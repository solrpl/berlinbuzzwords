#%%python
# Shared imports and helpers
import csv
import json
import os
import re

import fasttext
import numpy as np
import requests

DATA_DIR  = os.environ.get("DATA_DIR",       "./ml-25m")
VESPA_URL = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")
NAMESPACE = "movielens"   # matches the deployed app (batch.py)

def clean(text: str) -> str:
    text = re.sub(r'\(\d{4}\)', '', text).lower()
    text = re.sub(r'[^a-z0-9 ]', ' ', text)
    return re.sub(r'\s+', ' ', text).strip()

def movie_text(title: str, genres: list, overview: str = "") -> str:
    parts = [clean(title)] + [clean(g) for g in genres]
    if overview:
        parts.append(clean(overview))
    return " ".join(p for p in parts if p)

def load_movies() -> dict:
    movies = {}
    with open(os.path.join(DATA_DIR, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            genres = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
            movies[row["movieId"]] = {"title": row["title"], "genres": genres}
    return movies

def embed(model, text: str) -> np.ndarray:
    words = clean(text).split()
    if not words:
        return np.zeros(model.get_dimension(), dtype=np.float32)
    vecs = np.array([model.get_word_vector(w) for w in words], dtype=np.float32)
    vec = vecs.mean(axis=0)
    norm = np.linalg.norm(vec)
    return (vec / norm).astype(np.float32) if norm > 0 else vec

print("Helpers ready.")

#%%python
# 1. Build training corpus
CORPUS_PATH = "/tmp/fasttext_corpus.txt"

movies = load_movies()
print(f"Movies loaded: {len(movies):,}")

with open(CORPUS_PATH, "w", encoding="utf-8") as f:
    for mid, m in movies.items():
        line = movie_text(m["title"], m["genres"])
        if line:
            f.write(line + "\n")

print(f"Corpus written: {CORPUS_PATH}  ({len(movies):,} lines)")
print("Sample lines:")
with open(CORPUS_PATH) as f:
    for _ in range(5):
        print(" ", f.readline().rstrip())

#%%python
# 2. Train FastText model
MODEL_PATH = "/tmp/fasttext.bin"

model = fasttext.train_unsupervised(
    CORPUS_PATH,
    model="skipgram",
    dim=100,
    epoch=5,
    minCount=1,
    thread=os.cpu_count() or 4,
)
model.save_model(MODEL_PATH)
print(f"Model trained and saved: {MODEL_PATH}")
print(f"Vocabulary size: {len(model.words):,}")
print(f"Embedding dim:   {model.get_dimension()}")

# Quick sanity check — nearest neighbours for a few words
for word in ["action", "comedy", "alien", "love"]:
    neighbours = model.get_nearest_neighbors(word, k=5)
    print(f"  {word:10s} → {[w for _, w in neighbours]}")

#%%python
# 3. Compute embeddings and feed to Vespa as partial updates
from concurrent.futures import ThreadPoolExecutor, as_completed

def _partial_update(mid_vec):
    mid, vec = mid_vec
    resp = requests.put(
        f"{VESPA_URL}/document/v1/{NAMESPACE}/movie/docid/{mid}",
        json={"fields": {"embedding_fasttext": {"assign": {"values": vec}}}},
        timeout=10,
    )
    return resp.status_code == 200

items = [
    (mid, embed(model, movie_text(m["title"], m["genres"])).tolist())
    for mid, m in movies.items()
]
print(f"Feeding {len(items):,} embeddings to Vespa…")

fed = failed = 0
with ThreadPoolExecutor(max_workers=32) as pool:
    futures = {pool.submit(_partial_update, item): item[0] for item in items}
    for i, future in enumerate(as_completed(futures), 1):
        if future.result():
            fed += 1
        else:
            failed += 1
        if i % 5_000 == 0:
            print(f"  {i:,} / {len(items):,}  ({failed} failed)")

print(f"Done: {fed:,} fed, {failed:,} failed.")

#%%python
# 4. Test query embedding
_query = "sci-fi space adventure"
_vec   = embed(model, _query)

print(f"Query : '{_query}'")
print(f"Dim   : {len(_vec)}")
print(f"Norm  : {np.linalg.norm(_vec):.6f}")
print(f"[:8]  : {_vec[:8].tolist()}")

#%%python
# 5. BM25 vs FastText — side-by-side comparison
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec

def search_bm25(query: str, n: int = 10) -> list:
    resp = requests.get(
        f"{VESPA_URL}/search/",
        params={
            "yql": f"select title, genres from movie where userQuery() limit {n}",
            "query": query,
            "ranking": "bm25",
            "hits": n,
        },
        timeout=10,
    ).json()
    errors = resp.get("root", {}).get("errors", [])
    if errors:
        print("BM25 errors:", errors)
    return [
        {"title": h["fields"].get("title", "?"),
         "genres": h["fields"].get("genres", []),
         "score": h["relevance"]}
        for h in resp.get("root", {}).get("children", [])
    ]

def search_fasttext(query: str, n: int = 10) -> list:
    vec = embed(model, query)
    resp = requests.post(
        f"{VESPA_URL}/search/",
        json={
            "yql": f"select title, genres from movie where {{targetHits: {n}}} nearestNeighbor(embedding_fasttext, q)",
            "ranking": "semantic-fasttext",
            "input.query(q)": {"values": vec.tolist()},
            "hits": n,
        },
        timeout=10,
    ).json()
    errors = resp.get("root", {}).get("errors", [])
    if errors:
        print("Errors:", errors)
    return [
        {"title": h["fields"].get("title", "?"),
         "genres": h["fields"].get("genres", []),
         "score": h["relevance"]}
        for h in resp.get("root", {}).get("children", [])
    ]

def shorten(title: str, n: int = 38) -> str:
    return title[:n] + "…" if len(title) > n else title

def compare(query: str) -> None:
    bm25_hits    = search_bm25(query)
    fasttext_hits = search_fasttext(query)

    fig = plt.figure(figsize=(14, 6))
    fig.suptitle(f'Query: "{query}"', fontsize=13, fontweight="bold", y=1.01)
    gs = gridspec.GridSpec(1, 2, figure=fig, wspace=0.05)

    for col, (hits, label, color) in enumerate([
        (bm25_hits,     "BM25",    "steelblue"),
        (fasttext_hits, "FastText","mediumseagreen"),
    ]):
        ax = fig.add_subplot(gs[col])
        if not hits:
            ax.text(0.5, 0.5, "no results", ha="center", va="center", transform=ax.transAxes)
        else:
            titles = [shorten(h["title"]) for h in hits]
            scores = [h["score"] for h in hits]
            norm   = max(scores) if max(scores) > 0 else 1
            bars   = ax.barh(range(len(titles)), [s / norm for s in scores],
                             color=color, alpha=0.85)
            ax.set_yticks(range(len(titles)))
            ax.set_yticklabels(titles, fontsize=9)
            ax.invert_yaxis()
            ax.set_xlim(0, 1.15)
            ax.set_xlabel("Normalised score")
            for i, (bar, h) in enumerate(zip(bars, hits)):
                genres = ", ".join(h["genres"][:2])
                ax.text(bar.get_width() + 0.02, i, genres,
                        va="center", fontsize=7, color="grey")
        ax.set_title(label, fontsize=11, color=color, fontweight="bold")
        if col == 1:
            ax.yaxis.set_visible(False)

    plt.tight_layout()
    plt.show()
    plt.close(fig)

# Try a few queries
for _q in ["sci-fi space adventure", "heist thriller", "love story paris"]:
    compare(_q)