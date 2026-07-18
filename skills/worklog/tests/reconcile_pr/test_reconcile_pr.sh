#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
HELPER="$REPO_ROOT/skills/worklog/bin/reconcile-pr.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

WORKLOG_FIXTURE="$SCRATCH/worklog"
FAKE_BIN="$SCRATCH/bin"
mkdir -p "$WORKLOG_FIXTURE/people/test/active" "$FAKE_BIN"
git -C "$WORKLOG_FIXTURE" init -q
git -C "$WORKLOG_FIXTURE" config user.name test
git -C "$WORKLOG_FIXTURE" config user.email test@example.com

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${GH_FIXTURE_FAIL:-0}" == "1" ]] && exit 1
printf '{"number":%s,"state":"%s","url":"https://github.com/acme/demo/pull/%s","isDraft":false,"mergedAt":%s}\n' \
  "${GH_FIXTURE_PR:-42}" "${GH_FIXTURE_STATE:-OPEN}" "${GH_FIXTURE_PR:-42}" "${GH_FIXTURE_MERGED_AT:-null}"
EOF
chmod +x "$FAKE_BIN/gh"

write_task() {
  local status="$1"
  cat > "$WORKLOG_FIXTURE/people/test/active/demo-task.md" <<EOF
---
slug: demo-task
status: $status
kind: impl
repos: [demo]
project: none
last_updated: 2026-07-18
next_action: "Verify linked PR"
---

## Context

Fixture.

## Next

- [ ] Verify.
EOF
  git -C "$WORKLOG_FIXTURE" add .
  git -C "$WORKLOG_FIXTURE" commit -q -m "demo-task: $status" -m $'Worklog-Slug: demo-task\nWorklog-PR: 42'
}

run_helper() {
  local slug="${1:-demo-task}"
  PATH="$FAKE_BIN:$PATH" \
    WORKLOG_REPO="$WORKLOG_FIXTURE" \
    WORKLOG_KNOWN_REPOS="acme/demo" \
    "$HELPER" "$slug"
}

write_task in-review
open_json="$(GH_FIXTURE_STATE=OPEN run_helper)"
python3 - "$open_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["slug"] == "demo-task"
assert data["expected"] == {"worklog_status": "in-review", "github_states": ["OPEN"]}
assert data["observed"][0]["state"] == "OPEN"
assert data["observed_at"].endswith("Z")
assert data["source"] == ["https://github.com/acme/demo/pull/42"]
assert data["mismatches"] == []
PY

write_task shipping
merged_json="$(GH_FIXTURE_STATE=OPEN GH_FIXTURE_MERGED_AT='"2026-07-18T12:00:00Z"' run_helper)"
python3 - "$merged_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["expected"]["github_states"] == ["MERGED"]
assert data["observed"][0]["state"] == "MERGED"
assert data["mismatches"] == []
PY

closed_json="$(GH_FIXTURE_STATE=CLOSED GH_FIXTURE_MERGED_AT=null run_helper)"
python3 - "$closed_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data["observed"][0]["state"] == "CLOSED"
assert data["mismatches"] == [{"pr": 42, "repo": "acme/demo", "expected": ["MERGED"], "observed": "CLOSED"}]
PY

if GH_FIXTURE_FAIL=1 run_helper >"$SCRATCH/fetch.out" 2>"$SCRATCH/fetch.err"; then
  echo "expected GitHub fetch failure" >&2
  exit 1
fi
test ! -s "$SCRATCH/fetch.out"
grep -q "failed to fetch" "$SCRATCH/fetch.err"

python3 - "$WORKLOG_FIXTURE/people/test/active/demo-task.md" "$WORKLOG_FIXTURE/people/test/active/missing-task.md" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(source.replace("demo-task", "missing-task"))
PY
git -C "$WORKLOG_FIXTURE" add .
git -C "$WORKLOG_FIXTURE" commit -q -m "missing-task: create" -m "Worklog-Slug: missing-task"
if run_helper missing-task >"$SCRATCH/missing.out" 2>"$SCRATCH/missing.err"; then
  echo "expected missing PR linkage failure" >&2
  exit 1
fi
test ! -s "$SCRATCH/missing.out"
grep -q "no authoritative Worklog-PR" "$SCRATCH/missing.err" || {
  cat "$SCRATCH/missing.err" >&2
  exit 1
}

echo "reconcile-pr: fixtures passed"
