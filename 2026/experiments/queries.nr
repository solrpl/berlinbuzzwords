#%%vespa
# Search for movies
POST /search
{
  "yql": "select * from movie where true"
}
#%%vespa
# Search for rating
POST /search
{
  "yql": "select * from rating where true"
}
#%%vespa
# Search for tags
POST /search
{
  "yql": "select * from tag where true"
}
#%%vespa
# Grouping try #1
POST /search
{
  "yql": "select * from movie where true",
  "grouping": [
    { "all": { "group": "genres", "each": { "output": "count()" } } },
    { "all": { "group": "year",   "each": { "output": "count()" } } }
  ]
}
#%%vespa
# Grouping with pipes
POST /search
{
  "yql": "select * from movie where true limit 0 | all(group(genres) max(20) order(-count()) each(output(count()))) | all(group(year) max(30) order(-count()) each(output(count()))) | all(group(fixedwidth(year,10)) order(-count()) each(output(count())))"
}
#%%vespa
# Grouping with pipes year sorted via value
POST /search
{
  "yql": "select * from movie where true limit 0 | all(group(genres) max(20) order(-count()) each(output(count()))) | all(group(year) max(30) order(min(year)) each(output(count()))) | all(group(fixedwidth(year,10)) order(-count()) each(output(count())))"
}
#%%python
# Basic Visualizations with Python
import os

import matplotlib.pyplot as plt
import polars as pl
import requests

VESPA_URL = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")

def search(yql: str) -> list:
    """Run a grouping YQL and return the group children list."""
    resp = requests.get(f"{VESPA_URL}/search/", params={"yql": yql}, timeout=30)
    resp.raise_for_status()
    body = resp.json()
    for error in body.get("root", {}).get("errors", []):
        if "Timeout" in error.get("message", ""):
            return []
        raise RuntimeError(error["message"])
    try:
        return body["root"]["children"][0]["children"][0]["children"]
    except (KeyError, IndexError):
        return []

def show(fig) -> None:
    plt.show()
    plt.close(fig)

def plot_movies_per_year() -> None:
    print("Movies per year...")
    children = search(
        "select * from movie where year > 0 limit 0 "
        "| all( group(year) max(200) each( output(count()) ))"
    )
    df = pl.DataFrame([
        {"year": int(c["value"]), "count": c["fields"]["count()"]}
        for c in children
    ]).sort("year")

    fig, ax = plt.subplots(figsize=(14, 5))
    ax.bar(df["year"].to_list(), df["count"].to_list(), color="coral", width=0.8)
    ax.set_xlabel("Year")
    ax.set_ylabel("Number of movies")
    ax.set_title("Movies per Year")
    ax.grid(True, alpha=0.3, axis="y")
    fig.autofmt_xdate()
    show(fig)

def plot_top_genres() -> None:
    print("Top genres...")
    children = search(
        "select * from movie where true limit 0 "
        "| all( group(genres) max(25) each( output(count()) ))"
    )
    df = pl.DataFrame([
        {"genre": c["value"], "count": c["fields"]["count()"]}
        for c in children
    ]).sort("count", descending=True)

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.barh(df["genre"].to_list(), df["count"].to_list(), color="mediumseagreen")
    ax.set_xlabel("Number of movies")
    ax.set_title("Movies per Genre")
    ax.invert_yaxis()
    ax.grid(True, alpha=0.3, axis="x")
    show(fig)

def plot_rating_distribution() -> None:
    print("Rating distribution...")
    children = search(
        "select * from rating where true limit 0 "
        "| all( group(rating) each( output(count()) ))"
    )
    if not children:
        print("  No rating documents indexed yet — skipping.")
        return

    df = pl.DataFrame([
        {"rating": float(c["value"]), "count": c["fields"]["count()"]}
        for c in children
    ]).sort("rating")

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.bar(df["rating"].to_list(), df["count"].to_list(), width=0.4, color="steelblue")
    ax.set_xlabel("Rating")
    ax.set_ylabel("Number of ratings")
    ax.set_title("Rating Distribution")
    ax.grid(True, alpha=0.3, axis="y")
    show(fig)

def plot_top_rated_movies() -> None:
    print("Top 20 most rated movies...")
    children = search(
        "select * from rating where true limit 0 "
        "| all( group(movie_id) order(-count()) max(20) each( output(count()) ))"
    )
    if not children:
        print("  No rating documents indexed yet — skipping.")
        return

    df = pl.DataFrame([
        {"movie_id": str(c["value"]), "ratings": c["fields"]["count()"]}
        for c in children
    ])

    fig, ax = plt.subplots(figsize=(12, 5))
    ax.bar(df["movie_id"].to_list(), df["ratings"].to_list(), color="mediumpurple")
    ax.set_xlabel("Movie ID")
    ax.set_ylabel("Number of ratings")
    ax.set_title("Top 20 Most Rated Movies")
    ax.grid(True, alpha=0.3, axis="y")
    fig.autofmt_xdate()
    show(fig)

def plot_movies_per_decade() -> None:
    print("Movies per decade...")
    children = search(
        "select * from movie where year > 0 limit 0 "
        "| all( group(year) max(200) each( output(count()) ))"
    )
    rows = [{"year": int(c["value"]), "count": c["fields"]["count()"]} for c in children]
    df = (
        pl.DataFrame(rows)
        .with_columns((pl.col("year") // 10 * 10).alias("decade"))
        .group_by("decade")
        .agg(pl.col("count").sum())
        .sort("decade")
    )

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(
        [str(d) + "s" for d in df["decade"].to_list()],
        df["count"].to_list(),
        color="darkorange",
    )
    ax.set_xlabel("Decade")
    ax.set_ylabel("Number of movies")
    ax.set_title("Movies per Decade")
    ax.grid(True, alpha=0.3, axis="y")
    show(fig)

def main() -> None:
    print(f"Vespa: {VESPA_URL}\n")
    plot_movies_per_year()
    plot_movies_per_decade()
    plot_top_genres()
    plot_rating_distribution()
    plot_top_rated_movies()
    print("\nDone.")


if __name__ == "__main__":
    main()

#%%python
# Exploration with Python
import os

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import polars as pl
import requests

VESPA_URL = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")

def search(yql: str, timeout: str = "30s") -> list:
    resp = requests.get(
        f"{VESPA_URL}/search/",
        params={"yql": yql, "timeout": timeout},
        timeout=60,
    )
    resp.raise_for_status()
    body = resp.json()
    for error in body.get("root", {}).get("errors", []):
        if "timeout" in error.get("message", "").lower():
            print(f"  Query timed out — skipping.")
            return []
        raise RuntimeError(error["message"])
    try:
        return body["root"]["children"][0]["children"][0]["children"]
    except (KeyError, IndexError):
        return []


def show(fig) -> None:
    plt.show()
    plt.close(fig)

def plot_halfstar_vs_wholestar() -> None:
    print("Half-star vs whole-star preference...")
    children = search(
        "select * from rating where true limit 0 "
        "| all( group(rating) each( output(count()) ))"
    )
    if not children:
        return

    df = pl.DataFrame([
        {"rating": float(c["value"]), "count": c["fields"]["count()"]}
        for c in children
    ]).with_columns(
        pl.when(pl.col("rating") % 1 == 0).then(pl.lit("whole")).otherwise(pl.lit("half")).alias("type")
    ).sort("rating")

    colors = ["steelblue" if t == "whole" else "lightskyblue"
              for t in df["type"].to_list()]

    fig, ax = plt.subplots(figsize=(9, 5))
    bars = ax.bar(
        [str(r) for r in df["rating"].to_list()],
        df["count"].to_list(),
        color=colors,
    )
    ax.set_xlabel("Rating value")
    ax.set_ylabel("Number of ratings")
    ax.set_title("Half-star vs Whole-star Ratings\n(dark = whole star, light = half star)")
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x/1e6:.1f}M"))
    ax.grid(True, alpha=0.3, axis="y")
    show(fig)

def plot_ratings_over_time() -> None:
    print("Ratings over time...")
    children = search(
        "select * from rating where true limit 0 "
        "| all( group(time.year(timestamp)) max(30) each( output(count()) output(avg(rating)) ))"
    )
    if not children:
        return

    df = pl.DataFrame([
        {
            "year": int(c["value"]),
            "count": c["fields"]["count()"],
            "avg_rating": c["fields"]["avg(rating)"],
        }
        for c in children
    ]).sort("year")

    fig, ax1 = plt.subplots(figsize=(12, 5))
    ax2 = ax1.twinx()

    ax1.bar(df["year"].to_list(), df["count"].to_list(), color="steelblue", alpha=0.6, label="# ratings")
    ax2.plot(df["year"].to_list(), df["avg_rating"].to_list(), color="coral",
             marker="o", linewidth=2, label="avg rating")

    ax1.set_xlabel("Year")
    ax1.set_ylabel("Number of ratings", color="steelblue")
    ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x/1e6:.1f}M"))
    ax2.set_ylabel("Average rating", color="coral")
    ax2.set_ylim(3.0, 4.2)
    ax1.set_title("Rating Volume and Average Score Over Time")

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper left")
    ax1.grid(True, alpha=0.3, axis="y")
    show(fig)

def plot_top_movies_count_vs_avg() -> None:
    print("Top 20 most rated movies: count vs avg rating...")
    children = search(
        "select * from rating where true limit 0 "
        "| all( group(movie_id) order(-count()) max(20) each( output(count()) output(avg(rating)) ))"
    )
    if not children:
        return

    # Fetch movie titles for those IDs
    movie_ids = [str(c["value"]) for c in children]
    id_filter = " OR ".join(f"movie_id = {mid}" for mid in movie_ids)
    title_resp = requests.get(
        f"{VESPA_URL}/search/",
        params={"yql": f"select movie_id, title from movie where {id_filter} limit 20"},
        timeout=10,
    ).json()
    titles = {}
    for hit in title_resp.get("root", {}).get("children", []):
        f = hit.get("fields", {})
        titles[str(f["movie_id"])] = f["title"]

    df = pl.DataFrame([
        {
            "title": titles.get(str(c["value"]), f"movie {c['value']}"),
            "count": c["fields"]["count()"],
            "avg": c["fields"]["avg(rating)"],
        }
        for c in children
    ]).sort("count", descending=True)

    short_titles = [t[:30] + "…" if len(t) > 30 else t for t in df["title"].to_list()]

    fig, ax = plt.subplots(figsize=(12, 7))
    scatter = ax.scatter(
        df["count"].to_list(),
        df["avg"].to_list(),
        s=120,
        c=df["avg"].to_list(),
        cmap="RdYlGn",
        vmin=3.5, vmax=4.5,
        zorder=3,
    )
    for i, label in enumerate(short_titles):
        ax.annotate(label, (df["count"][i], df["avg"][i]),
                    fontsize=7, ha="left", va="bottom",
                    xytext=(4, 4), textcoords="offset points")
    plt.colorbar(scatter, ax=ax, label="Avg rating")
    ax.set_xlabel("Number of ratings")
    ax.set_ylabel("Average rating")
    ax.set_title("Top 20 Most Rated Movies: Popularity vs Quality")
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x/1e3:.0f}K"))
    ax.grid(True, alpha=0.3)
    show(fig)

def plot_most_active_users() -> None:
    print("Top 20 most active users...")
    children = search(
        "select * from rating where true limit 0 "
        "| all( group(user_id) order(-count()) max(20) each( output(count()) output(avg(rating)) ))"
    )
    if not children:
        return

    df = pl.DataFrame([
        {
            "user_id": str(c["value"]),
            "count": c["fields"]["count()"],
            "avg": c["fields"]["avg(rating)"],
        }
        for c in children
    ]).sort("count", descending=True)

    fig, ax1 = plt.subplots(figsize=(12, 5))
    ax2 = ax1.twinx()

    x = range(len(df))
    ax1.bar(x, df["count"].to_list(), color="mediumpurple", alpha=0.7, label="# ratings")
    ax2.plot(x, df["avg"].to_list(), color="darkorange", marker="o", linewidth=2, label="avg rating")

    ax1.set_xticks(list(x))
    ax1.set_xticklabels([f"user {uid}" for uid in df["user_id"].to_list()],
                        rotation=45, ha="right", fontsize=8)
    ax1.set_ylabel("Number of ratings", color="mediumpurple")
    ax2.set_ylabel("Average rating", color="darkorange")
    ax2.set_ylim(1.0, 5.0)
    ax1.set_title("Top 20 Most Active Users")
    ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x/1e3:.0f}K"))

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper right")
    ax1.grid(True, alpha=0.3, axis="y")
    show(fig)

def plot_most_tagged_movies() -> None:
    print("Top 20 most tagged movies...")
    children = search(
        "select * from tag where true limit 0 "
        "| all( group(movie_id) order(-count()) max(20) each( output(count()) ))"
    )
    if not children:
        return

    movie_ids = [str(c["value"]) for c in children]
    id_filter = " OR ".join(f"movie_id = {mid}" for mid in movie_ids)
    title_resp = requests.get(
        f"{VESPA_URL}/search/",
        params={"yql": f"select movie_id, title from movie where {id_filter} limit 20"},
        timeout=10,
    ).json()
    titles = {}
    for hit in title_resp.get("root", {}).get("children", []):
        f = hit.get("fields", {})
        titles[str(f["movie_id"])] = f["title"]

    df = pl.DataFrame([
        {
            "title": titles.get(str(c["value"]), f"movie {c['value']}"),
            "tags": c["fields"]["count()"],
        }
        for c in children
    ]).sort("tags", descending=True)

    short_titles = [t[:35] + "…" if len(t) > 35 else t for t in df["title"].to_list()]

    fig, ax = plt.subplots(figsize=(10, 7))
    ax.barh(short_titles, df["tags"].to_list(), color="teal")
    ax.set_xlabel("Number of tags")
    ax.set_title("Top 20 Most Tagged Movies")
    ax.invert_yaxis()
    ax.grid(True, alpha=0.3, axis="x")
    show(fig)

def main() -> None:
    print(f"Vespa: {VESPA_URL}\n")
    plot_halfstar_vs_wholestar()
    plot_ratings_over_time()
    plot_top_movies_count_vs_avg()
    plot_most_active_users()
    plot_most_tagged_movies()
    print("\nDone.")


if __name__ == "__main__":
    main()

#%%python
# Data story: shared helpers
import os
import re
from collections import Counter

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import polars as pl
import requests

VESPA_URL = os.environ.get("VESPA_FEED_URL", "http://localhost:8080")


def search(yql: str, timeout: str = "30s", hits: int = 0) -> dict:
    resp = requests.get(
        f"{VESPA_URL}/search/",
        params={"yql": yql, "hits": hits, "timeout": timeout},
        timeout=60,
    )
    resp.raise_for_status()
    body = resp.json()
    for error in body.get("root", {}).get("errors", []):
        if "timeout" in error.get("message", "").lower():
            return {}
        raise RuntimeError(error["message"])
    return body


def groups(body: dict) -> list:
    try:
        return body["root"]["children"][0]["children"][0]["children"]
    except (KeyError, IndexError):
        return []


def show(fig) -> None:
    plt.show()
    plt.close(fig)


#%%python
# 1. Is the data clean?
total = search("select * from movie where true limit 0")["root"]["fields"]["totalCount"]
no_year_count = search("select * from movie where !(year > 0) limit 0")["root"]["fields"]["totalCount"]
no_genre_count = search('select * from movie where genres contains "(no genres listed)" limit 0')["root"]["fields"]["totalCount"]

year_children = groups(search(
    "select * from movie where year > 0 limit 0 "
    "| all( group(year) max(200) each( output(count()) ))"
))
years = sorted(int(c["value"]) for c in year_children)

print(f"Total movies:       {total:,}")
print(f"Missing year:       {no_year_count:,} ({100*no_year_count/total:.1f}%)")
print(f"No genres listed:   {no_genre_count:,} ({100*no_genre_count/total:.1f}%)")
print(f"Year range:         {years[0]} – {years[-1]}")
print(f"Pre-1930 years:     {len([y for y in years if y < 1930])}")

df_years = pl.DataFrame([
    {"year": int(c["value"]), "count": c["fields"]["count()"]}
    for c in year_children
]).sort("year")
colors_bar = ["salmon" if y < 1930 else "steelblue" for y in df_years["year"].to_list()]

fig, axes = plt.subplots(1, 2, figsize=(13, 5))
axes[0].pie(
    [total - no_year_count, no_year_count],
    labels=["Have year", "No year"],
    colors=["steelblue", "salmon"],
    autopct="%1.1f%%", startangle=140,
)
axes[0].set_title("Year field coverage")
axes[1].bar(df_years["year"].to_list(), df_years["count"].to_list(), color=colors_bar, width=0.9)
axes[1].set_title("Year distribution  (red = pre-1930 outliers)")
axes[1].set_xlabel("Year")
axes[1].set_ylabel("Movies")
axes[1].grid(True, alpha=0.3, axis="y")
plt.tight_layout()
show(fig)

#%%python
# 2. Facets: what's in it?
genre_children = groups(search(
    "select * from movie where true limit 0 "
    "| all( group(genres) max(25) each( output(count()) ))"
))
year_children = groups(search(
    "select * from movie where year > 0 limit 0 "
    "| all( group(year) max(200) each( output(count()) ))"
))
genre_df = pl.DataFrame([
    {"genre": c["value"], "movies": c["fields"]["count()"]}
    for c in genre_children
]).sort("movies", descending=True)

decade_df = (
    pl.DataFrame([{"year": int(c["value"]), "count": c["fields"]["count()"]} for c in year_children])
    .with_columns((pl.col("year") // 10 * 10).alias("decade"))
    .group_by("decade").agg(pl.col("count").sum()).sort("decade")
)

fig, axes = plt.subplots(1, 2, figsize=(15, 6))
axes[0].barh(genre_df["genre"].to_list(), genre_df["movies"].to_list(), color="mediumseagreen")
axes[0].set_title("Movies per Genre (facet)")
axes[0].set_xlabel("Count")
axes[0].invert_yaxis()
axes[0].grid(True, alpha=0.3, axis="x")
axes[1].bar([f"{d}s" for d in decade_df["decade"].to_list()], decade_df["count"].to_list(), color="darkorange")
axes[1].set_title("Movies per Decade (facet)")
axes[1].set_xlabel("Decade")
axes[1].set_ylabel("Count")
axes[1].grid(True, alpha=0.3, axis="y")
plt.xticks(rotation=45)
plt.tight_layout()
show(fig)

#%%python
# 3. Significant terms: what stands out?
_resp = requests.get(
    f"{VESPA_URL}/search/",
    params={"yql": "select title from movie where true limit 400", "hits": 400, "timeout": "10s"},
    timeout=15,
).json()
print("errors:", _resp.get("root", {}).get("errors", []))
hits = _resp.get("root", {}).get("children", [])
print(f"hits fetched: {len(hits)}")
titles = [h["fields"]["title"] for h in hits if "title" in h.get("fields", {})]
if not titles:
    print("No titles — skipping chart")
else:
    stopwords = {"the", "a", "an", "of", "and", "in", "to", "is", "at", "on",
                 "for", "with", "de", "la", "le", "les", "der", "die", "das"}
    words = []
    for t in titles:
        clean = re.sub(r'\(\d{4}\)', '', t).lower()
        words.extend(w for w in re.findall(r"[a-z']{3,}", clean) if w not in stopwords)

    top_words = Counter(words).most_common(30)
    words_list  = [w for w, _ in top_words]
    counts_list = [c for _, c in top_words]

    fig, ax = plt.subplots(figsize=(12, 6))
    bars = ax.bar(words_list, counts_list, color="steelblue")
    for bar in bars[:5]:
        bar.set_color("coral")
    ax.set_title("Most Frequent Words in Movie Titles  (top 5 highlighted, 5K sample)")
    ax.set_xlabel("Word")
    ax.set_ylabel("Occurrences")
    ax.grid(True, alpha=0.3, axis="y")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    show(fig)

#%%python
# 4. Additional parsing: what can we extract?
_resp = requests.get(
    f"{VESPA_URL}/search/",
    params={"yql": "select title, year from movie where true limit 400", "hits": 400, "timeout": "10s"},
    timeout=15,
).json()
print("errors:", _resp.get("root", {}).get("errors", []))
hits = _resp.get("root", {}).get("children", [])
print(f"hits fetched: {len(hits)}")
rows = [{"title": h["fields"]["title"], "year": h["fields"].get("year")}
        for h in hits if "title" in h.get("fields", {})]
if not rows:
    print("No data — skipping")
else:
    df = pl.DataFrame(rows)

    articles = df.filter(
        pl.col("title").str.to_lowercase().str.starts_with("the ") |
        pl.col("title").str.to_lowercase().str.starts_with("a ") |
        pl.col("title").str.to_lowercase().str.starts_with("an ")
    )
    sequels = df.filter(pl.col("title").str.contains(r"[2-9]|\bII\b|\bIII\b|\bIV\b|\bV\b|\bVI\b"))
    comma_inverted = df.filter(pl.col("title").str.contains(r", The$|, A$|, An$"))

    print(f"Titles starting with article: {len(articles)} ({100*len(articles)/len(df):.1f}%)")
    print(f"Probable sequels/series:      {len(sequels)} ({100*len(sequels)/len(df):.1f}%)")
    print(f"Comma-inverted titles:        {len(comma_inverted)}")

    sequel_by_decade = (
        df.with_columns(pl.col("year").cast(pl.Int64, strict=False))
        .filter(pl.col("year").is_not_null() & (pl.col("year") > 0))
        .with_columns((pl.col("year") // 10 * 10).alias("decade"))
        .with_columns(pl.col("title").str.contains(r"[2-9]|\bII\b|\bIII\b").alias("is_sequel"))
        .group_by(["decade", "is_sequel"]).len().sort("decade")
    )
    sequels_df   = sequel_by_decade.filter( pl.col("is_sequel")).sort("decade")
    originals_df = sequel_by_decade.filter(~pl.col("is_sequel")).sort("decade")

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].pie(
        [len(articles), len(df) - len(articles)],
        labels=["Starts with article", "Other"],
        autopct="%1.1f%%", colors=["steelblue", "lightgrey"], startangle=140,
    )
    axes[0].set_title("Titles Starting with 'The / A / An'")
    decades = sequels_df["decade"].to_list()
    axes[1].bar(decades, originals_df["len"].to_list(), width=7, label="Originals",      color="steelblue", alpha=0.7)
    axes[1].bar(decades, sequels_df["len"].to_list(),   width=7, label="Sequels/series", color="coral",     alpha=0.9,
                bottom=originals_df["len"].to_list())
    axes[1].set_title("Originals vs Sequels/Series per Decade")
    axes[1].set_xlabel("Decade")
    axes[1].set_ylabel("Movies")
    axes[1].legend()
    axes[1].grid(True, alpha=0.3, axis="y")
    plt.tight_layout()
    show(fig)

#%%python
# 5. Augment it: what can we add?
_resp = requests.get(
    f"{VESPA_URL}/search/",
    params={"yql": "select imdb_id, tmdb_id from movie where true limit 400", "hits": 400, "timeout": "10s"},
    timeout=15,
).json()
print("errors:", _resp.get("root", {}).get("errors", []))
hits = _resp.get("root", {}).get("children", [])
print(f"hits fetched: {len(hits)}")
rows = [{"has_imdb": bool(h["fields"].get("imdb_id")), "has_tmdb": bool(h["fields"].get("tmdb_id"))}
        for h in hits if "fields" in h]
if not rows:
    print("No data — skipping")
else:
    df = pl.DataFrame(rows)
    has_imdb  = df.filter(pl.col("has_imdb"))["has_imdb"].len()
    has_tmdb  = df.filter(pl.col("has_tmdb"))["has_tmdb"].len()
    both      = df.filter(pl.col("has_imdb") & pl.col("has_tmdb"))["has_imdb"].len()
    only_imdb = has_imdb - both
    only_tmdb = has_tmdb - both
    missing   = len(df) - has_imdb - has_tmdb + both

    print(f"Has IMDB ID: {has_imdb} ({100*has_imdb/len(df):.1f}%)")
    print(f"Has TMDB ID: {has_tmdb} ({100*has_tmdb/len(df):.1f}%)")
    print("Augmentation via TMDB API: country, language, budget, runtime, cast, plot")

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.bar(["IMDB only", "TMDB only", "Both IDs", "Missing both"],
           [only_imdb, only_tmdb, both, missing],
           color=["steelblue", "coral", "mediumseagreen", "lightgrey"])
    ax.set_title("External ID Coverage  (augmentation anchors)")
    ax.set_ylabel("Movies in sample")
    ax.grid(True, alpha=0.3, axis="y")
    show(fig)

#%%vespa
# After enrichment: plot-based search via overview field
POST /search
{
  "yql": "select title, overview, original_language, runtime from movie where overview contains 'heist' limit 5"
}
#%%vespa
# Filter by original language (e.g. Korean films)
POST /search
{
  "yql": "select title, year, runtime from movie where original_language matches \"ko\" limit 10"
}
#%%vespa
# Filter by runtime — short films under 60 minutes
POST /search
{
  "yql": "select title, runtime, genres from movie where runtime < 60 and runtime > 0 limit 10"
}
#%%vespa
# Filter by production country
POST /search
{
  "yql": "select title, year, original_language from movie where production_countries contains 'FR' limit 10"
}
#%%python
# 6. After enrichment: new field coverage
_resp = requests.get(
    f"{VESPA_URL}/search/",
    params={
        "yql": "select overview, original_language, runtime, production_countries from movie where true limit 400",
        "hits": 400,
        "timeout": "10s",
    },
    timeout=15,
).json()
hits = _resp.get("root", {}).get("children", [])
if not hits:
    print("No hits — run enrich.py first, then re-run this cell")
else:
    rows = [
        {
            "overview":   bool(h.get("fields", {}).get("overview")),
            "language":   bool(h.get("fields", {}).get("original_language")),
            "runtime":    bool(h.get("fields", {}).get("runtime")),
            "countries":  bool(h.get("fields", {}).get("production_countries")),
        }
        for h in hits
    ]
    df = pl.DataFrame(rows)
    n = len(df)
    coverage = {col: df[col].sum() for col in df.columns}

    labels = list(coverage.keys())
    pcts   = [v / n * 100 for v in coverage.values()]

    fig, ax = plt.subplots(figsize=(8, 5))
    bars = ax.bar(labels, pcts, color=["steelblue", "mediumseagreen", "coral", "mediumpurple"])
    for bar, pct in zip(bars, pcts):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                f"{pct:.1f}%", ha="center", fontsize=11, fontweight="bold")
    ax.set_ylim(0, 115)
    ax.set_ylabel("Coverage (%)")
    ax.set_title("New Field Coverage After TMDB Enrichment  (sample of 400 movies)")
    ax.grid(True, alpha=0.3, axis="y")
    plt.tight_layout()
    show(fig)

#%%python
# 7. Language & production country breakdown
_lang_children = groups(search(
    "select * from movie where true limit 0 "
    "| all( group(original_language) max(30) each( output(count()) ))"
))
_country_children = groups(search(
    "select * from movie where true limit 0 "
    "| all( group(production_countries) max(20) each( output(count()) ))"
))

if not _lang_children and not _country_children:
    print("No language/country data — run enrich.py first")
else:
    LANG_NAMES = {
        "en": "English", "fr": "French", "de": "German", "es": "Spanish",
        "it": "Italian", "ja": "Japanese", "ko": "Korean", "zh": "Chinese",
        "hi": "Hindi",   "pt": "Portuguese", "ru": "Russian", "sv": "Swedish",
        "da": "Danish",  "nl": "Dutch",   "pl": "Polish",  "no": "Norwegian",
        "fi": "Finnish", "tr": "Turkish", "ar": "Arabic",  "he": "Hebrew",
    }

    fig, axes = plt.subplots(1, 2, figsize=(15, 6))

    if _lang_children:
        lang_df = pl.DataFrame([
            {"language": c["value"], "count": c["fields"]["count()"]}
            for c in _lang_children
        ]).sort("count", descending=True)
        labels = [LANG_NAMES.get(l, l) for l in lang_df["language"].to_list()]
        colors = ["steelblue" if l == "en" else "mediumseagreen"
                  for l in lang_df["language"].to_list()]
        axes[0].barh(labels, lang_df["count"].to_list(), color=colors)
        axes[0].set_title("Movies by Original Language")
        axes[0].set_xlabel("Number of movies")
        axes[0].invert_yaxis()
        axes[0].grid(True, alpha=0.3, axis="x")

    if _country_children:
        country_df = pl.DataFrame([
            {"country": c["value"], "count": c["fields"]["count()"]}
            for c in _country_children
        ]).sort("count", descending=True).head(15)
        axes[1].barh(country_df["country"].to_list(), country_df["count"].to_list(), color="coral")
        axes[1].set_title("Movies by Production Country  (top 15, ISO codes)")
        axes[1].set_xlabel("Number of movies")
        axes[1].invert_yaxis()
        axes[1].grid(True, alpha=0.3, axis="x")

    plt.tight_layout()
    show(fig)

#%%python
# 8. Runtime distribution
_runtime_raw = groups(search(
    "select * from movie where runtime > 0 limit 0 "
    "| all( group(runtime) max(400) each( output(count()) ))"
))
if not _runtime_raw:
    print("No runtime data — run enrich.py first")
else:
    rows = [
        {"runtime": int(c["value"]), "count": c["fields"]["count()"]}
        for c in _runtime_raw
        if "value" in c
    ]
    if not rows:
        print("Unexpected grouping structure — first child:", _runtime_raw[0])
    else:
        runtime_df = (
            pl.DataFrame(rows)
            .with_columns((pl.col("runtime") // 15 * 15).alias("bucket"))
            .group_by("bucket")
            .agg(pl.col("count").sum())
            .sort("bucket")
            .filter(pl.col("bucket") < 240)
        )

        def _runtime_color(r: int) -> str:
            if r < 60:   return "lightcoral"
            if r < 105:  return "steelblue"
            if r < 150:  return "darkorange"
            return "mediumpurple"

        labels = [f"{r}–{r+15}" for r in runtime_df["bucket"].to_list()]
        colors = [_runtime_color(r) for r in runtime_df["bucket"].to_list()]

        fig, ax = plt.subplots(figsize=(13, 5))
        ax.bar(labels, runtime_df["count"].to_list(), color=colors)
        ax.set_title(
            "Runtime Distribution  "
            "(red < 60 min · blue 60–105 · orange 105–150 · purple 150+)"
        )
        ax.set_xlabel("Runtime bucket (minutes)")
        ax.set_ylabel("Number of movies")
        ax.grid(True, alpha=0.3, axis="y")
        plt.xticks(rotation=45, ha="right")
        plt.tight_layout()
        show(fig)