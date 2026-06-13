#!/usr/bin/env bash
# search.sh — rg-first search across worklog task files with slug-grouped
# output and frontmatter filters.
#
# Companion to bin/slug.sh (slug fuzzy) and bin/related-search.sh (keyword grep
# only). This tool combines body-level ripgrep with frontmatter-level filtering
# via .cache/index.jsonl. The /serena-rg-search skill is the analogous chooser
# for *code* queries; this is the worklog-corpus chooser.
#
# Usage:
#   bin/search.sh <pattern>                    # rg pattern across all task bodies
#   bin/search.sh <pattern> --active           # active/ only (default: active+archive)
#   bin/search.sh <pattern> --archive          # archive/ only
#   bin/search.sh <pattern> --kind=KIND        # filter by frontmatter kind
#   bin/search.sh <pattern> --status=STATUS    # filter by frontmatter status
#   bin/search.sh <pattern> --project=PROJ     # filter by frontmatter project
#   bin/search.sh <pattern> --linear=ID        # filter tasks referencing Linear ID
#   bin/search.sh <pattern> --pr=N             # filter tasks with PR N in pr: or body
#   bin/search.sh <pattern> --repo=REPO        # filter by frontmatter repos: entry
#   bin/search.sh <pattern> --ldap=LDAP        # filter by owner
#   bin/search.sh --list [filters...]          # no pattern; list slugs matching filters
#   bin/search.sh --json [args...]             # one JSON record per hit (slug + line)
#   bin/search.sh --refresh                    # rebuild .cache/index.jsonl first
#
# Flags compose. Empty pattern requires --list.
#
# rg is invoked with --no-heading --color=never --line-number; the wrapper
# regroups output by slug and prepends a one-line frontmatter banner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INDEX=".cache/index.jsonl"
SCOPE="both"   # both | active | archive
JSON=0
LIST_ONLY=0
REFRESH=0
SEMANTIC=0
TOP_K=10
PATTERN=""
declare -a JQ_FILTERS=()
declare -a RG_EXTRA=()

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

# shellcheck source=_query.sh
. "$SCRIPT_DIR/_query.sh"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --refresh) REFRESH=1 ;;
    --semantic) SEMANTIC=1 ;;
    --top=*) TOP_K="${1#--top=}" ;;
    --active) SCOPE="active" ;;
    --archive) SCOPE="archive" ;;
    --json) JSON=1 ;;
    --list) LIST_ONLY=1 ;;
    --kind=*)    JQ_FILTERS+=("select(.kind == \"${1#--kind=}\")") ;;
    --status=*)  JQ_FILTERS+=("select(.status == \"${1#--status=}\")") ;;
    --project=*) JQ_FILTERS+=("select(.project == \"${1#--project=}\")") ;;
    --ldap=*)    JQ_FILTERS+=("select(.ldap == \"${1#--ldap=}\")") ;;
    --linear=*)
      v="${1#--linear=}"
      JQ_FILTERS+=("select(.linear == \"$v\" or ((.body_refs.linear // []) | index(\"$v\")))")
      ;;
    --pr=*)
      v="${1#--pr=}"
      JQ_FILTERS+=("select(((.pr // []) | map(tostring) | index(\"$v\")) or ((.body_refs.prs // []) | map(tostring) | index(\"$v\")))")
      ;;
    --repo=*)
      v="${1#--repo=}"
      JQ_FILTERS+=("select((.repos // []) | index(\"$v\"))")
      ;;
    --) shift; while [ "$#" -gt 0 ]; do RG_EXTRA+=("$1"); shift; done; break ;;
    -*) RG_EXTRA+=("$1") ;;
    *)
      if [ -z "$PATTERN" ]; then PATTERN="$1"; else RG_EXTRA+=("$1"); fi
      ;;
  esac
  shift
done

if [ "$REFRESH" = "1" ]; then
  "$SCRIPT_DIR/index.sh" >/dev/null
else
  ensure_index
fi

# Scope filter on top of user filters.
case "$SCOPE" in
  active)  JQ_FILTERS+=("select(.state == \"active\")") ;;
  archive) JQ_FILTERS+=("select(.state == \"archive\")") ;;
esac

# Build the jq pipeline.
JQ_PIPE="."
if [ "${#JQ_FILTERS[@]}" -gt 0 ]; then
  for f in "${JQ_FILTERS[@]}"; do
    JQ_PIPE="$JQ_PIPE | $f"
  done
fi

# Materialize candidate files.
CANDIDATE_FILES=$(jq -r "$JQ_PIPE | .file" < "$INDEX")

if [ -z "$CANDIDATE_FILES" ]; then
  echo "(no tasks match filters)" >&2
  exit 1
fi

# --list short-circuits before rg.
if [ "$LIST_ONLY" = "1" ]; then
  if [ -n "$PATTERN" ]; then
    echo "search.sh: --list does not take a pattern (use rg over the listed files instead)" >&2
    exit 2
  fi
  if [ "$JSON" = "1" ]; then
    jq -c "$JQ_PIPE | {slug, ldap, state, kind, status, project, linear, pr, last_updated}" < "$INDEX"
  else
    jq -r "$JQ_PIPE | \"\(.state)  \(.status)  \(.slug)\"" < "$INDEX" | sort
  fi
  exit 0
fi

# --semantic: cosine over .cache/index.embeddings.jsonl filtered to candidate files.
if [ "$SEMANTIC" = "1" ]; then
  [ -z "$PATTERN" ] && { echo "search.sh: --semantic requires a query pattern" >&2; exit 2; }
  [ -f ".cache/index.embeddings.jsonl" ] || { echo "search.sh: .cache/index.embeddings.jsonl missing — run bin/embed.sh first" >&2; exit 1; }
  CANDIDATES_TMP=$(mktemp)
  trap 'rm -f "$CANDIDATES_TMP"' EXIT
  printf '%s\n' "$CANDIDATE_FILES" > "$CANDIDATES_TMP"
  python3 - "$CANDIDATES_TMP" ".cache/index.embeddings.jsonl" <<'PY' >&2 || true
import json
import pathlib
import sys

candidates = [line.strip() for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.strip()]
embed_path = pathlib.Path(sys.argv[2])
try:
  by_file = {}
  for line in embed_path.read_text().splitlines():
    if not line.strip():
      continue
    rec = json.loads(line)
    by_file[rec.get("file", "")] = rec
except Exception:
  print("search.sh: warning: embedding cache is unreadable; run bin/embed.sh --refresh")
  sys.exit(0)

missing = 0
stale = 0
for file_name in candidates:
  path = pathlib.Path(file_name)
  rec = by_file.get(file_name)
  if rec is None:
    missing += 1
    continue
  try:
    if path.stat().st_mtime > float(rec.get("mtime", 0)) + 1e-3:
      stale += 1
  except OSError:
    stale += 1

if missing or stale:
  print(f"search.sh: warning: semantic cache stale ({missing} missing, {stale} older than source); run bin/embed.sh --refresh")
PY
  JSON="$JSON" TOP_K="$TOP_K" CANDIDATES_FILE="$CANDIDATES_TMP" QUERY="$PATTERN" \
    python3 "$SCRIPT_DIR/_semantic_search.py"
  exit $?
fi

if [ -z "$PATTERN" ]; then
  echo "search.sh: pattern required (or use --list)" >&2
  usage >&2
  exit 2
fi

# Stage candidate files for rg via xargs (rg lacks a --files-from flag; pipe paths in).
RG_OUT=$(printf '%s\n' "$CANDIDATE_FILES" | \
  xargs rg ${RG_EXTRA[@]+"${RG_EXTRA[@]}"} --no-heading --color=never --line-number --with-filename \
    -e "$PATTERN" 2>/dev/null || true)

if [ -z "$RG_OUT" ]; then
  echo "(no hits for /$PATTERN/)" >&2
  exit 1
fi

if [ "$JSON" = "1" ]; then
  # One JSON record per line: {slug, file, line_no, text}
  printf '%s\n' "$RG_OUT" | python3 -c '
import json, sys, os
for raw in sys.stdin:
  raw = raw.rstrip("\n")
  parts = raw.split(":", 2)
  if len(parts) < 3: continue
  file, line_no, text = parts
  slug = os.path.basename(file)[:-3] if file.endswith(".md") else os.path.basename(file)
  print(json.dumps({"slug": slug, "file": file, "line_no": int(line_no), "text": text}))
'
  exit 0
fi

# Default: slug-grouped human output.
printf '%s\n' "$RG_OUT" | awk -F: '
  BEGIN { current = "" }
  {
    file = $1
    line = $2
    rest = substr($0, length($1) + length($2) + 3)
    if (file != current) {
      current = file
      slug = file
      sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
      printf "\n=== %s ===\n", slug
    }
    printf "  %s:%s\n", line, rest
  }
'
