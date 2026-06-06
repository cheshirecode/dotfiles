#!/usr/bin/env bash
# test_round_trip.sh — frontmatter round-trip integrity test.
#
# Reads tests/frontmatter/round_trip.md via the same yaml.safe_load path that
# bin/_lint.py and bin/_index.py use, re-emits with yaml.safe_dump, and asserts
# every key + nested shape survived. Catches the "list-of-mappings dropped to
# scalar list" regression class flagged in audit-prompt § 4.
#
# We don't assert byte-identical raw text — yaml.safe_dump normalizes ordering
# and quoting. The contract is: every key parses back to an equivalent value
# (including list-of-mappings with continuation fields like `note:`).
#
# Usage: tests/frontmatter/test_round_trip.sh
# Exit:  0 round-trip preserved, 1 shape lost, 2 invocation.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."

FIXTURE="tests/frontmatter/round_trip.md"
[[ -f "$FIXTURE" ]] || { echo "missing $FIXTURE" >&2; exit 2; }

python3 - "$FIXTURE" <<'PY'
import re
import sys
import yaml

path = sys.argv[1]
text = open(path).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
if not m:
    print("FAIL: fixture has no frontmatter block", file=sys.stderr)
    sys.exit(1)

original = yaml.safe_load(m.group(1))
roundtripped = yaml.safe_load(yaml.safe_dump(original, sort_keys=False))

if original != roundtripped:
    print("FAIL: round-trip changed the parsed structure", file=sys.stderr)
    print(f"  original:    {original}", file=sys.stderr)
    print(f"  roundtripped: {roundtripped}", file=sys.stderr)
    sys.exit(1)

# Shape spot-checks — these are the audit-prompt's named regression classes.
assert isinstance(original.get("repos"), list), "repos must be a list"
related = original.get("related")
assert isinstance(related, list) and related, "related must be a non-empty list"
for i, item in enumerate(related):
    assert isinstance(item, dict), f"related[{i}] must be a mapping (not scalar)"
    assert "slug" in item, f"related[{i}] missing slug"
    assert "note" in item, f"related[{i}] missing note (continuation field — exactly the shape that historically dropped)"

ext = original.get("external_refs")
assert isinstance(ext, list) and ext and isinstance(ext[0], dict), "external_refs list-of-mappings shape lost"

pr = original.get("pr")
assert isinstance(pr, list) and all(isinstance(n, int) for n in pr), "pr must be a list of ints"

print("frontmatter: round-trip preserved every shape ✓")
PY
