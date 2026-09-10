#!/usr/bin/env bash
# checkpoint-batch.sh — atomic multi-task frontmatter update in a single commit.
#
# Reads JSON array from stdin: [{"slug": "...", "next": "...", "status": "...", "pr": N}, ...]
# Required per record: slug. Optional: status, next, pr.
#
# For each record:
#   1. Validate slug resolves to the caller's people/<LDAP>/active/<slug>.md
#   2. Rewrite frontmatter (last_updated → today; status/next/pr per record)
#   3. Stage the file
#
# After all records processed:
#   - One commit with subject `worklog-batch: N tasks updated`
#   - Body lists each slug + change summary
#   - Worklog-Slug: trailer per touched slug + Worklog-Status: per status flip
#   - One push
#
# Usage:
#   echo '[{"slug": "a", "status": "in-review"}, {"slug": "b"}]' | bin/checkpoint-batch.sh
#
# Why a separate script: bin/checkpoint.sh single-slug path is already complex;
# Unix philosophy (AGENTS.md § Helpers) prefers a sibling script for the batch shape.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

verify_provenance || exit 1
LDAP="$(resolve_ldap)"

# Read entire stdin as JSON array.
INPUT="$(cat)"
[[ -z "$INPUT" ]] && { echo "checkpoint-batch: no JSON on stdin" >&2; exit 2; }

# Validate JSON + drive frontmatter rewrites via Python.
# Output: TSV per record — slug, action_summary, status_flipped (true/false), task_file
PLAN="$(BATCH_LDAP="$LDAP" python3 - "$INPUT" <<'PY'
import json, sys, re, pathlib, datetime, os, subprocess
records = json.loads(sys.argv[1])
if not isinstance(records, list):
    print("checkpoint-batch: input must be a JSON array", file=sys.stderr)
    sys.exit(2)
today = datetime.date.today().isoformat()
STATUSES = {"draft", "in-progress", "in-review", "blocked", "shipping"}

ldap = os.environ["BATCH_LDAP"]
if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", ldap):
    sys.exit("checkpoint-batch: invalid namespace")
namespace = pathlib.Path("people") / ldap / "active"
if any(p.is_symlink() for p in (namespace, namespace.parent, namespace.parent.parent)):
    sys.exit("checkpoint-batch: symlinked namespace refused")

def find_task(slug):
    p = namespace / f"{slug}.md"
    if p.is_file() and not p.is_symlink() and p.resolve().parent == namespace.resolve():
        return p
    return None

def yaml_double_quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def sub(text, field, value, quote=False):
    if quote:
        value = yaml_double_quote(value)
    # Match field line PLUS any indented continuation (multi-line YAML
    # scalars). Without this, replacing a multi-line `next_action:` only
    # rewrites line 1 and leaves continuation orphans → YAML parse error.
    # Mirror of fix in bin/archive.sh + bin/checkpoint.sh. See lessons.md
    # 2026-05 §3 for the multi-line scalar lesson.
    pattern = re.compile(rf'^{field}:.*(?:\n[ \t]+.*)*$', re.MULTILINE)
    if pattern.search(text):
        return pattern.sub(lambda _m: f'{field}: {value}', text, count=1)
    return re.sub(r'^(---\n.*?)(\n---)', lambda m: f'{m.group(1)}\n{field}: {value}{m.group(2)}', text, count=1, flags=re.DOTALL)

def pr_values(value):
    if value is None or value == "":
        return []
    if isinstance(value, list):
        raw = value
    else:
        raw = [value]
    vals = []
    for item in raw:
        vals.extend(re.findall(r'\d+', str(item)))
    return vals

def merge_prs(text, requested):
    requested_vals = pr_values(requested)
    if not requested_vals:
        return text, []
    existing_vals = []
    m = re.search(r'^pr:\s*(.+)$', text, re.MULTILINE)
    if m:
        existing_vals = re.findall(r'\d+', m.group(1))
    merged = []
    for val in existing_vals + requested_vals:
        if val not in merged:
            merged.append(val)
    return sub(text, "pr", "[" + ", ".join(merged) + "]"), requested_vals

errors = []
plan = []
seen = set()
for rec in records:
    if not isinstance(rec, dict):
        errors.append("record must be an object")
        continue
    slug = rec.get("slug")
    if not isinstance(slug, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug):
        errors.append("record requires a valid task slug")
        continue
    if slug in seen:
        errors.append(f"duplicate slug '{slug}'")
        continue
    seen.add(slug)
    p = find_task(slug)
    if p is None:
        errors.append(f"no active task file for slug '{slug}'")
        continue
    if any(key in rec and not isinstance(rec[key], str) for key in ("status", "next")):
        errors.append(f"{slug}: status and next must be strings when supplied")
        continue
    pr = rec.get("pr")
    if pr is not None and any(isinstance(v, bool) or not isinstance(v, (str, int))
                              for v in (pr if isinstance(pr, list) else [pr])):
        errors.append(f"{slug}: pr must be a number, string or list of these")
        continue
    requested_status = rec.get("status")
    if requested_status:
        if requested_status == "archived":
            errors.append(f"{slug}: status=archived is not supported by checkpoint-batch; use archive.sh")
            continue
        if requested_status not in STATUSES:
            errors.append(f"{slug}: status '{requested_status}' not in FSM: {sorted(STATUSES | {'archived'})}")
            continue
    text = p.read_text()
    text = sub(text, "last_updated", today)
    flipped = False
    summary_parts = []
    if requested_status:
        # Read current status to detect flip.
        m = re.search(r'^status:\s*(\S+)', text, re.MULTILINE)
        old = m.group(1) if m else ""
        text = sub(text, "status", requested_status)
        if old and old != requested_status:
            flipped = True
            summary_parts.append(f"status: {old}→{requested_status}")
        else:
            summary_parts.append(f"status: {requested_status}")
    if rec.get("next"):
        text = sub(text, "next_action", rec["next"], quote=True)
        summary_parts.append("next updated")
    if "pr" in rec:
        text, added_prs = merge_prs(text, rec.get("pr"))
        if added_prs:
            summary_parts.append(f"pr={','.join(added_prs)}")
    if not summary_parts:
        summary_parts.append("last_updated bump")
    plan.append((slug, ", ".join(summary_parts), "true" if flipped else "false", str(p), requested_status or "", text))

allowed = {row[3] for row in plan}
staged = subprocess.run(["git", "diff", "--cached", "--name-only", "-z"],
                        capture_output=True, check=True).stdout
unexpected = [os.fsdecode(p) for p in staged.split(b"\0") if p and os.fsdecode(p) not in allowed]
if unexpected:
    errors.append("unexpected staged paths outside batch scope: " + ", ".join(unexpected))

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(2)

for slug, summary, flipped, file, status, text in plan:
    pathlib.Path(file).write_text(text)
    print(f"{slug}\t{summary}\t{flipped}\t{file}\t{status}")
PY
)"

[[ -z "$PLAN" ]] && { echo "checkpoint-batch: no records to process" >&2; exit 2; }

# Pull, then stage each touched file.
git pull --no-rebase --autostash -q
COUNT=0
SUBJECT_LINES=()
TRAILER_LINES=()
SLUGS=()
FILES=()
while IFS=$'\t' read -r slug summary flipped file status; do
  [[ -z "$slug" ]] && continue
  git add "$file"
  COUNT=$((COUNT + 1))
  SUBJECT_LINES+=("- $slug — $summary")
  TRAILER_LINES+=("Worklog-Slug: $slug")
  if [[ "$flipped" == "true" && -n "$status" ]]; then
    TRAILER_LINES+=("Worklog-Status: $status")
  fi
  SLUGS+=("$slug")
  FILES+=("$file")
done <<< "$PLAN"

if git diff --cached --quiet; then
  echo "checkpoint-batch: no changes after frontmatter rewrites (idempotent — all dates already today)"
  exit 0
fi

# Detect collisions across all slugs (advisory).
for s in "${SLUGS[@]}"; do
  detect_session_collision "$s" 2>&1 || true
done

SUBJECT="worklog-batch: $COUNT tasks updated"
BODY=$(printf '%s\n' "${SUBJECT_LINES[@]}")
TRAILERS=$(printf '%s\n' "${TRAILER_LINES[@]}")

# Recheck after pull/staging; --only also keeps a late index write out of this commit.
python3 - "${FILES[@]}" <<'PY_CHECK'
import os, subprocess, sys
staged = subprocess.check_output(["git", "diff", "--cached", "--name-only", "-z"])
unexpected = [os.fsdecode(p) for p in staged.split(b"\0") if p and os.fsdecode(p) not in sys.argv[1:]]
if unexpected:
    sys.exit("checkpoint-batch: unexpected staged paths before commit: " + ", ".join(unexpected))
PY_CHECK
git commit --only -q -m "$SUBJECT" -m "$BODY" -m "$TRAILERS" -- "${FILES[@]}"
push_with_retry || exit 1
for s in "${SLUGS[@]}"; do
  record_session_touch "$s" "checkpoint-batch"
done
echo "checkpoint-batch: pushed $COUNT tasks"
