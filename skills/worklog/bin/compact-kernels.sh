#!/usr/bin/env bash
# Dump a compact resume kernel for every active task into
# .cache/compact-kernels.{md,json}. Safe to call anytime — idempotent, no-op
# if there are no active tasks. Wired to PreCompact + SessionEnd hooks
# so a post-compact / next-session Claude can read one small file
# instead of re-reading every active task.
#
# .cache/ is gitignored by design (rag-format.md: machine-local caches).
#
# Single Python pass produces both .md (human-friendly) and .json
# (TaskCreate-hydration shape) — earlier per-slug bin/context.sh shell-out
# loop was 50ms × 55 tasks ≈ 2.86s; single-pass is ~300ms.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

LDAP="$(resolve_ldap)"

ACTIVE_DIR="people/$LDAP/active"
OUT_DIR=".cache"
OUT_MD="$OUT_DIR/compact-kernels.md"
OUT_JSON="$OUT_DIR/compact-kernels.json"

mkdir -p "$OUT_DIR"
OUT_MD_TMP="$(mktemp "$OUT_DIR/compact-kernels.md.tmp.XXXXXX")"
OUT_JSON_TMP="$(mktemp "$OUT_DIR/compact-kernels.json.tmp.XXXXXX")"
trap 'rm -f "$OUT_MD_TMP" "$OUT_JSON_TMP"' EXIT

# Empty-active short-circuit (matches existing behavior expected by tests).
if ! ls "$ACTIVE_DIR"/*.md >/dev/null 2>&1; then
  {
    NOW_EPOCH="$(date -u +%s)"
    STALE_EPOCH=$((NOW_EPOCH + 3600))
    printf '# Compact kernels — generated %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# Stale after: %s (readers should skip if current time exceeds this)\n' \
      "$(date -u -r "$STALE_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$STALE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
    printf '\nOne resume kernel per active task. Read this first after /compact\n'
    printf 'or on a new session; only open the full task file if you need more.\n\n'
    printf '_(no active tasks)_\n'
  } > "$OUT_MD_TMP"
  echo "[]" > "$OUT_JSON_TMP"
  mv -f "$OUT_MD_TMP" "$OUT_MD"
  mv -f "$OUT_JSON_TMP" "$OUT_JSON"
  trap - EXIT
  echo "compact-kernels: wrote $OUT_MD (no active tasks)"
  exit 0
fi

python3 - "$ACTIVE_DIR" "$OUT_MD_TMP" "$OUT_JSON_TMP" "$SCRIPT_DIR" <<'PY'
import json, pathlib, sys, subprocess, datetime
sys.path.insert(0, sys.argv[4])
from _task_context import parse_task_file, make_kernel, kernel_markdown

active_dir = pathlib.Path(sys.argv[1])
out_md = pathlib.Path(sys.argv[2])
out_json = pathlib.Path(sys.argv[3])

now = datetime.datetime.now(datetime.timezone.utc)
stale = now + datetime.timedelta(hours=1)

# One git log batch covers all files. Per-file `git log -1` previously forked
# ~100× = 8s system time; this single invocation streams every commit touching
# active_dir and we keep the first (most recent) sha+subject per file.
files = sorted(active_dir.glob("*.md"))
last_sha_by_path = {}
try:
  proc = subprocess.run(
    ["git", "log", "--name-only", "--format=COMMIT\t%h\t%s", "--", str(active_dir)],
    capture_output=True, text=True, check=False,
  )
  cur_sha = cur_subject = ""
  for line in proc.stdout.split("\n"):
    if line.startswith("COMMIT\t"):
      _, sha, subject = line.split("\t", 2)
      cur_sha, cur_subject = sha, subject
    elif line and cur_sha:
      key = str(pathlib.Path(line).resolve())
      if key not in last_sha_by_path:
        last_sha_by_path[key] = (cur_sha, cur_subject)
except Exception:
  pass
# Normalize file keys to the resolved paths so the lookup matches below.
files_resolved = {str(f.resolve()): f for f in files}

records = []
md_sections = []

for f in files:
  text = f.read_text()
  fm, body = parse_task_file(text)
  if not fm:
    continue
  last_sha, last_subject = last_sha_by_path.get(str(f.resolve()), ("", ""))
  kernel = make_kernel(f.stem, fm, body, text, f, last_sha, last_subject, now, "file")
  records.append(kernel)
  md_sections.append(f"### {kernel['slug']}\n\n" + kernel_markdown(kernel))

# Emit md.
with out_md.open("w") as fh:
  fh.write(f"# Compact kernels — generated {now.strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
  fh.write(f"# Stale after: {stale.strftime('%Y-%m-%dT%H:%M:%SZ')} (readers should skip if current time exceeds this)\n\n")
  fh.write("One resume kernel per active task. Read this first after /compact\n")
  fh.write("or on a new session; only open the full task file if you need more.\n\n")
  for sec in md_sections:
    fh.write(sec + "\n\n")

# Emit json.
out_json.write_text(json.dumps(records, indent=2) + "\n")

PY

mv -f "$OUT_MD_TMP" "$OUT_MD"
mv -f "$OUT_JSON_TMP" "$OUT_JSON"
trap - EXIT

# Mirror old log format for any caller that grepped it.
echo "compact-kernels: wrote $OUT_MD ($(wc -l <"$OUT_MD" | tr -d ' ') lines)"
echo "compact-kernels: wrote $OUT_JSON"
