#!/usr/bin/env python3
"""Verify that MovieLens data is indexed in Vespa."""
import json
import os
import sys

import requests

VESPA_FEED_URL = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")


def count_docs(doctype: str) -> int:
    url = f"{VESPA_FEED_URL}/search/"
    resp = requests.get(url, params={"yql": f"select * from {doctype} where true", "hits": "0"}, timeout=10)
    resp.raise_for_status()
    return resp.json()["root"]["fields"]["totalCount"]


def fetch_doc(doctype: str, doc_id: str) -> dict:
    url = f"{VESPA_FEED_URL}/document/v1/movielens/{doctype}/docid/{doc_id}"
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    return resp.json()


def search(query: str, hits: int = 3) -> list[dict]:
    url = f"{VESPA_FEED_URL}/search/"
    resp = requests.get(url, params={"yql": query, "hits": str(hits)}, timeout=10)
    resp.raise_for_status()
    return resp.json()["root"].get("children", [])


def main() -> None:
    ok = True

    print("=== Document counts ===")
    for doctype in ("movie", "rating", "tag"):
        try:
            n = count_docs(doctype)
            print(f"  {doctype:8s}: {n:>12,}")
            if n == 0:
                print(f"  WARNING: no {doctype} documents found")
                ok = False
        except Exception as e:
            print(f"  {doctype:8s}: ERROR — {e}")
            ok = False

    print("\n=== Fetch movie docid/1 (Toy Story) ===")
    try:
        doc = fetch_doc("movie", "1")
        fields = doc.get("fields", {})
        print(f"  title : {fields.get('title')}")
        print(f"  year  : {fields.get('year')}")
        print(f"  genres: {fields.get('genres')}")
        print(f"  imdb  : {fields.get('imdb_id')}")
        print(f"  tmdb  : {fields.get('tmdb_id')}")
    except Exception as e:
        print(f"  ERROR — {e}")
        ok = False

    print("\n=== Full-text search: title contains 'toy' ===")
    try:
        hits = search("select title, year, genres from movie where title contains 'toy'", hits=3)
        if not hits:
            print("  No results")
            ok = False
        for hit in hits:
            f = hit.get("fields", {})
            print(f"  [{hit.get('relevance', 0):.4f}]  {f.get('title')}  ({f.get('year')})  {f.get('genres')}")
    except Exception as e:
        print(f"  ERROR — {e}")
        ok = False

    print()
    if ok:
        print("All checks passed.")
    else:
        print("Some checks failed — see above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
