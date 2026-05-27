#!/usr/bin/env python3
import hashlib
import json
import re
import sys

# C0 + C1 control characters minus the three whitespace controls we want to keep.
_BAD_CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")


def _clean(s: str) -> str:
    return _BAD_CTRL.sub("", s)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} rating_explanation.json", file=sys.stderr)
        return 2

    with open(sys.argv[1], encoding="utf-8") as f:
        judgments = json.load(f)

    for j in judgments:
        query = _clean(j["query"])
        explanation = _clean(j["explanation"])
        # Stable judgment id from (query, doc_id). doc_id below is the *movie's*
        # Vespa id, not this judgment's. Hash the cleaned query so re-running on
        # a re-cleaned input still yields the same id.
        key = f"{query}|{j['doc_id']}".encode("utf-8")
        judgment_id = hashlib.sha1(key).hexdigest()
        print(
            json.dumps(
                {
                    "id": f"id:judgments:judgment::{judgment_id}",
                    "fields": {
                        "query": query,
                        "doc_id": j["doc_id"],
                        "rating": j["rating"],
                        "explanation": explanation,
                    },
                },
                ensure_ascii=False,
            )
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
