#!/usr/bin/env python3
import csv
import json
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} movies.csv", file=sys.stderr)
        return 2

    with open(sys.argv[1], newline="", encoding="utf-8") as csv_file:
        for row in csv.DictReader(csv_file):
            movie_id = row["movieId"]
            genres = [] if row["genres"] == "(no genres listed)" else row["genres"].split("|")
            print(
                json.dumps(
                    {
                        "id": f"id:movies:movie::{movie_id}",
                        "fields": {
                            "id": movie_id,
                            "title": row["title"],
                            "genres": genres,
                        },
                    },
                    ensure_ascii=False,
                )
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
