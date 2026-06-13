#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/bin/git-hooks/commit-msg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q
git config user.email tester@example.com
git config user.name Tester
mkdir -p people/tester/active

for slug in first-task second-task; do
  cat > "people/tester/active/$slug.md" <<EOF
---
slug: $slug
kind: impl
status: in-progress
project: sample
last_updated: 2026-06-12
next_action: Keep going
repos: [sample]
---

## Context
$slug context.

## Next
Keep going.
EOF
done

msg="$TMP/msg.txt"
cat > "$msg" <<'EOF'
batch: hand-written trailers

Worklog-Slug: first-task
Worklog-Slug: second-task
Worklog-Status: done
EOF

if "$HOOK" "$msg" >"$TMP/out.txt" 2>&1; then
  echo "FAIL: invalid Worklog-Status should reject even when trailer counts differ"
  exit 1
fi
grep -q "invalid Worklog-Status: done" "$TMP/out.txt"

cat > "$msg" <<'EOF'
batch: hand-written trailers

Worklog-Slug: first-task
Worklog-Slug: second-task
Worklog-Status: in-progress
EOF

"$HOOK" "$msg"

echo "ok: commit-msg status trailer validation"
