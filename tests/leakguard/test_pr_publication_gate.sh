#!/usr/bin/env bash
# Exercise the public PR gate in a disposable repository.

set -euo pipefail

SOURCE="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-publication-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

git init -q
git config user.email test@example.invalid
git config user.name test
mkdir -p bin skills/pr-review/bin
cp "$SOURCE/bin/leak-guard.sh" "$SOURCE/bin/pr-publication-gate.sh" bin/
cp "$SOURCE/skills/pr-review/bin/leak-scan.sh" skills/pr-review/bin/
git add .
git -c core.hooksPath=/dev/null commit -qm base
BASE="$(git rev-parse HEAD)"
printf 'safe change\n' > feature.txt
git add feature.txt
git -c core.hooksPath=/dev/null commit -qm feature

printf 'Describe feature\n' > "$TMP/title"
printf 'Adds a repeatable browser check.\n' > "$TMP/body"
bash bin/pr-publication-gate.sh "$BASE" "$TMP/title" "$TMP/body" >/dev/null || {
  echo "FAIL: clean PR was blocked" >&2
  exit 1
}

printf 'next_action: internal note\n' > "$TMP/body"
if bash bin/pr-publication-gate.sh "$BASE" "$TMP/title" "$TMP/body" >"$TMP/out" 2>&1; then
  echo "FAIL: reviewer-text leak passed" >&2
  exit 1
fi
if grep -q 'internal note' "$TMP/out"; then
  echo "FAIL: gate printed PR text" >&2
  exit 1
fi

printf 'PATH=/%s/%s/project\n' Users alice > "$TMP/body"
if bash bin/pr-publication-gate.sh "$BASE" "$TMP/title" "$TMP/body" >"$TMP/out" 2>&1; then
  echo "FAIL: private path in body passed" >&2
  exit 1
fi
if grep -q 'alice' "$TMP/out"; then
  echo "FAIL: gate printed private path" >&2
  exit 1
fi

printf 'Adds a repeatable browser check.\n' > "$TMP/body"
printf 'PATH=/%s/%s/project\n' Users alice > feature.txt
git add feature.txt
git -c core.hooksPath=/dev/null commit -qm changed-feature
if bash bin/pr-publication-gate.sh "$BASE" "$TMP/title" "$TMP/body" >"$TMP/out" 2>&1; then
  echo "FAIL: private path in added lines passed" >&2
  exit 1
fi
if grep -q 'alice' "$TMP/out"; then
  echo "FAIL: gate printed private added line" >&2
  exit 1
fi

echo "ok: PR gate passes clean text and blocks private body or diff content without echoing it"
