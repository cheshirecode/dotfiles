#!/usr/bin/env bash
# End-to-end test for bin/transcript-dump.sh + auto-triggers from
# archive.sh / checkpoint.sh.
#
# Acceptance (from worklog-transcript-dump spec, 2026-05-14 design):
#   T1  empty transcripts/X.md → first trigger creates file with one
#       `## Session ... — <trigger> @ <ts>` section + content
#   T2  existing transcripts/X.md with mtime T → second trigger appends
#       only messages with timestamp > T (watermark)
#   T3  CLAUDE_CODE_SESSION_ID + WORKLOG_TRANSCRIPT_JSONL unset → silent skip
#   T4  WORKLOG_NO_TRANSCRIPT=1 → silent skip
#   T5  bin/archive.sh X → trigger fires + body has `Transcript: ...` line
#       after the `Archived <date>: <reason>.` marker
#   T6  bin/checkpoint.sh X --status=in-review → trigger fires + body NOT
#       modified (only archive writes the body link)
#   T7  bin/checkpoint.sh X --status=blocked → trigger does NOT fire
#   T8  bin/transcript-dump.sh X (manual) → trigger fires + body NOT modified
#   T9  Header is `# Slug: X` (from wrapper), NOT empty
#
# Runs against a scratch clone so production worklog isn't touched.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t transcript-dump-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
UPSTREAM="$SCRATCH_ROOT/upstream.git"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Setup ==="
git init -q --bare "$UPSTREAM"
git clone -q "$SOURCE" "$SCRATCH"
rm -rf "$SCRATCH/bin"
cp -R "$SOURCE/bin" "$SCRATCH/bin"
rm -rf "$SCRATCH/bin/__pycache__"
cd "$SCRATCH"
git remote set-url origin "$UPSTREAM"
git push -q origin HEAD:main
git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
git config user.email "testuser@example.com"
git config user.name "transcript-dump-test"

LDAP="testuser"
printf '%s' "$LDAP" > "$TMPDIR/worklog-ldap-${USER}"
rm -rf people
mkdir -p "people/$LDAP/active" "people/$LDAP/archive"
touch "people/$LDAP/archive/.gitkeep"
export WORKLOG_NO_HOOK=1
export WORKLOG_SKIP_PROVENANCE=1
mkdir -p .cache; touch .cache/provenance-verified
git add -A && git commit -q -m "seed" --no-verify && git push -q origin main

# JSONL fixture: 5 entries spanning 3 minutes; the watermark test cuts the
# stream mid-session.
FIXTURE="$SCRATCH_ROOT/fixture.jsonl"
cat > "$FIXTURE" <<'EOF'
{"type":"user","sessionId":"fixture-session","gitBranch":"main","timestamp":"2026-05-15T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"EARLY-USER-MSG create task X"}]}}
{"type":"assistant","timestamp":"2026-05-15T10:00:30Z","message":{"role":"assistant","content":[{"type":"text","text":"EARLY-ASSISTANT-MSG creating"}]}}
{"type":"assistant","timestamp":"2026-05-15T10:01:00Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"bin/checkpoint.sh X"}}]}}
{"type":"user","timestamp":"2026-05-15T10:02:00Z","message":{"role":"user","content":[{"type":"text","text":"LATE-USER-MSG more work"}]}}
{"type":"assistant","timestamp":"2026-05-15T10:03:00Z","message":{"role":"assistant","content":[{"type":"text","text":"LATE-ASSISTANT-MSG continuing"}]}}
EOF
export WORKLOG_TRANSCRIPT_JSONL="$FIXTURE"
export CLAUDE_CODE_SESSION_ID="fixture-session"

# Seed an active task to dump against.
cat > "people/$LDAP/active/dumptest.md" <<'EOF'
---
slug: dumptest
status: in-progress
kind: tooling
repos: []
project: none
last_updated: 2026-05-15
next_action: "test"
---

## Context

Test task for transcript dump.
EOF
git add -A && git commit -q -m "seed dumptest" --no-verify

echo ""
echo "=== T1: empty transcripts/dumptest.md → first dump creates file with section + content ==="
[[ ! -e "people/$LDAP/transcripts/dumptest.md" ]] || { echo "FAIL: precondition - file already exists"; exit 1; }
"$WORKLOG_BIN/transcript-dump.sh" dumptest 2>&1 | tail -3
TRANSCRIPT="people/$LDAP/transcripts/dumptest.md"
[[ -f "$TRANSCRIPT" ]] || { echo "FAIL T1: transcripts/dumptest.md not created"; exit 1; }
grep -q "^## Session" "$TRANSCRIPT" || { echo "FAIL T1: no Session section header"; cat "$TRANSCRIPT"; exit 1; }
grep -q "EARLY-USER-MSG" "$TRANSCRIPT" || { echo "FAIL T1: missing EARLY-USER-MSG"; exit 1; }
grep -q "LATE-ASSISTANT-MSG" "$TRANSCRIPT" || { echo "FAIL T1: missing LATE-ASSISTANT-MSG"; exit 1; }
echo "  ✓ first dump creates file with section + full content"

echo ""
echo "=== T9: header is '# Slug: dumptest' (not empty) ==="
head -1 "$TRANSCRIPT" | grep -q "^# Slug: dumptest$" \
  || { echo "FAIL T9: header wrong"; head -3 "$TRANSCRIPT"; exit 1; }
echo "  ✓ header reads '# Slug: dumptest'"

echo ""
echo "=== T2: existing file with mtime T → second dump appends only post-T messages ==="
# Set mtime to between the EARLY (10:01:00Z) and LATE (10:02:00Z) entries.
# Use Python to set an exact UTC unix timestamp — macOS `touch -t` interprets
# local time, which breaks the watermark test in any non-UTC timezone.
python3 -c "
import os, datetime as dt
target = dt.datetime(2026, 5, 15, 10, 1, 30, tzinfo=dt.timezone.utc).timestamp()
os.utime('$TRANSCRIPT', (target, target))
"
PRE_SECTIONS=$(grep -c "^## Session" "$TRANSCRIPT")
"$WORKLOG_BIN/transcript-dump.sh" dumptest 2>&1 | tail -3
POST_SECTIONS=$(grep -c "^## Session" "$TRANSCRIPT")
[[ "$POST_SECTIONS" -gt "$PRE_SECTIONS" ]] \
  || { echo "FAIL T2: no new section appended"; exit 1; }
# Pull the LAST section (the one we just appended).
LAST_SECTION="$(awk '/^## Session/{n++} n==('"$POST_SECTIONS"'){print}' "$TRANSCRIPT")"
echo "$LAST_SECTION" | grep -q "LATE-USER-MSG" \
  || { echo "FAIL T2: post-watermark message missing from new section"; echo "$LAST_SECTION"; exit 1; }
# A naive check that early messages are NOT in the new section. The watermark
# is exclusive: messages with timestamp >= watermark go in. Set the watermark
# strict-after the EARLY 10:00:30 line, so it MUST be excluded from new section.
if echo "$LAST_SECTION" | grep -q "EARLY-ASSISTANT-MSG"; then
  echo "FAIL T2: pre-watermark message leaked into new section"
  echo "$LAST_SECTION"
  exit 1
fi
echo "  ✓ second dump appends only post-watermark messages"

echo ""
echo "=== T3: env unset → silent skip ==="
rm -f "$TRANSCRIPT"
(unset CLAUDE_CODE_SESSION_ID; unset WORKLOG_TRANSCRIPT_JSONL; \
  "$WORKLOG_BIN/transcript-dump.sh" dumptest >/dev/null 2>&1)
RC=$?
[[ "$RC" -eq 0 ]] || { echo "FAIL T3: expected exit 0 got $RC"; exit 1; }
[[ ! -f "$TRANSCRIPT" ]] || { echo "FAIL T3: file created despite unset env"; exit 1; }
echo "  ✓ silent skip; no file"

echo ""
echo "=== T4: WORKLOG_NO_TRANSCRIPT=1 → silent skip ==="
WORKLOG_NO_TRANSCRIPT=1 "$WORKLOG_BIN/transcript-dump.sh" dumptest >/dev/null 2>&1
[[ ! -f "$TRANSCRIPT" ]] || { echo "FAIL T4: file created despite WORKLOG_NO_TRANSCRIPT=1"; exit 1; }
echo "  ✓ silent skip"

echo ""
echo "=== T5: "$WORKLOG_BIN/archive.sh" fires trigger + body link ==="
"$WORKLOG_BIN/transcript-dump.sh" dumptest >/dev/null 2>&1  # ensure file exists for T5
"$WORKLOG_BIN/archive.sh" dumptest --reason=shipped --summary="test archive" >/dev/null 2>&1
ARCHIVED="people/$LDAP/archive/dumptest.md"
[[ -f "$ARCHIVED" ]] || { echo "FAIL T5: file not archived"; exit 1; }
grep -q "Transcript:.*transcripts/dumptest\.md" "$ARCHIVED" \
  || { echo "FAIL T5: no Transcript: line in archived body"; head -30 "$ARCHIVED"; exit 1; }
echo "  ✓ archive trigger fires + body link added"

echo ""
echo "=== T6: "$WORKLOG_BIN/checkpoint.sh" --status=in-review fires trigger + body NOT modified ==="
cat > "people/$LDAP/active/dump6.md" <<'EOF'
---
slug: dump6
status: in-progress
kind: tooling
repos: []
project: none
last_updated: 2026-05-15
next_action: "test"
---

## Context

T6 task.
EOF
git add -A && git commit -q -m "seed dump6" --no-verify
BODY_BEFORE=$(sha1sum "people/$LDAP/active/dump6.md")
"$WORKLOG_BIN/checkpoint.sh" dump6 --status=in-review >/dev/null 2>&1 || true
[[ -f "people/$LDAP/transcripts/dump6.md" ]] \
  || { echo "FAIL T6: status-flip did not fire transcript dump"; exit 1; }
# Body changed (checkpoint flips status + last_updated), but should NOT have Transcript: line.
grep -q "Transcript:" "people/$LDAP/active/dump6.md" \
  && { echo "FAIL T6: status-flip wrongly added Transcript: line"; exit 1; }
echo "  ✓ in-review trigger fires + no body link"

echo ""
echo "=== T7: "$WORKLOG_BIN/checkpoint.sh" --status=blocked does NOT fire ==="
cat > "people/$LDAP/active/dump7.md" <<'EOF'
---
slug: dump7
status: in-progress
kind: tooling
repos: []
project: none
last_updated: 2026-05-15
next_action: "test"
---

## Context

T7 task.
EOF
git add -A && git commit -q -m "seed dump7" --no-verify
"$WORKLOG_BIN/checkpoint.sh" dump7 --status=blocked --next="Waiting on test" >/dev/null 2>&1 || true
[[ ! -f "people/$LDAP/transcripts/dump7.md" ]] \
  || { echo "FAIL T7: --status=blocked should not trigger dump"; exit 1; }
echo "  ✓ --status=blocked does not fire"

echo ""
echo "=== T8: manual "$WORKLOG_BIN/transcript-dump.sh" fires + body NOT modified ==="
cat > "people/$LDAP/active/dump8.md" <<'EOF'
---
slug: dump8
status: in-progress
kind: tooling
repos: []
project: none
last_updated: 2026-05-15
next_action: "test"
---

## Context

T8 task.
EOF
git add -A && git commit -q -m "seed dump8" --no-verify
BODY8_BEFORE=$(sha1sum "people/$LDAP/active/dump8.md")
"$WORKLOG_BIN/transcript-dump.sh" dump8 >/dev/null 2>&1
[[ -f "people/$LDAP/transcripts/dump8.md" ]] \
  || { echo "FAIL T8: manual dump did not create file"; exit 1; }
BODY8_AFTER=$(sha1sum "people/$LDAP/active/dump8.md")
[[ "$BODY8_BEFORE" == "$BODY8_AFTER" ]] \
  || { echo "FAIL T8: manual dump modified body"; exit 1; }
echo "  ✓ manual dump creates file + leaves body unchanged"

echo ""
echo "=== T10: production-path resolver — no WORKLOG_TRANSCRIPT_JSONL override ==="
# Regression test for 2026-05-15: original sanitization used str.replace('/', '-')
# but Claude Code's actual algorithm also replaces underscores (and any other
# non-alphanumeric char). The fixture must live at the sanitized-cwd path so
# resolve_jsonl_path() can find it WITHOUT an override.
cat > "people/$LDAP/active/dump10.md" <<'EOF'
---
slug: dump10
status: in-progress
kind: tooling
repos: []
project: none
last_updated: 2026-05-15
next_action: "test"
---

## Context

T10 task — production path resolver.
EOF
git add -A && git commit -q -m "seed dump10" --no-verify

# Sanitize cwd the SAME way the production code does so the fixture path matches.
FAKE_HOME="$SCRATCH_ROOT/fake-home"
SANITIZED="$(python3 -c "import re,pathlib; print(re.sub(r'[^a-zA-Z0-9]', '-', str(pathlib.Path.cwd().resolve())))")"
PROJ_DIR="$FAKE_HOME/.claude/projects/$SANITIZED"
mkdir -p "$PROJ_DIR"
cp "$FIXTURE" "$PROJ_DIR/fixture-session.jsonl"
(unset WORKLOG_TRANSCRIPT_JSONL; HOME="$FAKE_HOME" "$WORKLOG_BIN/transcript-dump.sh" dump10 2>&1 | tail -3)
TRANSCRIPT="people/$LDAP/transcripts/dump10.md"
[[ -f "$TRANSCRIPT" ]] || { echo "FAIL T10: resolver did not find JSONL at sanitized path $PROJ_DIR"; ls -la "$FAKE_HOME/.claude/projects/" 2>&1; exit 1; }
grep -q "EARLY-USER-MSG" "$TRANSCRIPT" || { echo "FAIL T10: transcript content missing"; exit 1; }
echo "  ✓ resolver finds JSONL at sanitized path (non-alnum → '-')"

echo ""
echo "All transcript-dump assertions passed."
