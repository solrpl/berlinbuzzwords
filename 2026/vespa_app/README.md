# Movie Vespa App

Minimal local Vespa application for MovieLens `movies.csv`.

## Schema

Documents use type `movie` with:

- `id`: string
- `title`: string
- `genres`: array of strings

## Deploy

```sh
vespa deploy --wait 2026/vespa_app
```

## Feed MovieLens CSV

From the repository root:

```sh
python3 2026/vespa_app/to_vespa_feed.py \
  2026/dataset/movielens/ml-latest-small/movies.csv \
  > /tmp/movies-vespa-feed.jsonl

vespa feed /tmp/movies-vespa-feed.jsonl
```

## Query

```sh
vespa query 'select * from movie where title contains "Toy"'
vespa query 'select * from movie where genres contains "Adventure"'
```
