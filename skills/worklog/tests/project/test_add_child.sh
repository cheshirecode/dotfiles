#!/usr/bin/env bash
# `project.sh add-child` — add ONE child task to an EXISTING project.
#
# The defect this pins is a silent wrong answer, not a crash. Before this
# subcommand existed the only way to add a child to a live project was to
# hand-write the stub and hand-edit the parent's `tasks:` block. Skip the
# second half — which is what a scheduled "create today's child task" job does
# when it only knows how to write a file — and you get an ORPHAN: a task file
# carrying `project:`/`parent_slug:` that the parent never declares. Nothing
# errors. `project verify` walks the parent's `tasks:` block, so it never sees
# the orphan and stays exit-0-clean, and `project next` can never hand the
# orphan to a worker. The work exists on disk and is unreachable forever.
#
# So the assertions below are deliberately NOT "add-child exits 0". They are:
#   - the orphan is invisible to `project next` (the pre-fix state), and
#   - add-child makes it reachable, with `project verify` still exit 0.
#
# Runs against a scratch vault + bare upstream; never touches a real worklog.

set -euo pipefail

# Self-isolate. tests/run.sh wraps worklog fixtures in WL_HERMETIC for a reason:
# every child `bash` sources $BASH_ENV, and a developer profile that exports
# WORKLOG_REPO/WORKLOG_LDAP unconditionally overwrites this fixture's own
# exports *inside* project.sh/archive.sh. The scratch vault below then looks
# correct while the tools underneath it commit and push to the real worklog.
# Unsetting BASH_ENV here removes it from the environment children inherit, so
# the fixture is safe run bare as well as under the runner.
unset BASH_ENV
unset WORKLOG_NS

# Pinned, not `${WORKLOG_BIN:-...}`. A developer shell exports WORKLOG_BIN
# pointing at the *installed* skill (~/.claude/skills/worklog/bin), and
# WL_HERMETIC does not strip it — so a defaulted assignment silently tests the
# installed copy instead of the tree this fixture ships in, and a green run
# proves nothing about the change under review.
export WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t project-addchild-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
UPSTREAM="$SCRATCH_ROOT/upstream.git"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Setup ==="
git init -q --bare --initial-branch=main "$UPSTREAM"
# See test_phase1.sh for why this inits a scratch data repo rather than cloning
# $SOURCE, and why WORKLOG_REPO must be pinned to the scratch.
git init -q --initial-branch=main "$SCRATCH"
cp -R "$SOURCE/bin" "$SCRATCH/bin"
rm -rf "$SCRATCH/bin/__pycache__"
cd "$SCRATCH"
export WORKLOG_REPO="$SCRATCH"
git config user.email "testuser@example.com"
git config user.name "add-child-test"
git remote add origin "$UPSTREAM"
git add -A && git -c commit.gpgsign=false commit -q -m "seed: bin" --no-verify
git push -q origin HEAD:main
git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

LDAP="testuser"
export WORKLOG_LDAP="$LDAP"
rm -rf people
mkdir -p "people/$LDAP/active" "people/$LDAP/archive"
touch "people/$LDAP/archive/.gitkeep"
git add -A && git commit -q -m "seed" --no-verify && git push -q origin main

export WORKLOG_NO_HOOK=1
export WORKLOG_SKIP_PROVENANCE=1
mkdir -p .cache; touch .cache/provenance-verified

ACTIVE="people/$LDAP/active"

verify_rc() {
  local rc=0
  "$WORKLOG_BIN/project.sh" verify "$1" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

echo ""
echo "=== 1: seed an existing project with one child ==="
echo '[{"slug":"ac-a"}]' | "$WORKLOG_BIN/project.sh" new ac-proj \
  --goal "Daily rollup" --objective "One child per day" >/dev/null
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || { echo "FAIL: freshly created project should verify clean, got exit $rc"; exit 1; }
echo "  ok: ac-proj verifies clean (exit 0)"

# The mirror image of the orphan, done in the other order: declare the child in
# tasks: and forget to write the file. THAT half verify does reject, loudly.
cp "$ACTIVE/ac-proj.md" "$SCRATCH_ROOT/ac-proj.bak"
python3 - "$ACTIVE/ac-proj.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
open(p, "w").write(t.replace("tasks:\n", "tasks:\n  - slug: ac-never-written\n", 1))
PY
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 2 ]] || { echo "FAIL: expected exit 2 for a declared-but-missing child, got $rc"; exit 1; }
cp "$SCRATCH_ROOT/ac-proj.bak" "$ACTIVE/ac-proj.md"
[[ "$(verify_rc ac-proj)" -eq 0 ]] || { echo "FAIL: restore failed"; exit 1; }
echo "  ok: the mirror-image hand-edit (declared, no file) is an exit-2 error"

echo ""
echo "=== 2: the manual workaround produces an unreachable orphan ==="
# Exactly what a hand-rolled "write today's child stub" step produces: correct
# frontmatter, correct back-reference, and no entry in the parent's tasks:.
cat > "$ACTIVE/ac-orphan.md" <<EOF
---
slug: ac-orphan
status: draft
kind: impl
repos: []
project: ac-proj
parent_slug: ac-proj
last_updated: 2026-09-02
next_action: "Awaiting claim — child of ac-proj"
---

## Context

Child task of [[ac-proj]].

## Next

- [ ] Claim via \`bin/project.sh claim ac-orphan\` (phase 2)
EOF
git add "$ACTIVE/ac-orphan.md"
git commit -q -m "ac-orphan: hand-written child stub" --no-verify

# The silent part: verify stays clean because it only walks tasks:.
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || { echo "FAIL: expected the orphan to slip past verify (exit 0), got $rc"; exit 1; }
# The wrong part: the orphan can never be handed out.
"$WORKLOG_BIN/archive.sh" ac-a --reason=shipped >/dev/null 2>&1
if nxt="$("$WORKLOG_BIN/project.sh" next ac-proj 2>/dev/null)"; then
  [[ "$nxt" != "ac-orphan" ]] || { echo "FAIL: fixture broken — orphan was already reachable"; exit 1; }
  echo "FAIL: expected no eligible task, got '$nxt'"; exit 1
fi
echo "  ok: orphan is invisible to project next while verify reports clean"

echo ""
echo "=== 3: add-child adopts the orphan and makes it reachable ==="
BEFORE="$(git rev-list --count HEAD)"
"$WORKLOG_BIN/project.sh" add-child ac-proj ac-orphan
AFTER="$(git rev-list --count HEAD)"
[[ $((AFTER - BEFORE)) -eq 1 ]] || {
  echo "FAIL: expected exactly 1 commit for stub+parent, got $((AFTER - BEFORE))"; exit 1; }
echo "  ok: stub + parent tasks: entry landed in one commit"

grep -q '^  - slug: ac-orphan$' "$ACTIVE/ac-proj.md" || {
  echo "FAIL: parent tasks: block is missing ac-orphan"; sed -n '1,40p' "$ACTIVE/ac-proj.md"; exit 1; }
# The adopted body must survive untouched.
grep -q 'Child task of \[\[ac-proj\]\]' "$ACTIVE/ac-orphan.md" || {
  echo "FAIL: adopt rewrote the existing child body"; exit 1; }
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || {
  echo "FAIL: project verify must exit 0 after add-child, got $rc"
  "$WORKLOG_BIN/project.sh" verify ac-proj; exit 1; }
out="$("$WORKLOG_BIN/project.sh" next ac-proj)"
[[ "$out" == "ac-orphan" ]] || { echo "FAIL: expected next=ac-orphan, got '$out'"; exit 1; }
echo "  ok: verify exit 0 and project next now returns ac-orphan"

echo ""
echo "=== 4: re-running add-child is an idempotent no-op ==="
BEFORE="$(git rev-list --count HEAD)"
"$WORKLOG_BIN/project.sh" add-child ac-proj ac-orphan
AFTER="$(git rev-list --count HEAD)"
[[ "$BEFORE" == "$AFTER" ]] || { echo "FAIL: re-run created a commit"; exit 1; }
# Count inside tasks: specifically — the slug also appears under related:, so a
# whole-file grep would pass even with a duplicated task entry.
python3 - "$ACTIVE/ac-proj.md" <<'PY'
import sys, yaml
fm = yaml.safe_load(open(sys.argv[1]).read().split("---\n")[1])
n = sum(1 for t in fm["tasks"] if t.get("slug") == "ac-orphan")
assert n == 1, f"duplicate tasks: entry (count={n})"
r = sum(1 for t in (fm.get("related") or []) if t.get("slug") == "ac-orphan")
assert r == 1, f"duplicate related: entry (count={r})"
PY
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || { echo "FAIL: verify non-zero after idempotent re-run: $rc"; exit 1; }
echo "  ok: re-run adds no commit, no duplicate entry, verify still 0"

echo ""
echo '=== 5: add-child creates a brand-new stub matching `new`s shape ==='
"$WORKLOG_BIN/project.sh" add-child ac-proj ac-fresh --kind=debug --title="Look into it"
[[ -f "$ACTIVE/ac-fresh.md" ]] || { echo "FAIL: stub not created"; exit 1; }
for line in 'slug: ac-fresh' 'status: draft' 'kind: debug' 'project: ac-proj' 'parent_slug: ac-proj'; do
  grep -q "^$line\$" "$ACTIVE/ac-fresh.md" || {
    echo "FAIL: stub frontmatter missing '$line'"; sed -n '1,15p' "$ACTIVE/ac-fresh.md"; exit 1; }
done
grep -q 'Look into it' "$ACTIVE/ac-fresh.md" || { echo "FAIL: --title not used as Context"; exit 1; }
# Trailers must name both the project and the child, like `project new` does.
git log -1 --format=%B | grep -q '^Worklog-Slug: ac-proj$' || { echo "FAIL: missing parent trailer"; exit 1; }
git log -1 --format=%B | grep -q '^Worklog-Slug: ac-fresh$' || { echo "FAIL: missing child trailer"; exit 1; }
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || { echo "FAIL: verify non-zero after fresh add-child: $rc"; exit 1; }
echo "  ok: fresh stub matches new's frontmatter, trailers name both slugs"

echo ""
echo "=== 6: --depends-on wires the parent tasks: block ==="
"$WORKLOG_BIN/project.sh" add-child ac-proj ac-dep --depends-on=ac-fresh
python3 - "$ACTIVE/ac-proj.md" <<'PY'
import sys, yaml
fm = yaml.safe_load(open(sys.argv[1]).read().split("---\n")[1])
t = {x["slug"]: x for x in fm["tasks"]}
assert t["ac-dep"].get("depends_on") == ["ac-fresh"], t["ac-dep"]
PY
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || { echo "FAIL: verify non-zero with depends_on: $rc"; exit 1; }
# ac-dep is blocked behind ac-fresh, so next must not hand it out.
out="$("$WORKLOG_BIN/project.sh" next ac-proj)"
[[ "$out" != "ac-dep" ]] || { echo "FAIL: next handed out a dep-blocked child"; exit 1; }
echo "  ok: depends_on recorded and respected by next"

echo ""
echo "=== 7: bad input is refused before anything is written ==="
if "$WORKLOG_BIN/project.sh" add-child ac-proj ac-bad --kind=notakind >/dev/null 2>&1; then
  echo "FAIL: unknown kind accepted"; exit 1
fi
[[ ! -e "$ACTIVE/ac-bad.md" ]] || { echo "FAIL: rejected kind still wrote a stub"; exit 1; }
if "$WORKLOG_BIN/project.sh" add-child ac-proj ac-bad2 --depends-on=nope-not-here >/dev/null 2>&1; then
  echo "FAIL: depends_on on an undeclared slug accepted"; exit 1
fi
[[ ! -e "$ACTIVE/ac-bad2.md" ]] || { echo "FAIL: rejected dep still wrote a stub"; exit 1; }
if "$WORKLOG_BIN/project.sh" add-child ac-fresh ac-bad3 >/dev/null 2>&1; then
  echo "FAIL: accepted a non-project parent"; exit 1
fi
if "$WORKLOG_BIN/project.sh" add-child ac-proj ac-proj >/dev/null 2>&1; then
  echo "FAIL: accepted the project as its own child"; exit 1
fi
rc="$(verify_rc ac-proj)"
[[ "$rc" -eq 0 ]] || { echo "FAIL: rejected input left the project dirty: $rc"; exit 1; }
echo "  ok: unknown kind / undeclared dep / non-project parent / self all refused"

echo ""
echo "=== 8: a child owned by another project is refused, not silently stolen ==="
echo '[{"slug":"other-a"}]' | "$WORKLOG_BIN/project.sh" new ac-other \
  --goal "Second project" --objective "Owns other-a" >/dev/null
if "$WORKLOG_BIN/project.sh" add-child ac-proj other-a >/dev/null 2>&1; then
  echo "FAIL: adopted a child already owned by ac-other"; exit 1
fi
grep -q '^parent_slug: ac-other$' "$ACTIVE/other-a.md" || {
  echo "FAIL: refused add-child still rewrote the other project's child"; exit 1; }
[[ "$(verify_rc ac-other)" -eq 0 ]] || { echo "FAIL: ac-other no longer verifies clean"; exit 1; }
echo "  ok: cross-project steal refused, both projects still clean"

echo ""
echo "=== 9: --dry-run writes nothing ==="
BEFORE="$(git rev-list --count HEAD)"
"$WORKLOG_BIN/project.sh" add-child ac-proj ac-dry --dry-run >/dev/null
[[ ! -e "$ACTIVE/ac-dry.md" ]] || { echo "FAIL: --dry-run wrote a stub"; exit 1; }
if grep -q 'ac-dry' "$ACTIVE/ac-proj.md"; then echo "FAIL: --dry-run edited the parent"; exit 1; fi
[[ "$(git rev-list --count HEAD)" == "$BEFORE" ]] || { echo "FAIL: --dry-run committed"; exit 1; }
echo "  ok: --dry-run is inert"

echo ""
echo "All add-child assertions passed."
trap - ERR
rm -rf "$SCRATCH_ROOT"
