#!/usr/bin/env python3
"""
Enrich movie documents in Vespa with TMDB metadata.

New fields added to the movie schema:
  - overview              (text, BM25-indexed)  — plot summary
  - original_language     (string attribute)    — e.g. "en", "fr", "ko"
  - runtime               (int attribute)       — minutes
  - production_countries  (array<string>)       — ISO 3166-1 codes, e.g. ["US", "GB"]

Usage:
    # 1. Deploy updated schema only (no TMDB key needed):
    python enrich.py --deploy-only

    # 2. Enrich all ~62 K movies and re-feed:
    TMDB_API_KEY=your_key python enrich.py

    # 3. Enrich a small sample (good for demos):
    TMDB_API_KEY=your_key python enrich.py --limit 500

    # 4. Re-feed without re-deploying the schema:
    TMDB_API_KEY=your_key python enrich.py --skip-deploy

    Get a free TMDB API key at: https://www.themoviedb.org/settings/api
"""

import argparse
import csv
import io
import os
import re
import time
import zipfile

import requests
from vespa.application import Vespa

VESPA_CONFIG_URL = os.environ.get("VESPA_CONFIG_URL", "http://localhost:19071")
VESPA_FEED_URL   = os.environ.get("VESPA_FEED_URL",   "http://localhost:8080")
DATA_DIR         = os.environ.get("DATA_DIR",          "./ml-25m")
TMDB_API_KEY     = os.environ.get("TMDB_API_KEY",      "")
NAMESPACE        = "movielens"
SCHEMAS_DIR      = os.path.join(os.path.dirname(__file__), "schemas")
TMDB_BASE        = "https://api.themoviedb.org/3/movie"

# TMDB free tier: 40 requests / 10 s  →  stay comfortably under with 3.5 req/s
_TMDB_MIN_INTERVAL = 1.0 / 3.5
_last_tmdb_call = 0.0


# ── TMDB ──────────────────────────────────────────────────────────────────────

def tmdb_fetch(tmdb_id: str) -> dict:
    """Fetch movie details from TMDB, respecting rate limits."""
    global _last_tmdb_call
    elapsed = time.monotonic() - _last_tmdb_call
    if elapsed < _TMDB_MIN_INTERVAL:
        time.sleep(_TMDB_MIN_INTERVAL - elapsed)
    _last_tmdb_call = time.monotonic()

    resp = requests.get(
        f"{TMDB_BASE}/{tmdb_id}",
        params={"api_key": TMDB_API_KEY},
        timeout=10,
    )
    if resp.status_code == 404:
        return {}
    if resp.status_code == 429:
        retry_after = int(resp.headers.get("Retry-After", 10))
        print(f"  TMDB rate-limited — sleeping {retry_after}s")
        time.sleep(retry_after)
        return tmdb_fetch(tmdb_id)
    resp.raise_for_status()
    return resp.json()


def tmdb_fields(tmdb: dict) -> dict:
    """Extract only the fields we care about from a TMDB response."""
    out = {}
    if tmdb.get("overview"):
        out["overview"] = tmdb["overview"]
    if tmdb.get("original_language"):
        out["original_language"] = tmdb["original_language"]
    if tmdb.get("runtime"):
        out["runtime"] = tmdb["runtime"]
    countries = [c["iso_3166_1"] for c in tmdb.get("production_countries", [])]
    if countries:
        out["production_countries"] = countries
    return out


# ── Document helpers ───────────────────────────────────────────────────────────

def parse_year(title: str) -> int | None:
    match = re.search(r'\((\d{4})\)\s*$', title.strip())
    return int(match.group(1)) if match else None


def load_links(data_dir: str) -> dict:
    links = {}
    with open(os.path.join(data_dir, "links.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            links[row["movieId"]] = {
                "imdb_id": row["imdbId"],
                "tmdb_id": row["tmdbId"],
            }
    return links


def iter_enriched_movies(data_dir: str, limit: int | None = None):
    """Yield (doc_id, fields) for every movie, enriched with TMDB data."""
    links = load_links(data_dir)
    count = 0

    with open(os.path.join(data_dir, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if limit is not None and count >= limit:
                break

            mid     = row["movieId"]
            link    = links.get(mid, {})
            tmdb_id = link.get("tmdb_id", "")
            genres  = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]

            fields: dict = {
                "movie_id": int(mid),
                "title":    row["title"],
                "genres":   genres,
                "imdb_id":  link.get("imdb_id", ""),
                "tmdb_id":  tmdb_id,
            }
            year = parse_year(row["title"])
            if year is not None:
                fields["year"] = year

            if tmdb_id and TMDB_API_KEY:
                fields.update(tmdb_fields(tmdb_fetch(tmdb_id)))

            count += 1
            if count % 500 == 0:
                print(f"  {count:,} movies processed...")

            yield mid, fields


# ── Vespa feed ────────────────────────────────────────────────────────────────

def feed_movies(feed_url: str, docs_iter) -> tuple[int, int]:
    app = Vespa(url=feed_url)
    fed = 0
    failed = 0

    def callback(response, doc_id):
        nonlocal fed, failed
        if response.status_code == 200:
            fed += 1
        else:
            failed += 1
            print(f"  WARN movie/{doc_id}: {response.status_code}")
        total = fed + failed
        if total % 5_000 == 0:
            print(f"  movie: {total:,} fed ({failed:,} failed)")

    app.feed_async_iterable(
        iter=docs_iter,
        schema="movie",
        namespace=NAMESPACE,
        callback=callback,
        max_queue_size=1_000,
        max_workers=16,
        max_connections=1,
    )
    return fed, failed


# ── Schema deploy ─────────────────────────────────────────────────────────────

def services_xml() -> str:
    return """\
<?xml version="1.0" encoding="utf-8" ?>
<services version="1.0">
  <container id="default" version="1.0">
    <document-api/>
    <search/>
    <nodes>
      <node hostalias="node1"/>
    </nodes>
  </container>
  <content id="content" version="1.0">
    <redundancy>1</redundancy>
    <documents>
      <document type="movie" mode="index"/>
      <document type="rating" mode="index"/>
      <document type="tag" mode="index"/>
    </documents>
    <nodes>
      <node hostalias="node1" distribution-key="0"/>
    </nodes>
  </content>
</services>
"""


def hosts_xml() -> str:
    return """\
<?xml version="1.0" encoding="utf-8" ?>
<hosts>
  <host name="localhost">
    <alias>node1</alias>
  </host>
</hosts>
"""


def build_app_package() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("services.xml", services_xml())
        zf.writestr("hosts.xml", hosts_xml())
        for sd_file in os.listdir(SCHEMAS_DIR):
            if sd_file.endswith(".sd"):
                with open(os.path.join(SCHEMAS_DIR, sd_file), encoding="utf-8") as f:
                    zf.writestr(f"schemas/{sd_file}", f.read())
    return buf.getvalue()


def deploy(config_url: str, package_bytes: bytes) -> None:
    base = f"{config_url}/application/v2/tenant/default"

    resp = requests.post(
        f"{base}/session",
        data=package_bytes,
        headers={"Content-Type": "application/zip"},
        timeout=60,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"Session create failed [{resp.status_code}]: {resp.text}")
    body = resp.json()
    session_id  = body["session-id"]
    prepare_url = body["prepared"]
    print(f"  Session {session_id} created.")

    resp = requests.put(prepare_url, timeout=60)
    if resp.status_code != 200:
        raise RuntimeError(f"Prepare failed [{resp.status_code}]: {resp.text}")
    body = resp.json()
    for entry in body.get("log", []):
        if entry.get("level") in ("WARNING", "ERROR"):
            print(f"  [{entry['level']}] {entry.get('message', '')}")
    activate_url = body["activate"]

    resp = requests.put(activate_url, timeout=60)
    if resp.status_code != 200:
        raise RuntimeError(f"Activate failed [{resp.status_code}]: {resp.text}")
    print(f"  Deployed: session {session_id} activated.")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enrich Vespa movie documents with TMDB metadata.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--deploy-only", action="store_true",
        help="Deploy the updated schema and exit (no TMDB calls).",
    )
    parser.add_argument(
        "--skip-deploy", action="store_true",
        help="Skip schema deployment and go straight to feeding.",
    )
    parser.add_argument(
        "--limit", type=int, default=None, metavar="N",
        help="Enrich only the first N movies (useful for demos).",
    )
    args = parser.parse_args()

    if not args.skip_deploy:
        print("Building and deploying updated schema...")
        deploy(VESPA_CONFIG_URL, build_app_package())

    if args.deploy_only:
        print("Done. Schema deployed — run without --deploy-only to enrich data.")
        return

    if not TMDB_API_KEY:
        print("ERROR: set TMDB_API_KEY before running enrichment.")
        print("       Get a free key at https://www.themoviedb.org/settings/api")
        raise SystemExit(1)

    limit_msg = f" (first {args.limit:,})" if args.limit else ""
    print(f"\nEnriching movies{limit_msg} — fetching from TMDB at ~3.5 req/s...")
    if args.limit:
        eta_min = args.limit / 3.5 / 60
        print(f"  Estimated time: ~{eta_min:.0f} min for {args.limit:,} movies")

    docs = (
        {"id": doc_id, "fields": fields}
        for doc_id, fields in iter_enriched_movies(DATA_DIR, limit=args.limit)
    )
    fed, failed = feed_movies(VESPA_FEED_URL, docs)
    print(f"\nDone: {fed:,} fed, {failed:,} failed.")


if __name__ == "__main__":
    main()
