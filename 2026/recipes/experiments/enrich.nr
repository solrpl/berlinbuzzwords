#%%python
# Shared config and helpers
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
DATA_DIR         = "./ml-25m"
SCHEMAS_DIR      = "./schemas"
TMDB_API_KEY     = os.environ.get("TMDB_API_KEY", "")
NAMESPACE        = "movielens"
TMDB_BASE        = "https://api.themoviedb.org/3/movie"

_TMDB_MIN_INTERVAL = 1.0 / 3.5   # 3.5 req/s — safely under the 40/10s free-tier limit
_last_tmdb_call = 0.0

def tmdb_fetch(tmdb_id: str) -> dict:
    global _last_tmdb_call
    elapsed = time.monotonic() - _last_tmdb_call
    if elapsed < _TMDB_MIN_INTERVAL:
        time.sleep(_TMDB_MIN_INTERVAL - elapsed)
    _last_tmdb_call = time.monotonic()
    resp = requests.get(f"{TMDB_BASE}/{tmdb_id}", params={"api_key": TMDB_API_KEY}, timeout=10)
    if resp.status_code == 404:
        return {}
    if resp.status_code == 429:
        retry_after = int(resp.headers.get("Retry-After", 10))
        print(f"  Rate-limited — sleeping {retry_after}s")
        time.sleep(retry_after)
        return tmdb_fetch(tmdb_id)
    resp.raise_for_status()
    return resp.json()

def tmdb_fields(tmdb: dict) -> dict:
    out = {}
    if tmdb.get("overview"):        out["overview"]  = tmdb["overview"]
    if tmdb.get("original_language"): out["original_language"] = tmdb["original_language"]
    if tmdb.get("runtime"):         out["runtime"]   = tmdb["runtime"]
    countries = [c["iso_3166_1"] for c in tmdb.get("production_countries", [])]
    if countries:                   out["production_countries"] = countries
    return out

def parse_year(title: str):
    m = re.search(r'\((\d{4})\)\s*$', title.strip())
    return int(m.group(1)) if m else None

def load_links() -> dict:
    links = {}
    with open(os.path.join(DATA_DIR, "links.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            links[row["movieId"]] = {"imdb_id": row["imdbId"], "tmdb_id": row["tmdbId"]}
    return links

print(f"TMDB_API_KEY set: {bool(TMDB_API_KEY)}")
print("Helpers ready.")

#%%python
# 1. Deploy schema (adds overview, original_language, runtime, production_countries,
#                   embedding_fasttext + rank profiles)
def services_xml():
    return """\
<?xml version="1.0" encoding="utf-8" ?>
<services version="1.0">
  <container id="default" version="1.0">
    <document-api/>
    <search/>
    <nodes><node hostalias="node1"/></nodes>
  </container>
  <content id="content" version="1.0">
    <redundancy>1</redundancy>
    <documents>
      <document type="movie"  mode="index"/>
      <document type="rating" mode="index"/>
      <document type="tag"    mode="index"/>
    </documents>
    <nodes><node hostalias="node1" distribution-key="0"/></nodes>
  </content>
</services>"""

def hosts_xml():
    return """\
<?xml version="1.0" encoding="utf-8" ?>
<hosts>
  <host name="localhost"><alias>node1</alias></host>
</hosts>"""

def build_package() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("services.xml", services_xml())
        zf.writestr("hosts.xml", hosts_xml())
        for sd in os.listdir(SCHEMAS_DIR):
            if sd.endswith(".sd"):
                with open(os.path.join(SCHEMAS_DIR, sd), encoding="utf-8") as f:
                    zf.writestr(f"schemas/{sd}", f.read())
    return buf.getvalue()

def deploy(pkg: bytes) -> None:
    base = f"{VESPA_CONFIG_URL}/application/v2/tenant/default"
    resp = requests.post(f"{base}/session", data=pkg,
                         headers={"Content-Type": "application/zip"}, timeout=60)
    resp.raise_for_status()
    body = resp.json()
    session_id, prepare_url = body["session-id"], body["prepared"]
    print(f"  Session {session_id} created.")
    resp = requests.put(prepare_url, timeout=60)
    resp.raise_for_status()
    for entry in resp.json().get("log", []):
        if entry.get("level") in ("WARNING", "ERROR"):
            print(f"  [{entry['level']}] {entry['message']}")
    activate_url = resp.json()["activate"]
    resp = requests.put(activate_url, timeout=60)
    resp.raise_for_status()
    print(f"  Deployed: session {session_id} activated.")

deploy(build_package())

#%%python
# 2. Preview: fetch one movie from TMDB
if not TMDB_API_KEY:
    print("Set TMDB_API_KEY in environment first.")
else:
    links = load_links()
    # Use Toy Story (movieId=1, tmdbId=862)
    sample = tmdb_fetch(links["1"]["tmdb_id"])
    for key in ("title", "original_language", "runtime", "overview", "production_countries"):
        val = sample.get(key, "—")
        if key == "overview" and isinstance(val, str) and len(val) > 120:
            val = val[:120] + "…"
        print(f"  {key:25s} {val}")

#%%python
# 3. Enrich a sample of 200 movies (demo — ~1 min at 3.5 req/s)
LIMIT = 200

if not TMDB_API_KEY:
    print("Set TMDB_API_KEY in environment first.")
else:
    links  = load_links()
    app    = Vespa(url=VESPA_FEED_URL)
    fed    = 0
    failed = 0
    eta    = LIMIT / 3.5 / 60
    print(f"Enriching {LIMIT} movies (~{eta:.0f} min)…")

    def _callback(response, doc_id):
        global fed, failed
        if response.status_code == 200:
            fed += 1
        else:
            failed += 1
            print(f"  WARN {doc_id}: {response.status_code}")

    def _iter(limit):
        count = 0
        with open(os.path.join(DATA_DIR, "movies.csv"), encoding="utf-8") as f:
            for row in csv.DictReader(f):
                if count >= limit:
                    break
                mid     = row["movieId"]
                link    = links.get(mid, {})
                tmdb_id = link.get("tmdb_id", "")
                genres  = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
                fields  = {
                    "movie_id": int(mid), "title": row["title"], "genres": genres,
                    "imdb_id": link.get("imdb_id", ""), "tmdb_id": tmdb_id,
                }
                year = parse_year(row["title"])
                if year:
                    fields["year"] = year
                if tmdb_id:
                    fields.update(tmdb_fields(tmdb_fetch(tmdb_id)))
                count += 1
                if count % 50 == 0:
                    print(f"  {count}/{limit} processed…")
                yield {"id": mid, "fields": fields}

    app.feed_async_iterable(
        iter=_iter(LIMIT), schema="movie", namespace=NAMESPACE,
        callback=_callback, max_queue_size=500, max_workers=8, max_connections=1,
    )
    print(f"Done: {fed} fed, {failed} failed.")

#%%python
# 4. Enrich ALL movies (~5 hours at 3.5 req/s — run overnight)
if not TMDB_API_KEY:
    print("Set TMDB_API_KEY in environment first.")
else:
    links  = load_links()
    app    = Vespa(url=VESPA_FEED_URL)
    fed    = 0
    failed = 0
    print("Enriching all movies… (Ctrl-C to stop safely)")

    def _callback_all(response, doc_id):
        global fed, failed
        if response.status_code == 200:
            fed += 1
        else:
            failed += 1
        total = fed + failed
        if total % 1_000 == 0:
            print(f"  {total:,} processed ({failed} failed)")

    def _iter_all():
        with open(os.path.join(DATA_DIR, "movies.csv"), encoding="utf-8") as f:
            for row in csv.DictReader(f):
                mid     = row["movieId"]
                link    = links.get(mid, {})
                tmdb_id = link.get("tmdb_id", "")
                genres  = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
                fields  = {
                    "movie_id": int(mid), "title": row["title"], "genres": genres,
                    "imdb_id": link.get("imdb_id", ""), "tmdb_id": tmdb_id,
                }
                year = parse_year(row["title"])
                if year:
                    fields["year"] = year
                if tmdb_id:
                    fields.update(tmdb_fields(tmdb_fetch(tmdb_id)))
                yield {"id": mid, "fields": fields}

    app.feed_async_iterable(
        iter=_iter_all(), schema="movie", namespace=NAMESPACE,
        callback=_callback_all, max_queue_size=1_000, max_workers=16, max_connections=1,
    )
    print(f"\nDone: {fed:,} fed, {failed:,} failed.")
