#!/usr/bin/env bash
# embed.sh — build .cache/index.embeddings.jsonl from the corpus.
#
# Reads .cache/index.jsonl (built by bin/index.sh) and emits one record per
# task to .cache/index.embeddings.jsonl: {slug, file, embedding: [float...]}.
# The embedding is over the task's body (frontmatter stripped); model is the
# fastembed default (BAAI/bge-small-en-v1.5, 384 dim).
#
# Usage:
#   bin/embed.sh                 # incremental: skip tasks whose source mtime
#                                 # is older than the embedding cache mtime.
#   bin/embed.sh --refresh        # rebuild .cache/index.jsonl first, re-embed all.
#   bin/embed.sh --all            # re-embed every task even if cached.
#
# First run downloads ~50MB model to ~/.cache/fastembed. Subsequent runs are
# in-process and fast (~100ms per task).
#
# Companion to bin/search.sh --semantic which reads the cache to score queries.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

INDEX=".cache/index.jsonl"
EMBED=".cache/index.embeddings.jsonl"
REFRESH=0
ALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --refresh) REFRESH=1 ;;
    --all) ALL=1 ;;
    *) echo "embed.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$REFRESH" = "1" ] || [ ! -f "$INDEX" ]; then
  bin/index.sh >/dev/null
fi

ALL=$ALL python3 "$(dirname "$0")/_embed.py" "$INDEX" "$EMBED"
