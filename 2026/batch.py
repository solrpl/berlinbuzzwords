#!/usr/bin/env python3
import csv
import io
import json
import os
import re
import time
import zipfile

import requests
from vespa.application import Vespa

VESPA_CONFIG_URL = os.environ.get("VESPA_CONFIG_URL", "http://localhost:19071")
VESPA_FEED_URL = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")
DATA_DIR = os.environ.get("DATA_DIR", "./ml-25m")
NAMESPACE = "movielens"


def movie_schema() -> str:
    return """\
schema movie {
    document movie {
        field movie_id type int {
            indexing: attribute | summary
        }
        field title type string {
            indexing: index | summary
            index: enable-bm25
        }
        field genres type array<string> {
            indexing: attribute | summary
        }
        field year type int {
            indexing: attribute | summary
        }
        field imdb_id type string {
            indexing: attribute | summary
        }
        field tmdb_id type string {
            indexing: attribute | summary
        }
    }
}
"""


def rating_schema() -> str:
    return """\
schema rating {
    document rating {
        field user_id type int {
            indexing: attribute | summary
        }
        field movie_id type int {
            indexing: attribute | summary
        }
        field rating type float {
            indexing: attribute | summary
        }
        field timestamp type long {
            indexing: attribute | summary
        }
    }
}
"""


def tag_schema() -> str:
    return """\
schema tag {
    document tag {
        field user_id type int {
            indexing: attribute | summary
        }
        field movie_id type int {
            indexing: attribute | summary
        }
        field tag type string {
            indexing: index | summary
            index: enable-bm25
        }
        field timestamp type long {
            indexing: attribute | summary
        }
    }
}
"""


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


def movie_doc(row: dict, links: dict) -> tuple:
    mid = row["movieId"]
    link = links.get(mid, {})
    genres = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
    fields = {
        "movie_id": int(mid),
        "title": row["title"],
        "genres": genres,
        "imdb_id": link.get("imdb_id", ""),
        "tmdb_id": link.get("tmdb_id", ""),
    }
    year = parse_year(row["title"])
    if year is not None:
        fields["year"] = year
    return mid, fields


def rating_doc(row: dict) -> tuple:
    uid, mid = row["userId"], row["movieId"]
    return f"rating_{uid}_{mid}", {
        "user_id": int(uid),
        "movie_id": int(mid),
        "rating": float(row["rating"]),
        "timestamp": int(row["timestamp"]),
    }


def tag_doc(row: dict) -> tuple:
    uid, mid, ts = row["userId"], row["movieId"], row["timestamp"]
    return f"tag_{uid}_{mid}_{ts}", {
        "user_id": int(uid),
        "movie_id": int(mid),
        "tag": row["tag"],
        "timestamp": int(ts),
    }


def iter_movies(data_dir: str):
    links = load_links(data_dir)
    with open(os.path.join(data_dir, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            yield movie_doc(row, links)


def iter_ratings(data_dir: str):
    with open(os.path.join(data_dir, "ratings.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            yield rating_doc(row)


def iter_tags(data_dir: str):
    with open(os.path.join(data_dir, "tags.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            yield tag_doc(row)


def delete_all(feed_url: str, doctype: str) -> None:
    """Delete all documents of a given doctype via the visit API."""
    url = f"{feed_url}/document/v1/{NAMESPACE}/{doctype}/docid"
    deleted = 0
    params = {"selection": "true", "cluster": "content"}
    while True:
        resp = requests.delete(url, params=params, timeout=300)
        if resp.status_code not in (200, 201):
            raise RuntimeError(f"Delete visit failed [{resp.status_code}]: {resp.text}")
        body = resp.json()
        deleted += body.get("documentCount", 0)
        continuation = body.get("continuation")
        if not continuation:
            break
        params["continuation"] = continuation
    print(f"  Deleted {deleted:,} {doctype} documents.")


def wait_for_ready(feed_url: str, retries: int = 30, delay: float = 2.0) -> None:
    health_url = f"{feed_url}/state/v1/health"
    print(f"Waiting for Vespa to be ready at {feed_url}...", end="", flush=True)
    for _ in range(retries):
        try:
            resp = requests.get(health_url, timeout=5)
            if resp.status_code == 200 and resp.json().get("status", {}).get("code") == "up":
                print(" ready.")
                return
        except requests.exceptions.RequestException:
            pass
        print(".", end="", flush=True)
        time.sleep(delay)
    raise RuntimeError(f"Vespa not ready after {retries * delay:.0f}s — aborting.")


def feed(feed_url: str, doctype: str, docs_iter, queue_size: int = 1000) -> tuple:
    app = Vespa(url=feed_url)
    fed = 0
    failed = 0

    def callback(response, doc_id):
        nonlocal fed, failed
        if response.status_code == 200:
            fed += 1
        else:
            failed += 1
            print(f"  WARN {doctype}/{doc_id}: {response.status_code}")
        total = fed + failed
        if total % 100_000 == 0:
            print(f"  {doctype}: {total:,} processed ({failed:,} failed)")

    def feed_data(docs):
        app.feed_async_iterable(
            iter=docs,
            schema=doctype,
            namespace=NAMESPACE,
            callback=callback,
            max_queue_size=queue_size,
            max_workers=64,
            max_connections=1,
        )

    feed_data({"id": doc_id, "fields": fields} for doc_id, fields in docs_iter)
    return fed, failed


def deploy(config_url: str, package_bytes: bytes) -> None:
    base = f"{config_url}/application/v2/tenant/default"

    # Step 1: create a session by uploading the ZIP
    resp = requests.post(
        f"{base}/session",
        data=package_bytes,
        headers={"Content-Type": "application/zip"},
        timeout=60,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"Session create failed [{resp.status_code}]: {resp.text}")
    body = resp.json()
    session_id = body["session-id"]
    prepare_url = body["prepared"]
    print(f"  Session {session_id} created.")

    # Step 2: prepare — surfaces schema validation errors
    resp = requests.put(prepare_url, timeout=60)
    if resp.status_code != 200:
        raise RuntimeError(f"Prepare failed [{resp.status_code}]: {resp.text}")
    body = resp.json()
    for entry in body.get("log", []):
        if entry.get("level") in ("WARNING", "ERROR"):
            print(f"  [{entry['level']}] {entry.get('message', '')}")
    activate_url = body["activate"]

    # Step 3: activate
    resp = requests.put(activate_url, timeout=60)
    if resp.status_code != 200:
        raise RuntimeError(f"Activate failed [{resp.status_code}]: {resp.text}")
    print(f"Deployed successfully: session {session_id} activated.")


SCHEMAS_DIR = os.path.join(os.path.dirname(__file__), "schemas")


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


def hosts_xml() -> str:
    return """\
<?xml version="1.0" encoding="utf-8" ?>
<hosts>
  <host name="localhost">
    <alias>node1</alias>
  </host>
</hosts>
"""


def main() -> None:
    print("Building app package...")
    pkg = build_app_package()

    print(f"Deploying to {VESPA_CONFIG_URL}...")
    deploy(VESPA_CONFIG_URL, pkg)
    wait_for_ready(VESPA_FEED_URL)

    results = {}

    for doctype, iterator, queue_size in [
        ("movie",  iter_movies(DATA_DIR),  1_000),
        ("rating", iter_ratings(DATA_DIR), 10_000),
        ("tag",    iter_tags(DATA_DIR),    10_000),
    ]:
        print(f"\nDeleting existing {doctype} documents...")
        delete_all(VESPA_FEED_URL, doctype)
        print(f"Feeding {doctype}s...")
        fed, failed = feed(VESPA_FEED_URL, doctype, iterator, queue_size=queue_size)
        results[doctype] = (fed, failed)
        print(f"  {doctype}: {fed:,} fed, {failed:,} failed")

    print("\n=== Summary ===")
    for doctype, (fed, failed) in results.items():
        print(f"  {doctype:8s}: {fed:>10,} fed  {failed:>6,} failed")


if __name__ == "__main__":
    main()
