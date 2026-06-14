#!/usr/bin/env bash
# Smoke-test OKF migration on a tiny git-backed worklog corpus.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"
SCRATCH="$(mktemp -d -t worklog-okf-test-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

mkdir -p "$SCRATCH/people/alice/active" "$SCRATCH/people/alice/archive" "$SCRATCH/projects" "$SCRATCH/docs"
git -C "$SCRATCH" init -q
git -C "$SCRATCH" config user.name "Test User"
git -C "$SCRATCH" config user.email "test@example.com"

cat >"$SCRATCH/people/alice/active/task-alpha.md" <<'EOF'
---
slug: task-alpha
kind: impl
status: in-progress
project: mini-apps
last_updated: 2026-05-10
next_action: Continue wiring the alpha flow
repos:
  - example/repo
---

## Context

Mentions task-beta as body context.

## Next

Continue.
EOF

cat >"$SCRATCH/people/alice/archive/task-beta.md" <<'EOF'
---
slug: task-beta
kind: debug
status: archived
project: mini-apps
last_updated: 2026-05-01
next_action: —
---

## Context

Archived 2026-05-01: shipped.
EOF

cat >"$SCRATCH/projects/mini-apps.md" <<'EOF'
# Mini Apps

Generated project view.
EOF

cat >"$SCRATCH/docs/protocol.md" <<'EOF'
# Protocol

Human-authored protocol notes.
EOF

git -C "$SCRATCH" add .
git -C "$SCRATCH" commit -q -m "fixture"
git -C "$SCRATCH" config core.hooksPath "$WORKLOG_BIN/git-hooks"

python3 "$WORKLOG_BIN/okf.py" migrate --repo "$SCRATCH" --apply >/tmp/worklog-okf-migrate.json
python3 "$WORKLOG_BIN/okf.py" migrate --repo "$SCRATCH" --check >/tmp/worklog-okf-check.json

python3 - "$SCRATCH" "$WORKLOG_BIN" <<'PY'
import json
import pathlib
import re
import subprocess
import sys
import yaml

root = pathlib.Path(sys.argv[1])
bin_dir = pathlib.Path(sys.argv[2])
check = json.loads(pathlib.Path("/tmp/worklog-okf-check.json").read_text())
assert check["changed"] == 0, check

task_text = (root / "people/alice/active/task-alpha.md").read_text()
fm = yaml.safe_load(re.match(r"^---\n(.*?)\n---\n", task_text, re.S).group(1))
assert fm["kind"] == "impl"
assert fm["type"] == "impl"
assert fm["worklog_id"] == "worklog-okf-test-XXXXXX/alice/task-alpha" or fm["worklog_id"].endswith("/alice/task-alpha")
assert str(fm["timestamp"]).startswith("2026-05-10")
assert str(fm["last_updated"]) == "2026-05-10"

project_fm = yaml.safe_load(re.match(r"^---\n(.*?)\n---\n", (root / "projects/mini-apps.md").read_text(), re.S).group(1))
assert project_fm["type"] == "project-view"
assert project_fm["worklog_entity"] == "project-view"
assert project_fm["worklog_authoritative"] is False
assert project_fm["worklog_id"].endswith("/projects/mini-apps")

doc_fm = yaml.safe_load(re.match(r"^---\n(.*?)\n---\n", (root / "docs/protocol.md").read_text(), re.S).group(1))
assert doc_fm["type"] == "protocol-doc"
assert doc_fm["worklog_authoritative"] is True

lint = subprocess.run(
  ["python3", str(bin_dir / "_lint.py"), "--okf", "--format=json"],
  cwd=root,
  text=True,
  stdout=subprocess.PIPE,
  stderr=subprocess.PIPE,
  check=False,
)
if lint.returncode != 0:
  print(lint.stdout)
  print(lint.stderr, file=sys.stderr)
  raise SystemExit(lint.returncode)
report = json.loads(lint.stdout)
assert report["total_errors"] == 0, report
PY

WORKLOG_REPO="$SCRATCH" "$WORKLOG_BIN/auto-slug-link.py" --apply --file=people/alice/active/task-alpha.md >/tmp/worklog-auto-slug-link.txt
grep -q '\[\[task-beta\]\]' "$SCRATCH/people/alice/active/task-alpha.md"

echo "okf: migration and repo-root auto-link tests passed"
