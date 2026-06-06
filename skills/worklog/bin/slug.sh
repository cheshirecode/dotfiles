#!/usr/bin/env bash
# slug.sh — closest-match slug lookup across people/*/{active,archive}/.
#
# Usage:
#   bin/slug.sh <fragment>          print best match slug; exit 1 if no match
#   bin/slug.sh --all <fragment>    print all matches scored, best first
#
# Match policy:
#   1. Exact slug → return it.
#   2. Substring (case-insensitive) → score by length-ratio + position.
#   3. Levenshtein-ish via awk → only if substring path empty.
#
# Used by:
#   - bin/git-hooks/commit-msg suggests closest match for typo'd Worklog-Slug:
#   - hand-typed slug references in any future tool

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

ALL=0
[[ "${1:-}" == "--all" ]] && { ALL=1; shift; }
FRAG="${1:-}"
[[ -z "$FRAG" ]] && { echo "usage: bin/slug.sh [--all] <fragment>" >&2; exit 2; }

# Enumerate every slug.
ALL_SLUGS="$(find people -mindepth 3 -maxdepth 3 -name '*.md' -type f 2>/dev/null \
  | sed 's|.*/||; s|\.md$||' | sort -u)"

[[ -z "$ALL_SLUGS" ]] && exit 1

# Exact match: short-circuit.
if printf '%s\n' "$ALL_SLUGS" | grep -qxF "$FRAG"; then
  echo "$FRAG"
  exit 0
fi

# Substring matches: case-insensitive contains. Score = len(fragment)/len(slug).
# Higher = closer match.
SUBSTR="$(printf '%s\n' "$ALL_SLUGS" | python3 -c "
import sys
frag = sys.argv[1].lower()
hits = []
for s in sys.stdin.read().splitlines():
  if frag in s.lower():
    score = len(frag) / max(len(s), 1)
    hits.append((score, s))
hits.sort(reverse=True)
for score, s in hits:
  print(f'{score:.3f}\t{s}')
" "$FRAG" 2>/dev/null || true)"

if [[ -n "$SUBSTR" ]]; then
  if (( ALL )); then
    echo "$SUBSTR" | awk '{print $2}'
  else
    echo "$SUBSTR" | head -1 | awk '{print $2}'
  fi
  exit 0
fi

# Levenshtein-ish fallback for typos that don't substring-match.
LEV="$(printf '%s\n' "$ALL_SLUGS" | python3 -c "
import sys
frag = sys.argv[1].lower()
def lev(a, b):
  m, n = len(a), len(b)
  if m == 0: return n
  if n == 0: return m
  dp = list(range(n + 1))
  for i, ca in enumerate(a, 1):
    prev, dp[0] = dp[0], i
    for j, cb in enumerate(b, 1):
      cur = dp[j]
      dp[j] = min(dp[j] + 1, dp[j-1] + 1, prev + (ca != cb))
      prev = cur
  return dp[n]
hits = []
for s in sys.stdin.read().splitlines():
  d = lev(frag, s.lower())
  hits.append((d, s))
hits.sort()
# Threshold: distance must be < 50% of fragment length to count as a match.
threshold = max(2, len(frag) // 2)
for d, s in hits[:5 if '$ALL' == '1' else 1]:
  if d <= threshold:
    print(s)
" "$FRAG" 2>/dev/null || true)"

if [[ -n "$LEV" ]]; then
  echo "$LEV"
  exit 0
fi

exit 1
