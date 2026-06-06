#!/usr/bin/env python3
"""Build/refresh .cache/index.embeddings.jsonl from .cache/index.jsonl.

Skips tasks whose source file mtime is older than the existing embedding
record (incremental). Pass ALL=1 in env to re-embed everything.

One record per line: {"slug": ..., "file": ..., "mtime": ..., "embedding": [...]}
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys

FRONTMATTER_RE = re.compile(r"^---\n.*?\n---\n", re.DOTALL)


def body_of(path: str) -> str:
  """Return frontmatter-stripped body."""
  text = pathlib.Path(path).read_text()
  return FRONTMATTER_RE.sub("", text, count=1).strip()


def load_existing(out_path: pathlib.Path) -> dict[str, dict]:
  if not out_path.exists():
    return {}
  out: dict[str, dict] = {}
  for line in out_path.read_text().splitlines():
    if not line.strip():
      continue
    try:
      rec = json.loads(line)
      out[rec["slug"]] = rec
    except (json.JSONDecodeError, KeyError):
      continue
  return out


def main() -> None:
  index_path = pathlib.Path(sys.argv[1])
  out_path = pathlib.Path(sys.argv[2])
  rebuild_all = os.environ.get("ALL") == "1"

  index_records = [json.loads(line) for line in index_path.read_text().splitlines() if line.strip()]
  existing = {} if rebuild_all else load_existing(out_path)

  to_embed: list[tuple[str, str, float, str]] = []  # (slug, file, mtime, body)
  carry_over: list[dict] = []

  for rec in index_records:
    slug = rec["slug"]
    file = rec["file"]
    if not pathlib.Path(file).exists():
      continue
    src_mtime = pathlib.Path(file).stat().st_mtime
    prev = existing.get(slug)
    if prev and prev.get("mtime", 0) >= src_mtime - 1e-3:
      carry_over.append(prev)
      continue
    body = body_of(file)
    if not body:
      continue
    to_embed.append((slug, file, src_mtime, body))

  if not to_embed:
    # Rewrite from carry-over to drop slugs no longer in the index.
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w") as f:
      for rec in carry_over:
        f.write(json.dumps(rec) + "\n")
    print(f"embed: 0 new, {len(carry_over)} cached")
    return

  # Lazy import — only pay the fastembed startup cost when actually embedding.
  from fastembed import TextEmbedding
  model = TextEmbedding()
  texts = [b for _, _, _, b in to_embed]
  vectors = list(model.embed(texts))

  new_records = []
  for (slug, file, mtime, _), vec in zip(to_embed, vectors):
    new_records.append({
      "slug": slug,
      "file": file,
      "mtime": mtime,
      "embedding": [float(x) for x in vec.tolist()],
    })

  all_records = carry_over + new_records
  out_path.parent.mkdir(parents=True, exist_ok=True)
  with out_path.open("w") as f:
    for rec in all_records:
      f.write(json.dumps(rec) + "\n")
  print(f"embed: {len(new_records)} new, {len(carry_over)} cached, total {len(all_records)}")


if __name__ == "__main__":
  main()
