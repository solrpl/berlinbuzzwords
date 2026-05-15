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
