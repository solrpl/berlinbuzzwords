#!/usr/bin/env python3
"""
Train a FastText model on the MovieLens corpus and generate document embeddings.

Pipeline:
  1. Build a text corpus (title + genres + optional overview per movie)
  2. Train a FastText skip-gram model on that corpus
  3. Compute a document vector for each movie (mean-pooling of word vectors, L2-normalised)
  4. Write a Vespa partial-update JSONL — feed it with `vespa feed <output>`

Usage:
    # Titles + genres only (no Vespa connection required)
    python train_fasttext.py

    # Include overviews fetched from Vespa (run enrich.py first)
    python train_fasttext.py --with-overviews

    # Inspect the trained model with a test query
    python train_fasttext.py --query "sci-fi space adventure"

    Feed the result:
        vespa feed fasttext_feed.jsonl

Environment variables:
    DATA_DIR         path to ml-25m directory  (default: ./ml-25m)
    VESPA_FEED_URL   Vespa query endpoint       (default: http://localhost:8080)
"""

import argparse
import csv
import json
import os
import re

import fasttext
import numpy as np
import requests

DATA_DIR     = os.environ.get("DATA_DIR",       "./ml-25m")
VESPA_URL    = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")
NAMESPACE    = "movies"   # matches vespa_app/to_vespa_feed.py
MODEL_DIM    = 100
MODEL_PATH   = "fasttext.bin"
CORPUS_PATH  = "fasttext_corpus.txt"
OUTPUT_PATH  = "fasttext_feed.jsonl"


# ── Text helpers ──────────────────────────────────────────────────────────────

def clean(text: str) -> str:
    """Lowercase, strip year in parens, collapse to a-z / digits / spaces."""
    text = re.sub(r'\(\d{4}\)', '', text)
    text = text.lower()
    text = re.sub(r'[^a-z0-9 ]', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()


def movie_text(title: str, genres: list[str], overview: str = "") -> str:
    parts = [clean(title)]
    parts.extend(clean(g) for g in genres)
    if overview:
        parts.append(clean(overview))
    return " ".join(p for p in parts if p)


# ── Data loading ──────────────────────────────────────────────────────────────

def load_movies(data_dir: str) -> dict:
    """Return {movie_id_str: {title, genres}} from movies.csv."""
    movies = {}
    with open(os.path.join(data_dir, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            genres = [
                g for g in row["genres"].split("|")
                if g and g != "(no genres listed)"
            ]
            movies[row["movieId"]] = {"title": row["title"], "genres": genres}
    return movies


def fetch_overviews(movie_ids: list[str], batch_size: int = 400) -> dict:
    """Fetch overview fields from Vespa. Returns {movie_id_str: overview}."""
    overviews: dict = {}
    total = len(movie_ids)
    for i in range(0, total, batch_size):
        chunk = movie_ids[i : i + batch_size]
        id_filter = " OR ".join(f"movie_id = {mid}" for mid in chunk)
        try:
            body = requests.get(
                f"{VESPA_URL}/search/",
                params={
                    "yql": f"select movie_id, overview from movie"
                           f" where {id_filter} limit {batch_size}",
                    "timeout": "10s",
                },
                timeout=15,
            ).json()
            for hit in body.get("root", {}).get("children", []):
                f = hit.get("fields", {})
                if f.get("overview"):
                    overviews[str(f["movie_id"])] = f["overview"]
        except Exception as exc:
            print(f"  WARN: overview fetch failed for batch {i}: {exc}")
        if (i // batch_size + 1) % 10 == 0 or i + batch_size >= total:
            print(f"  Overviews fetched: {min(i + batch_size, total):,} / {total:,}")
    return overviews


# ── Corpus & training ─────────────────────────────────────────────────────────

def build_corpus(movies: dict, overviews: dict, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for mid, m in movies.items():
            line = movie_text(m["title"], m["genres"], overviews.get(mid, ""))
            if line:
                f.write(line + "\n")
    print(f"  Corpus: {path}  ({len(movies):,} lines)")


def train_model(corpus_path: str, model_path: str, dim: int) -> "fasttext.FastText._FastText":
    print(f"  Training FastText skip-gram (dim={dim}, epoch=5)...")
    model = fasttext.train_unsupervised(
        corpus_path,
        model="skipgram",
        dim=dim,
        epoch=5,
        minCount=1,
        thread=os.cpu_count() or 4,
    )
    model.save_model(model_path)
    print(f"  Model saved: {model_path}")
    return model


# ── Embedding helpers ─────────────────────────────────────────────────────────

def embed(model: "fasttext.FastText._FastText", text: str) -> np.ndarray:
    """Mean of word vectors for the cleaned text, L2-normalised."""
    words = clean(text).split()
    if not words:
        return np.zeros(model.get_dimension(), dtype=np.float32)
    vecs = np.array([model.get_word_vector(w) for w in words], dtype=np.float32)
    vec = vecs.mean(axis=0)
    norm = np.linalg.norm(vec)
    return (vec / norm).astype(np.float32) if norm > 0 else vec


# ── Feed output ───────────────────────────────────────────────────────────────

def write_feed(
    movies: dict,
    overviews: dict,
    model: "fasttext.FastText._FastText",
    output_path: str,
) -> None:
    written = 0
    with open(output_path, "w", encoding="utf-8") as f:
        for mid, m in movies.items():
            text = movie_text(m["title"], m["genres"], overviews.get(mid, ""))
            vec  = embed(model, text)
            doc  = {
                "update": f"id:{NAMESPACE}:movie::{mid}",
                "fields": {
                    "embedding_fasttext": {
                        "assign": {"values": vec.tolist()}
                    }
                },
            }
            f.write(json.dumps(doc) + "\n")
            written += 1
            if written % 10_000 == 0:
                print(f"  {written:,} vectors written...")
    print(f"  Feed written: {output_path}  ({written:,} documents)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train FastText and produce a Vespa embedding feed.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--with-overviews", action="store_true",
        help="Fetch plot overviews from Vespa to enrich the training corpus.",
    )
    parser.add_argument("--output",  default=OUTPUT_PATH, metavar="FILE",
                        help=f"Output JSONL path (default: {OUTPUT_PATH})")
    parser.add_argument("--model",   default=MODEL_PATH,  metavar="FILE",
                        help=f"FastText model save path (default: {MODEL_PATH})")
    parser.add_argument("--dim",     type=int, default=MODEL_DIM, metavar="N",
                        help=f"Embedding dimensions (default: {MODEL_DIM})")
    parser.add_argument("--query",   default=None, metavar="TEXT",
                        help="Embed a test query with the trained model and print the vector stats.")
    args = parser.parse_args()

    print("Loading movies from CSV...")
    movies = load_movies(DATA_DIR)
    print(f"  {len(movies):,} movies.")

    overviews: dict = {}
    if args.with_overviews:
        print("Fetching overviews from Vespa...")
        overviews = fetch_overviews(list(movies.keys()))
        print(f"  {len(overviews):,} overviews retrieved.")

    print("Building training corpus...")
    build_corpus(movies, overviews, CORPUS_PATH)

    print("Training FastText model...")
    model = train_model(CORPUS_PATH, args.model, dim=args.dim)

    if args.query:
        vec = embed(model, args.query)
        print(f"\nQuery : '{args.query}'")
        print(f"Dim   : {len(vec)}")
        print(f"Norm  : {np.linalg.norm(vec):.6f}")
        print(f"[:8]  : {vec[:8].tolist()}")
        return

    print("Writing Vespa feed JSONL...")
    write_feed(movies, overviews, model, args.output)

    print(f"""
=== Next steps ===

1. Deploy the updated schema (adds embedding_fasttext field):
       vespa deploy vespa_app/

2. Re-feed movies (only needed if you changed schema fields other than the tensor):
       python vespa_app/to_vespa_feed.py ml-25m/movies.csv | vespa feed -

3. Feed the FastText embeddings (partial updates — safe to run on top of existing docs):
       vespa feed {args.output}

4. Test an ANN query in experiments/queries.nr  (see the semantic-fasttext cells)
""")


if __name__ == "__main__":
    main()
