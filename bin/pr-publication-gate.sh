#!/usr/bin/env bash
# Check proposed public PR text and the exact HEAD diff before a create/edit call.
# Usage: pr-publication-gate.sh <base-ref> <title-file> <body-file>

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: pr-publication-gate.sh <base-ref> <title-file> <body-file>" >&2
  exit 2
fi

BASE=$1
TITLE=$2
BODY=$3
ROOT="$(git rev-parse --show-toplevel)" || exit 2
GUARD="$ROOT/bin/leak-guard.sh"
SCAN="$ROOT/skills/pr-review/bin/leak-scan.sh"

for file in "$TITLE" "$BODY"; do
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "pr-publication-gate: missing PR text file" >&2
    exit 2
  fi
done
for tool in "$GUARD" "$SCAN"; do
  if [ ! -f "$tool" ]; then
    echo "pr-publication-gate: required scanner unavailable" >&2
    exit 2
  fi
done
if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
  echo "pr-publication-gate: base ref does not resolve" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-publication-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cat "$TITLE" "$BODY" > "$TMP/pr-text"
if ! git diff --no-ext-diff --no-color --unified=0 "$BASE...HEAD" > "$TMP/diff"; then
  echo "pr-publication-gate: cannot read branch diff" >&2
  exit 2
fi
if [ ! -s "$TMP/diff" ]; then
  echo "pr-publication-gate: branch diff is empty" >&2
  exit 2
fi
awk '/^\+\+\+/ {next} /^\+/ {print substr($0, 2)}' "$TMP/diff" > "$TMP/added"

scan_text() {
  local label=$1 file=$2
  if ! bash "$GUARD" --stdin < "$file" >/dev/null 2>&1; then
    echo "pr-publication-gate: $label failed repository privacy scan" >&2
    exit 1
  fi
}

scan_text "PR title/body" "$TMP/pr-text"
if ! bash "$SCAN" --label "PR title/body" < "$TMP/pr-text" >/dev/null 2>&1; then
  echo "pr-publication-gate: PR title/body failed reviewer-text scan" >&2
  exit 1
fi
if [ -s "$TMP/added" ]; then
  scan_text "added lines" "$TMP/added"
fi
if ! bash "$GUARD" --tree >/dev/null 2>&1; then
  echo "pr-publication-gate: tracked files failed repository privacy scan" >&2
  exit 1
fi

echo "pr-publication-gate: clean PR text, added lines, and tracked files"
