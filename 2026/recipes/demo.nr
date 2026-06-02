#%%python
#H1 Flow Configuration
# 1. Config & shared helpers
# Edit the variables in this section, then run the cells in order.
import csv
import json
import os
import re
import subprocess
import threading
import time
from collections import Counter

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import polars as pl
import requests
from vespa.application import Vespa

try:
    import fasttext as ft
    import numpy as np
    HAS_FT = True
except ImportError:
    HAS_FT = False
    print("fasttext / numpy not available — embedding cells will be skipped")

# ── Vespa ──────────────────────────────────────────────────────────────────────
VESPA_CONFIG_URL = "http://localhost:19071"
VESPA_FEED_URL   = "http://localhost:8080"
NAMESPACE        = "movies"
VESPA_APP_DIR    = "./vespa_app"
# /Users/gro/praca/conferences/berlinbuzzwords/2026/vespa_app/
# /Users/radu/gits/berlinbuzzwords/2026/vespa_app/


# ── Data ───────────────────────────────────────────────────────────────────────
DATA_DIR = "./ml-25m/"
# /Users/gro/praca/conferences/berlinbuzzwords/2026/ml-25m/
# /Users/radu/gits/berlinbuzzwords/2026/dataset/movielens/ml-latest-small/


# ── TMDB ───────────────────────────────────────────────────────────────────────
TMDB_API_KEY = os.environ.get("TMDB_API_KEY", "")

# ── FastText ───────────────────────────────────────────────────────────────────
FT_MODEL_PATH  = "/tmp/fasttext.bin"
FT_CORPUS_PATH = "/tmp/fasttext_corpus.txt"

# ── Search helpers ─────────────────────────────────────────────────────────────
def search(yql: str, timeout: str = "30s", hits: int = 0, **kwargs) -> dict:
    resp = requests.get(
        f"{VESPA_FEED_URL}/search/",
        params={"yql": yql, "hits": hits, "timeout": timeout, **kwargs},
        timeout=60,
    )
    if not resp.ok:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:300]}")
    body = resp.json()
    for err in body.get("root", {}).get("errors", []):
        if "timeout" in err.get("message", "").lower():
            print("  Query timed out — skipping.")
            return {}
        raise RuntimeError(err["message"])
    return body

def groups(body: dict) -> list:
    try:
        return body["root"]["children"][0]["children"][0]["children"]
    except (KeyError, IndexError):
        return []

def show(fig) -> None:
    plt.show()
    plt.close(fig)

def _parse_year(title: str):
    m = re.search(r'\((\d{4})\)\s*$', title.strip())
    return int(m.group(1)) if m else None

# ── FastText helpers ───────────────────────────────────────────────────────────
_ft_model = None

def ft_load():
    global _ft_model
    if _ft_model is None:
        _ft_model = ft.load_model(FT_MODEL_PATH)
        print(f"FastText model loaded (dim={_ft_model.get_dimension()})")
    return _ft_model

def ft_embed(text: str):
    model = ft_load()
    words = re.sub(r'[^a-z0-9 ]', ' ', text.lower()).split()
    if not words:
        return np.zeros(model.get_dimension(), dtype=np.float32)
    vecs = np.array([model.get_word_vector(w) for w in words], dtype=np.float32)
    vec = vecs.mean(axis=0)
    norm = np.linalg.norm(vec)
    return (vec / norm).astype(np.float32) if norm > 0 else vec

print(f"Config ready  |  TMDB key: {'set' if TMDB_API_KEY else 'NOT SET'}  |  FastText: {HAS_FT}")

#%%python
# 2. Deploy vespa_app
print("Deploying vespa_app...")
# you'll need Vespa CLI for this (e.g., brew install vespa-cli)
subprocess.run(["vespa", "deploy", "--wait", "300"], cwd=VESPA_APP_DIR, check=True)
print("Deployed.")

#%%python
# 3. Index Movies
def _load_movies_for_feed():
    links = {}
    with open(os.path.join(DATA_DIR, "links.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            links[row["movieId"]] = {"imdb_id": row["imdbId"], "tmdb_id": row["tmdbId"]}
    docs = []
    with open(os.path.join(DATA_DIR, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            mid    = row["movieId"]
            link   = links.get(mid, {})
            genres = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
            fields = {
                "id":      mid,
                "title":   row["title"],
                "genres":  genres,
                "imdb_id": link.get("imdb_id", ""),
                "tmdb_id": link.get("tmdb_id", ""),
            }
            year = _parse_year(row["title"])
            if year:
                fields["year"] = year
            docs.append({"id": mid, "fields": fields})
    return docs

def _feed_docs(
    docs_iter,
    schema="movie",
    total=None,
    operation_type="feed",
    progress_every=1000,
    max_workers=64,
    **kwargs,
):
    app = Vespa(url=VESPA_FEED_URL)
    fed = failed = 0

    def _callback(response, doc_id):
        nonlocal fed, failed
        if response.is_successful():
            fed += 1
        else:
            failed += 1
            print(f"  WARN {schema}/{doc_id}: {response.status_code}")
        done = fed + failed
        if done % progress_every == 0:
            suffix = f" / {total:,}" if total is not None else ""
            print(f"  {done:,}{suffix}")

    errors = []

    def _run_feed():
        try:
            app.feed_async_iterable(
                iter=docs_iter,
                schema=schema,
                namespace=NAMESPACE,
                callback=_callback,
                operation_type=operation_type,
                max_queue_size=1_000,
                max_workers=max_workers,
                max_connections=1,
                **kwargs,
            )
        except BaseException as exc:
            errors.append(exc)

    # running from a separate thread to work around notebook limitations (asyncio.run() cannot be called from a running event loop)
    thread = threading.Thread(target=_run_feed)
    thread.start()
    thread.join()
    if errors:
        raise errors[0]
    return fed, failed

_movie_docs = _load_movies_for_feed()
print(f"Feeding {len(_movie_docs):,} movies with pyvespa async feed…")

fed, failed = _feed_docs(_movie_docs, total=len(_movie_docs))
print(f"Movies fed: {fed:,}  failed: {failed:,}")

#%%python
#H1 Getting to Know the Data
# 1. Is the data clean?
_total      = search("select * from movie where true limit 0")["root"]["fields"]["totalCount"]
_no_year    = search("select * from movie where !(year > 0) limit 0")["root"]["fields"]["totalCount"]
_no_genre   = search('select * from movie where genres contains "(no genres listed)" limit 0')["root"]["fields"]["totalCount"]
_year_kids  = groups(search("select * from movie where year > 0 limit 0 | all( group(year) max(200) each( output(count()) ))"))
_years      = sorted(int(c["value"]) for c in _year_kids)

print(f"Total movies    : {_total:,}")
print(f"Missing year    : {_no_year:,}  ({100*_no_year/_total:.1f}%)")
print(f"No genres listed: {_no_genre:,}  ({100*_no_genre/_total:.1f}%)")
print(f"Year range      : {_years[0]} – {_years[-1]}")

_df_yr = pl.DataFrame([{"year": int(c["value"]), "count": c["fields"]["count()"]} for c in _year_kids]).sort("year")
_colors = ["salmon" if y < 1930 else "steelblue" for y in _df_yr["year"].to_list()]

fig, axes = plt.subplots(1, 2, figsize=(13, 5))
axes[0].pie([_total - _no_year, _no_year], labels=["Have year", "No year"],
            colors=["steelblue", "salmon"], autopct="%1.1f%%", startangle=140)
axes[0].set_title("Year field coverage")
axes[1].bar(_df_yr["year"].to_list(), _df_yr["count"].to_list(), color=_colors, width=0.9)
axes[1].set_title("Year distribution  (red = pre-1930)")
axes[1].set_xlabel("Year"); axes[1].set_ylabel("Movies")
axes[1].grid(True, alpha=0.3, axis="y")
plt.tight_layout(); show(fig)

#%%python
# 2. Facets: genres & decades
_genre_ch = groups(search("select * from movie where true limit 0 | all( group(genres_att) max(25) each( output(count()) ))"))
_year_ch  = groups(search("select * from movie where year > 0 limit 0 | all( group(year) max(200) each( output(count()) ))"))

_genre_df  = pl.DataFrame([{"genre": c["value"], "movies": c["fields"]["count()"]} for c in _genre_ch]).sort("movies", descending=True)
_decade_df = (
    pl.DataFrame([{"year": int(c["value"]), "count": c["fields"]["count()"]} for c in _year_ch])
    .with_columns((pl.col("year") // 10 * 10).alias("decade"))
    .group_by("decade").agg(pl.col("count").sum()).sort("decade")
)

fig, axes = plt.subplots(1, 2, figsize=(15, 6))
axes[0].barh(_genre_df["genre"].to_list(), _genre_df["movies"].to_list(), color="mediumseagreen")
axes[0].set_title("Movies per Genre"); axes[0].set_xlabel("Count"); axes[0].invert_yaxis()
axes[0].grid(True, alpha=0.3, axis="x")
axes[1].bar([f"{d}s" for d in _decade_df["decade"].to_list()], _decade_df["count"].to_list(), color="darkorange")
axes[1].set_title("Movies per Decade"); axes[1].set_xlabel("Decade"); axes[1].set_ylabel("Count")
axes[1].grid(True, alpha=0.3, axis="y")
plt.xticks(rotation=45); plt.tight_layout(); show(fig)

#%%python
# 3. Significant terms in titles
_hits_resp = requests.get(
    f"{VESPA_FEED_URL}/search/",
    params={"yql": "select title from movie where true limit 400", "hits": 400, "timeout": "10s"},
    timeout=15,
).json()
_titles = [h["fields"]["title"] for h in _hits_resp.get("root", {}).get("children", []) if "title" in h.get("fields", {})]

if not _titles:
    print("No titles — check that movies are indexed.")
else:
    _stop = {"the","a","an","of","and","in","to","is","at","on","for","with","de","la","le","les","der","die","das"}
    _words = []
    for t in _titles:
        _clean = re.sub(r'\(\d{4}\)', '', t).lower()
        _words.extend(w for w in re.findall(r"[a-z']{3,}", _clean) if w not in _stop)
    _top = Counter(_words).most_common(30)

    fig, ax = plt.subplots(figsize=(12, 6))
    _bars = ax.bar([w for w, _ in _top], [c for _, c in _top], color="steelblue")
    for b in _bars[:5]: b.set_color("coral")
    ax.set_title("Most Frequent Words in Movie Titles  (top 5 highlighted)"); ax.set_xlabel("Word"); ax.set_ylabel("Count")
    ax.grid(True, alpha=0.3, axis="y"); plt.xticks(rotation=45, ha="right"); plt.tight_layout(); show(fig)

#%%python
#H1 Let's Enrich
# 1. Enrich with TMDB
# We use TMDB - https://www.themoviedb.org
# Feeds full documents (base fields + TMDB fields) so BM25 index on overview works.
# Set ENRICH_LIMIT to None to run all ~62K movies (~5 h).
ENRICH_LIMIT = None
RESUME_FROM  = 0   # ← set to last reported count to resume after a crash

if not TMDB_API_KEY:
    print("TMDB_API_KEY not set — skipping enrichment. Set it in cell 0.")
else:
    _TMDB_INTERVAL = 1.0 / 3.5
    _last_call = 0.0

    def _tmdb_fetch(tmdb_id: str) -> dict:
        global _last_call
        if not tmdb_id or tmdb_id == "0":
            return {}
        wait = _TMDB_INTERVAL - (time.monotonic() - _last_call)
        if wait > 0: time.sleep(wait)
        _last_call = time.monotonic()
        r = requests.get(f"https://api.themoviedb.org/3/movie/{tmdb_id}",
                         params={"api_key": TMDB_API_KEY}, timeout=10)
        if r.status_code in (404, 401): return {}
        if r.status_code == 429:
            time.sleep(int(r.headers.get("Retry-After", 10)))
            return _tmdb_fetch(tmdb_id)
        r.raise_for_status()
        try:
            return r.json()
        except Exception:
            return {}

    # Load all base movie data once
    _links_e = {}
    with open(os.path.join(DATA_DIR, "links.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            _links_e[row["movieId"]] = {"imdb_id": row["imdbId"], "tmdb_id": row["tmdbId"]}

    _base_movies = {}
    with open(os.path.join(DATA_DIR, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            mid    = row["movieId"]
            link   = _links_e.get(mid, {})
            genres = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
            fields = {
                "id": mid, "title": row["title"], "genres": genres,
                "imdb_id": link.get("imdb_id", ""), "tmdb_id": link.get("tmdb_id", ""),
            }
            year = _parse_year(row["title"])
            if year: fields["year"] = year
            _base_movies[mid] = fields

    _all_mids = list(_base_movies.keys())[RESUME_FROM:]
    if ENRICH_LIMIT:
        _all_mids = _all_mids[:ENRICH_LIMIT]
    print(f"Enriching {len(_all_mids):,} movies (skipping first {RESUME_FROM:,}) — ~{len(_all_mids)/3.5/60:.0f} min…")

    def _enriched_docs():
        for mid in _all_mids:
            fields   = dict(_base_movies[mid])          # copy base fields
            tmdb_id  = _links_e.get(mid, {}).get("tmdb_id", "")
            tmdb     = _tmdb_fetch(tmdb_id)
            if tmdb.get("overview"):          fields["overview"]             = tmdb["overview"]
            if tmdb.get("original_language"): fields["original_language"]    = tmdb["original_language"]
            if tmdb.get("runtime"):           fields["runtime"]              = tmdb["runtime"]
            countries = [c["iso_3166_1"] for c in tmdb.get("production_countries", [])]
            if countries:                     fields["production_countries"] = countries

            # Full document feed guarantees BM25 re-indexing of all fields.
            yield {"id": mid, "fields": fields}

    _enriched, _failed_e = _feed_docs(
        _enriched_docs(),
        total=len(_all_mids),
        progress_every=100,
        max_workers=16,
    )
    print(f"Done: {_enriched:,} fed, {_failed_e:,} failed.")

#%%python
#H1 Data After Enrichment
# 1. New field coverage
_cov_resp = requests.get(
    f"{VESPA_FEED_URL}/search/",
    params={"yql": "select overview, original_language, runtime, production_countries from movie where true limit 400",
            "hits": 400, "timeout": "10s"},
    timeout=15,
).json()
_cov_hits = _cov_resp.get("root", {}).get("children", [])

if not _cov_hits:
    print("No hits — run enrichment first.")
else:
    _cov_rows = [{"overview": bool(h.get("fields", {}).get("overview")),
                  "language": bool(h.get("fields", {}).get("original_language")),
                  "runtime":  bool(h.get("fields", {}).get("runtime")),
                  "countries":bool(h.get("fields", {}).get("production_countries"))}
                 for h in _cov_hits]
    _cov_df = pl.DataFrame(_cov_rows)
    _n = len(_cov_df)
    _pcts = [_cov_df[col].sum() / _n * 100 for col in _cov_df.columns]

    fig, ax = plt.subplots(figsize=(8, 5))
    _cbars = ax.bar(list(_cov_df.columns), _pcts, color=["steelblue","mediumseagreen","coral","mediumpurple"])
    for bar, pct in zip(_cbars, _pcts):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1, f"{pct:.1f}%", ha="center", fontsize=11, fontweight="bold")
    ax.set_ylim(0, 115); ax.set_ylabel("Coverage (%)"); ax.set_title("TMDB Field Coverage  (sample of 400)")
    ax.grid(True, alpha=0.3, axis="y"); plt.tight_layout(); show(fig)

#%%python
# 2. Language & countries
_lang_ch    = groups(search("select * from movie where true limit 0 | all( group(original_language) max(30) each( output(count()) ))"))
_country_ch = groups(search("select * from movie where true limit 0 | all( group(production_countries) max(20) each( output(count()) ))"))

if not _lang_ch and not _country_ch:
    print("No language/country data — run enrichment first.")
else:
    LANG = {"en":"English","fr":"French","de":"German","es":"Spanish","it":"Italian",
            "ja":"Japanese","ko":"Korean","zh":"Chinese","hi":"Hindi","pt":"Portuguese",
            "ru":"Russian","sv":"Swedish","da":"Danish","nl":"Dutch","pl":"Polish"}

    fig, axes = plt.subplots(1, 2, figsize=(15, 6))
    if _lang_ch:
        _ld = pl.DataFrame([{"language": c["value"], "count": c["fields"]["count()"]} for c in _lang_ch if "value" in c]).sort("count", descending=True)
        _labels = [LANG.get(l, l) for l in _ld["language"].to_list()]
        axes[0].barh(_labels, _ld["count"].to_list(), color=["steelblue" if l=="en" else "mediumseagreen" for l in _ld["language"].to_list()])
        axes[0].set_title("Movies by Original Language"); axes[0].set_xlabel("Movies"); axes[0].invert_yaxis(); axes[0].grid(True, alpha=0.3, axis="x")
    if _country_ch:
        _cd = pl.DataFrame([{"country": c["value"], "count": c["fields"]["count()"]} for c in _country_ch if "value" in c]).sort("count", descending=True).head(15)
        axes[1].barh(_cd["country"].to_list(), _cd["count"].to_list(), color="coral")
        axes[1].set_title("Movies by Production Country  (top 15)"); axes[1].set_xlabel("Movies"); axes[1].invert_yaxis(); axes[1].grid(True, alpha=0.3, axis="x")
    plt.tight_layout(); show(fig)

#%%python
# 3. Runtime distribution
_rt_raw = groups(search("select * from movie where runtime > 0 limit 0 | all( group(runtime) max(400) each( output(count()) ))"))
if not _rt_raw:
    print("No runtime data — run enrichment first.")
else:
    _rt_rows = [{"runtime": int(c["value"]), "count": c["fields"]["count()"]} for c in _rt_raw if "value" in c]
    if _rt_rows:
        _rt_df = (
            pl.DataFrame(_rt_rows)
            .with_columns((pl.col("runtime") // 15 * 15).alias("bucket"))
            .group_by("bucket").agg(pl.col("count").sum()).sort("bucket")
            .filter(pl.col("bucket") < 240)
        )
        def _rc(r): return "lightcoral" if r<60 else "steelblue" if r<105 else "darkorange" if r<150 else "mediumpurple"
        fig, ax = plt.subplots(figsize=(13, 5))
        ax.bar([f"{r}–{r+15}" for r in _rt_df["bucket"].to_list()],
               _rt_df["count"].to_list(),
               color=[_rc(r) for r in _rt_df["bucket"].to_list()])
        ax.set_title("Runtime Distribution  (red <60 · blue 60–105 · orange 105–150 · purple 150+)")
        ax.set_xlabel("Minutes"); ax.set_ylabel("Movies"); ax.grid(True, alpha=0.3, axis="y")
        plt.xticks(rotation=45, ha="right"); plt.tight_layout(); show(fig)

#%%vespa
#H1 Ranking
# 1. BM25
POST /search
{
  "yql": "select title, genres from movie where userQuery() limit 10",
  "query": "space adventure",
  "ranking": "bm25"
}
#%%vespa
# 2. Native-rank
POST /search
{
  "yql": "select title, genres from movie where userQuery() limit 10",
  "query": "space adventure",
  "ranking": "native-rank"
}
#%%vespa
# 3. Plot / overview search
POST /search
{
  "yql": "select title, genres, overview from movie where overview contains \"heist\" limit 5",
  "ranking": "bm25"
}
#%%vespa
# 4. Filter by Language
POST /search
{
  "yql": "select title, year, runtime from movie where original_language matches \"ko\" limit 10"
}
#%%vespa
# 5. Filter by Runtime
POST /search
{
  "yql": "select title, runtime, genres from movie where runtime < 60 and runtime > 0 limit 10"
}
#%%python
#H1 FastText - Training
# 1. Train FastText
if not HAS_FT:
    print("Install fasttext-wheel and numpy first.")
else:
    # Build corpus: title + genres per movie
    _movies_ft = {}
    with open(os.path.join(DATA_DIR, "movies.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            genres = [g for g in row["genres"].split("|") if g and g != "(no genres listed)"]
            _movies_ft[row["movieId"]] = {"title": row["title"], "genres": genres}

    def _ft_clean(t):
        t = re.sub(r'\(\d{4}\)', '', t).lower()
        return re.sub(r'[^a-z0-9 ]', ' ', t).strip()

    with open(FT_CORPUS_PATH, "w", encoding="utf-8") as f:
        for m in _movies_ft.values():
            line = " ".join([_ft_clean(m["title"])] + [_ft_clean(g) for g in m["genres"]])
            if line.strip(): f.write(line + "\n")
    print(f"Corpus: {FT_CORPUS_PATH}  ({len(_movies_ft):,} lines)")

    _ft_model = ft.train_unsupervised(FT_CORPUS_PATH, model="skipgram", dim=100, epoch=5, minCount=1, thread=os.cpu_count() or 4)
    _ft_model.save_model(FT_MODEL_PATH)
    print(f"Model saved: {FT_MODEL_PATH}  (vocab={len(_ft_model.words):,}, dim={_ft_model.get_dimension()})")

    for word in ["action", "comedy", "alien", "love", "space"]:
        nn = _ft_model.get_nearest_neighbors(word, k=5)
        print(f"  {word:8s} → {[w for _, w in nn]}")

#%%python
# 2. Index FastText Embeddings
if not HAS_FT:
    print("FastText not available.")
else:
    def _ft_vec(title, genres):
        model = ft_load()
        text  = " ".join([_ft_clean(title)] + [_ft_clean(g) for g in genres])
        words = text.split()
        if not words: return np.zeros(model.get_dimension(), dtype=np.float32)
        vecs = np.array([model.get_word_vector(w) for w in words], dtype=np.float32)
        vec  = vecs.mean(axis=0); norm = np.linalg.norm(vec)
        return (vec / norm).astype(np.float32) if norm > 0 else vec

    def _ft_updates():
        for mid, m in _movies_ft.items():
            vec = _ft_vec(m["title"], m["genres"])
            yield {"id": mid, "fields": {"embedding_fasttext": {"assign": {"values": vec.tolist()}}}}

    _ft_total = len(_movies_ft)
    print(f"Feeding {_ft_total:,} vectors with pyvespa async feed…")

    _ft_fed, _ft_fail = _feed_docs(
        _ft_updates(),
        total=_ft_total,
        operation_type="update",
        progress_every=1000,
        auto_assign=False,
    )
    print(f"Done: {_ft_fed:,} fed, {_ft_fail:,} failed.")

#%%python
#H1 FastText - Let's Compare
# 1. BM25 vs FastText
import matplotlib.gridspec as gridspec

def _bm25(query, n=10):
    resp = requests.get(f"{VESPA_FEED_URL}/search/", params={
        "yql": f"select title, genres from movie where userQuery() limit {n}",
        "query": query, "ranking": "bm25", "hits": n,
    }, timeout=10).json()
    return [{"title": h["fields"].get("title","?"), "genres": h["fields"].get("genres",[]), "score": h["relevance"]}
            for h in resp.get("root",{}).get("children",[])]

def _ann(query, n=10):
    vec = ft_embed(query)
    resp = requests.post(f"{VESPA_FEED_URL}/search/", json={
        "yql": f"select title, genres from movie where {{targetHits: {n}}} nearestNeighbor(embedding_fasttext, q)",
        "ranking": "semantic-fasttext",
        "input.query(q)": {"values": vec.tolist()},
        "hits": n,
    }, timeout=10).json()
    errs = resp.get("root",{}).get("errors",[])
    if errs: print("ANN errors:", errs)
    return [{"title": h["fields"].get("title","?"), "genres": h["fields"].get("genres",[]), "score": h["relevance"]}
            for h in resp.get("root",{}).get("children",[])]

def _short(t, n=38): return t[:n]+"…" if len(t)>n else t

def compare(query):
    bm25_hits = _bm25(query)
    ann_hits  = _ann(query)
    fig = plt.figure(figsize=(14, 6))
    fig.suptitle(f'Query: "{query}"', fontsize=13, fontweight="bold")
    gs  = gridspec.GridSpec(1, 2, wspace=0.05)
    for col, (hits, label, color) in enumerate([(bm25_hits,"BM25","steelblue"),(ann_hits,"FastText","mediumseagreen")]):
        ax = fig.add_subplot(gs[col])
        if not hits:
            ax.text(0.5, 0.5, "no results", ha="center", va="center", transform=ax.transAxes)
        else:
            mx = max(h["score"] for h in hits) or 1
            bars = ax.barh(range(len(hits)), [h["score"]/mx for h in hits], color=color, alpha=0.85)
            ax.set_yticks(range(len(hits)))
            ax.set_yticklabels([_short(h["title"]) for h in hits], fontsize=9)
            ax.invert_yaxis(); ax.set_xlim(0, 1.2); ax.set_xlabel("Normalised score")
            for i, (bar, h) in enumerate(zip(bars, hits)):
                ax.text(bar.get_width()+0.02, i, ", ".join(h["genres"][:2]), va="center", fontsize=7, color="grey")
        ax.set_title(label, fontsize=11, color=color, fontweight="bold")
        if col == 1: ax.yaxis.set_visible(False)
    plt.tight_layout(); show(fig)

for _q in ["sci-fi space adventure", "heist thriller", "love story paris"]:
    compare(_q)

#%%vespa
#H1 Arctic XS
# 1. Arctic XS Semantic Search
POST /search
{
  "yql": "select title, genres from movie where {targetHits: 10} nearestNeighbor(embedding_arctic, q)",
  "ranking": "semantic-arctic",
  "input.query(q)": "embed(arctic, @text)",
  "text": "sci-fi space adventure",
  "hits": 10
}
#%%vespa
# 2. Arctic XS BM25 + Arctic ANN
POST /search
{
  "yql": "select title, genres from movie where {targetHits: 100} nearestNeighbor(embedding_arctic, q) OR userQuery()",
  "query": "space",
  "ranking": "hybrid-arctic",
  "input.query(q)": "embed(arctic, @text)",
  "text": "sci-fi space adventure",
  "hits": 10
}
#%%python
# 3. BM25 vs FastText vs Arctic
import matplotlib.gridspec as gridspec

def _arctic(query, n=10):
    resp = requests.get(
        f"{VESPA_FEED_URL}/search/",
        params={
            "yql": f"select title, genres from movie where {{targetHits: {n}}} nearestNeighbor(embedding_arctic, q)",
            "ranking": "semantic-arctic",
            "input.query(q)": f"embed(arctic, {query})",
            "hits": n,
        },
        timeout=30,   # longer — Vespa embeds query server-side
    ).json()
    errs = resp.get("root", {}).get("errors", [])
    if errs: print("Arctic errors:", errs)
    return [
        {"title": h["fields"].get("title", "?"), "genres": h["fields"].get("genres", []), "score": h["relevance"]}
        for h in resp.get("root", {}).get("children", [])
    ]

def compare3(query):
    bm25_hits   = _bm25(query)
    ft_hits     = _ann(query)
    arctic_hits = _arctic(query)

    fig = plt.figure(figsize=(20, 6))
    fig.suptitle(f'Query: "{query}"', fontsize=13, fontweight="bold")
    gs  = gridspec.GridSpec(1, 3, wspace=0.05)

    for col, (hits, label, color) in enumerate([
        (bm25_hits,   "BM25",      "steelblue"),
        (ft_hits,     "FastText",  "mediumseagreen"),
        (arctic_hits, "Arctic XS", "darkorchid"),
    ]):
        ax = fig.add_subplot(gs[col])
        if not hits:
            ax.text(0.5, 0.5, "no results", ha="center", va="center", transform=ax.transAxes)
        else:
            mx   = max(h["score"] for h in hits) or 1
            bars = ax.barh(range(len(hits)), [h["score"] / mx for h in hits], color=color, alpha=0.85)
            ax.set_yticks(range(len(hits)))
            ax.set_yticklabels([_short(h["title"]) for h in hits], fontsize=9)
            ax.invert_yaxis()
            ax.set_xlim(0, 1.2)
            ax.set_xlabel("Normalised score")
            for i, (bar, h) in enumerate(zip(bars, hits)):
                ax.text(bar.get_width() + 0.02, i, ", ".join(h["genres"][:2]),
                        va="center", fontsize=7, color="grey")
        ax.set_title(label, fontsize=11, color=color, fontweight="bold")
        if col > 0: ax.yaxis.set_visible(False)

    plt.tight_layout()
    show(fig)

for _q in ["sci-fi space adventure", "heist thriller", "love story paris"]:
    compare3(_q)