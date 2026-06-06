#!/usr/bin/env python3
"""Cosine-rank tasks in .cache/index.embeddings.jsonl against a query.

Reads env:
  QUERY              the search string
  CANDIDATES_FILE    path to a file listing one candidate task file path per line
  TOP_K              max results (default 10)
  JSON               '1' for JSON output, else slug-grouped human output

Output (text):  one line per hit, sorted by score desc:
  <score>  <slug>  <file>

Output (JSON):  one JSON object per line: {score, slug, file}
"""

from __future__ import annotations

import json
import math
import os
import pathlib
import sys


def cosine(a: list[float], b: list[float]) -> float:
  num = sum(x * y for x, y in zip(a, b))
  da = math.sqrt(sum(x * x for x in a))
  db = math.sqrt(sum(y * y for y in b))
  return num / (da * db) if da and db else 0.0


def main() -> None:
  query = os.environ["QUERY"]
  candidates_file = pathlib.Path(os.environ["CANDIDATES_FILE"])
  top_k = int(os.environ.get("TOP_K", "10"))
  as_json = os.environ.get("JSON") == "1"

  candidate_paths = {ln.strip() for ln in candidates_file.read_text().splitlines() if ln.strip()}

  embed_path = pathlib.Path(".cache/index.embeddings.jsonl")
  records = [json.loads(ln) for ln in embed_path.read_text().splitlines() if ln.strip()]
  records = [r for r in records if r["file"] in candidate_paths]
  if not records:
    print("(no embedded tasks match filters)", file=sys.stderr)
    sys.exit(1)

  from fastembed import TextEmbedding
  model = TextEmbedding()
  qvec = list(next(model.embed([query])).tolist())

  scored = [(cosine(qvec, r["embedding"]), r) for r in records]
  scored.sort(reverse=True, key=lambda x: x[0])
  top = scored[:top_k]

  for score, rec in top:
    if as_json:
      print(json.dumps({"score": round(score, 4), "slug": rec["slug"], "file": rec["file"]}))
    else:
      print(f"{score:.4f}  {rec['slug']}  {rec['file']}")


if __name__ == "__main__":
  main()
