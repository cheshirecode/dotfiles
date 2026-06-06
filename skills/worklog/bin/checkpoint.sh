#!/usr/bin/env bash
# Update a task's frontmatter (last_updated, optional status/next_action) and push.
# Emits Worklog-* trailers per AGENTS.md "Commit message convention".
#
# Usage:
#   bin/checkpoint.sh <slug>
#   bin/checkpoint.sh <slug> --status=in-review
#   bin/checkpoint.sh <slug> --status=blocked --next="Waiting on ENG-1514"
#   bin/checkpoint.sh <slug> --pr=11262
#   bin/checkpoint.sh <new-slug> --rename=<old-slug>
#   bin/checkpoint.sh <slug> --include=README.md --include=bin/foo.sh

set -euo pipefail

SLUG=""
STATUS=""
NEXT=""
PR=""
RENAME_FROM=""
INCLUDES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status=*)  STATUS="${1#--status=}" ;;
    --next=*)    NEXT="${1#--next=}" ;;
    --pr=*)      PR="${1#--pr=}" ;;
    --rename=*)  RENAME_FROM="${1#--rename=}" ;;
    --include=*) INCLUDES+=("${1#--include=}") ;;
    --status)    STATUS="$2"; shift ;;
    --next)      NEXT="$2"; shift ;;
    --pr)        PR="$2"; shift ;;
    --rename)    RENAME_FROM="$2"; shift ;;
    --include)   INCLUDES+=("$2"); shift ;;
    -h|--help)
      cat <<EOF
usage: checkpoint.sh <slug> [--status=X] [--next="..."] [--pr=N]
                            [--rename=OLD_SLUG] [--include=PATH ...]
  --status    flip frontmatter status (emits Worklog-Status trailer)
  --next      rewrite next_action
  --pr        attach a PR number to this commit (emits Worklog-PR trailer)
  --rename    this commit renames OLD_SLUG to <slug> (emits Worklog-Previous-Slug trailer)
  --include   stage an additional path alongside the task file (repeatable).
              Use when work for this slug touches sibling files (README,
              AGENTS.md, bin/, etc.) and the task file alone wouldn't cover them.
EOF
      exit 0
      ;;
    *) SLUG="$1" ;;
  esac
  shift
done

if [[ -z "$SLUG" ]]; then
  echo "checkpoint: slug required" >&2
  exit 2
fi

# --status=archived is the wrong tool: it flips frontmatter but doesn't move
# the file, clear next_action, run the orphan-check, or emit the retro prompt.
# Hard-fail with the canonical archive command (user picks the reason).
if [[ "$STATUS" == "archived" ]]; then
  cat >&2 <<EOF
checkpoint: --status=archived is the wrong tool. Use:
  bin/archive.sh $SLUG --reason=<shipped|superseded|abandoned|merged|obsolete>

bin/archive.sh moves active/ → archive/, clears next_action, runs the
orphan-check, prepends the Archived line to ## Context, and emits the
retro prompt. checkpoint.sh would only flip frontmatter and leave a
zombie file in active/.
EOF
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
LDAP="$(resolve_ldap)"
verify_provenance || exit 1
detect_session_collision "$SLUG" 2>&1 || true

FILE="people/$LDAP/active/$SLUG.md"
if [[ ! -f "$FILE" ]]; then
  echo "checkpoint: $FILE not found" >&2
  exit 1
fi

# Snapshot HEAD state so we can detect transitions / creates.
OLD_STATUS=""
IS_NEW_FILE=0
if ! git cat-file -e "HEAD:$FILE" 2>/dev/null; then
  IS_NEW_FILE=1
else
  OLD_STATUS="$(git show "HEAD:$FILE" 2>/dev/null | awk -F': *' '/^status:/ {print $2; exit}' || true)"
fi

TODAY="$(date +%Y-%m-%d)"

python3 - "$FILE" "$TODAY" "$STATUS" "$NEXT" <<'PY'
import sys, re, pathlib
path, today, status, next_action = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(path)
text = p.read_text()
def yaml_double_quote(s):
    # Wrap a prose string for safe inline YAML — escape backslash and double-quote.
    # Used for free-text fields (next_action) that can contain `:` or other
    # YAML-special characters and would otherwise re-trigger the B2 / B5 parse
    # error class. Constrained fields (status, last_updated) don't need this.
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
def sub(field, value, quote=False):
    global text
    if quote:
        value = yaml_double_quote(value)
    # Match field line PLUS any indented continuation (multi-line YAML scalars).
    # Without this, replacing a multi-line `next_action:` only rewrites line 1
    # and leaves continuation orphans → YAML parse error. See lessons.md
    # 2026-05 §1 (matching fix in bin/archive.sh).
    pattern = re.compile(rf'^{field}:.*(?:\n[ \t]+.*)*$', re.MULTILINE)
    if pattern.search(text):
        text = pattern.sub(lambda _m: f'{field}: {value}', text, count=1)
    else:
        text = re.sub(r'^(---\n.*?)(\n---)', lambda m: f'{m.group(1)}\n{field}: {value}{m.group(2)}', text, count=1, flags=re.DOTALL)
sub('last_updated', today)
if status:
    sub('status', status)
if next_action:
    sub('next_action', next_action, quote=True)
p.write_text(text)
PY

# Heartbeat tick: if the task has a `claim:` block held by the current
# session, refresh `claim.heartbeat_at` so the work commit advances the
# liveness signal (per worklog-project-mode.md § Mutex protocol). No-op
# otherwise. Errors are swallowed — heartbeat is best-effort.
if [[ -x bin/_claim.py ]]; then
  SID_FOR_TICK="$(. bin/_lib.sh; resolve_session_id 2>/dev/null || true)"
  if [[ -n "$SID_FOR_TICK" ]]; then
    python3 bin/_claim.py tick "$FILE" --session="$SID_FOR_TICK" 2>/dev/null || true
  fi
fi

# Auto-link bare body slugs to [[wikilinks]] for Obsidian graph/backlinks.
# Body-only; frontmatter is byte-for-byte preserved (bare slugs there are
# load-bearing per AGENTS.md "Slug as join key"). Idempotent. Bypass with
# WORKLOG_NO_AUTOLINK=1.
if [[ -z "${WORKLOG_NO_AUTOLINK:-}" ]] && [[ -x bin/auto-slug-link.py ]]; then
  bin/auto-slug-link.py --apply --file="$FILE" >/dev/null 2>&1 || true
fi

# Soft lint gate — single-file scope. Stderr-only, never blocks the checkpoint.
# Bypass with WORKLOG_NO_LINT=1 (e.g. in hooks / non-interactive contexts).
if [[ -z "${WORKLOG_NO_LINT:-}" ]] && [[ -x bin/lint.sh ]]; then
  bin/lint.sh --file="$FILE" --format=json 2>/dev/null | python3 - >&2 <<'PY' || true
import json, sys
try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(0)
for item in data.get("issues", []):
  for e in item.get("errors", []):
    print(f"checkpoint: lint ERROR  {e}", file=sys.stderr)
  for w in item.get("warnings", []):
    print(f"checkpoint: lint warn   {w}", file=sys.stderr)
PY
fi

git pull --no-rebase --autostash -q
git add "$FILE"

for inc in ${INCLUDES[@]+"${INCLUDES[@]}"}; do
  if [[ ! -e "$inc" ]]; then
    echo "checkpoint: --include path not found: $inc" >&2
    exit 1
  fi
  git add "$inc"
done

if [[ -n "$RENAME_FROM" ]]; then
  OLD_FILE="people/$LDAP/active/$RENAME_FROM.md"
  [[ -f "$OLD_FILE" ]] || OLD_FILE="people/$LDAP/archive/$RENAME_FROM.md"
  if [[ -f "$OLD_FILE" ]]; then
    git rm -q "$OLD_FILE" 2>/dev/null || true
  fi
fi

if git diff --cached --quiet; then
  echo "checkpoint: no changes for $SLUG"
  exit 0
fi

# Staged-scope guard: refuse if any staged path is not the task file, not in
# --include, and not the rename source. Keeps commit subjects ("<slug>:
# checkpoint" / "status → X") honest by keeping their content scoped to the
# named slug. Bypass with WORKLOG_CHECKPOINT_FORCE=1 for intentional
# multi-purpose commits (rare — prefer separate commits or --include).
if [[ "${WORKLOG_CHECKPOINT_FORCE:-0}" != "1" ]]; then
  ALLOWED=("$FILE")
  ALLOWED+=( ${INCLUDES[@]+"${INCLUDES[@]}"} )
  if [[ -n "$RENAME_FROM" ]]; then
    ALLOWED+=("people/$LDAP/active/$RENAME_FROM.md" "people/$LDAP/archive/$RENAME_FROM.md")
  fi
  UNEXPECTED=()
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    found=0
    for allowed in "${ALLOWED[@]}"; do
      [[ "$path" == "$allowed" ]] && { found=1; break; }
    done
    (( found )) || UNEXPECTED+=("$path")
  done < <(git diff --cached --name-only)
  if (( ${#UNEXPECTED[@]} > 0 )); then
    {
      echo "checkpoint: unexpected staged paths outside $SLUG's scope:"
      printf '  %s\n' "${UNEXPECTED[@]}"
      echo ""
      echo "These would be bundled into a '$SLUG: …' commit, making the audit trail misleading."
      echo "Pick one:"
      echo "  - Re-run with --include= for each path that belongs with this slug:"
      for u in "${UNEXPECTED[@]}"; do
        echo "      bin/checkpoint.sh $SLUG --include=$u ..."
      done
      echo "  - git restore --staged <path>   # if those changes belong to a different commit"
      echo "  - WORKLOG_CHECKPOINT_FORCE=1 bin/checkpoint.sh $SLUG ...   # one-shot bypass"
    } >&2
    exit 1
  fi
fi

# noop-detect: when the only staged change is the last_updated bump on $FILE
# (no rename, not a new file, no --include sibling files), skip the commit.
# AGENTS.md says last_updated is not ordering-authoritative, so a bump-only
# checkpoint adds noise to git log without information.
if [[ $IS_NEW_FILE -eq 0 && -z "$RENAME_FROM" && ${#INCLUDES[@]} -eq 0 ]]; then
  STAGED_FILES="$(git diff --cached --name-only)"
  if [[ "$STAGED_FILES" == "$FILE" ]]; then
    # Strip diff file headers (+++/---) first, then keep added/removed lines,
    # then drop last_updated bumps. Earlier `^[+-][^+-]` mis-filtered any
    # markdown bullet addition (e.g. `+- [ ] ...`) as a non-semantic header.
    SEMANTIC_DIFF="$(git diff --cached -U0 -- "$FILE" | grep -vE '^(\+\+\+|---) ' | grep -E '^[+-]' | grep -vE '^[+-]last_updated:' || true)"
    if [[ -z "$SEMANTIC_DIFF" ]]; then
      echo "checkpoint: no semantic changes for $SLUG (only last_updated bump — skipping)"
      git reset -q HEAD -- "$FILE"
      git checkout -q -- "$FILE"
      exit 0
    fi
  fi
fi

# next_action commonly contains UTF-8 (→, em-dash). macOS's system awk has broken
# multibyte support regardless of locale and aborts on those bytes
# ("towc: multibyte conversion failure"), silently dropping the commit. Run awk in
# byte mode (LC_ALL=C: MB_CUR_MAX=1, no wide-char conversion) so the bytes pass
# through untouched; the only char-aware step (subject truncation) uses python3.
NEW_STATUS="$(LC_ALL=C awk -F': *' '/^status:/ {print $2; exit}' "$FILE" || true)"
NEW_NEXT="$(LC_ALL=C awk -F': *' '/^next_action:/ {sub(/^next_action: */,""); print; exit}' "$FILE" || true)"
# PR list from frontmatter: `pr: [11246, 11262]` or `pr: 11246` → "11246,11262".
FM_PRS="$(python3 - "$FILE" <<'PY' 2>/dev/null || true
import sys, re, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'^pr:\s*(.+)$', t, re.MULTILINE)
if not m: sys.exit(0)
v = m.group(1).strip()
if v.startswith('['):
    nums = re.findall(r'\d+', v)
else:
    nums = [v] if v else []
print(",".join(n for n in nums if n))
PY
)"

SUBJECT="$SLUG: checkpoint"
if [[ -n "$RENAME_FROM" ]]; then
  SUBJECT="$SLUG: rename (was $RENAME_FROM)"
elif [[ $IS_NEW_FILE -eq 1 ]]; then
  SUBJECT="$SLUG: create"
elif [[ -n "$STATUS" && "$STATUS" != "$OLD_STATUS" ]]; then
  SUBJECT="$SLUG: status → $STATUS"
elif [[ -n "$NEW_NEXT" && "$NEW_NEXT" != "—" ]]; then
  # Derive a meaningful subject suffix from the next-action prose so future
  # `git log --oneline` is browseable. Truncate at the last word boundary
  # before 60 chars of suffix (per worklog-log-compaction-squash § Improvement 1).
  # Fallback to `: checkpoint` only when next-action is missing/empty.
  SUFFIX="$(printf '%s' "$NEW_NEXT" | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  # Char-count (not byte-count) gate so multibyte next_actions aren't truncated early.
  if [[ "$(printf '%s' "$SUFFIX" | PYTHONUTF8=1 python3 -c 'import sys;print(len(sys.stdin.buffer.read().decode("utf-8","replace")))')" -gt 60 ]]; then
    # Truncate at last word boundary ≤60 chars; trim trailing whitespace/punct.
    # python3 (UTF-8 forced) does this char-correctly — macOS awk can't handle
    # the multibyte content reliably.
    SUFFIX="$(printf '%s' "$SUFFIX" | PYTHONUTF8=1 python3 -c '
import sys
s = sys.stdin.buffer.read().decode("utf-8", "replace")[:60]
j = s.rfind(" ")
if j > 0:
    s = s[:j]
sys.stdout.write(s.rstrip(" \t\r\n-–—:;,.!?/|·"))
')"
    SUFFIX="${SUFFIX}…"
  fi
  [[ -n "$SUFFIX" ]] && SUBJECT="$SLUG: $SUFFIX"
fi

# Body: the current next_action. Gives `git log --format=%b` consumers a
# one-liner about what's next for this slug without reading the task file.
BODY=""
if [[ -n "$NEW_NEXT" && "$NEW_NEXT" != "—" ]]; then
  BODY="next: $NEW_NEXT"
fi

TRAILERS=""
append_trailer() { TRAILERS="${TRAILERS}${TRAILERS:+
}$1: $2"; }

PROJECT="$(awk -F': *' '/^project:/ {print $2; exit}' "$FILE" || true)"
if [[ $IS_NEW_FILE -eq 1 ]]; then
  KIND="$(awk -F': *' '/^kind:/ {print $2; exit}' "$FILE" || true)"
  LINEAR="$(awk -F': *' '/^linear:/ {print $2; exit}' "$FILE" || true)"
  append_trailer "Worklog-Status" "${NEW_STATUS:-draft}"
  append_trailer "Worklog-Kind" "${KIND:-}"
  append_trailer "Worklog-Linear" "${LINEAR:-}"
  [[ -n "$PROJECT" ]] && append_trailer "Worklog-Project" "$PROJECT"
elif [[ -n "$STATUS" ]]; then
  # User explicitly asserted status via --status=. Emit the trailer
  # unconditionally so the audit log records the assertion — even if
  # frontmatter status was already at the asserted value. This is what
  # clears a trailer-vs-frontmatter divergence warning from bin/lint.sh
  # without needing to bounce status through draft to force a trailer.
  # If the file has no semantic diff at all, the noop-detect guard
  # above already short-circuits — so this only fires when a real
  # commit is happening.
  append_trailer "Worklog-Status" "$STATUS"
  [[ -n "$PROJECT" ]] && append_trailer "Worklog-Project" "$PROJECT"
fi

# PR trailer: explicit --pr wins; else auto-emit from frontmatter `pr:` field.
PR_EMIT="${PR:-$FM_PRS}"
[[ -n "$PR_EMIT" ]] && append_trailer "Worklog-PR" "$PR_EMIT"
[[ -n "$RENAME_FROM" ]] && append_trailer "Worklog-Previous-Slug" "$RENAME_FROM"

COMMIT_ARGS=(-q -m "$SUBJECT")
[[ -n "$BODY" ]] && COMMIT_ARGS+=(-m "$BODY")
[[ -n "$TRAILERS" ]] && COMMIT_ARGS+=(-m "$TRAILERS")
git commit "${COMMIT_ARGS[@]}"
push_with_retry || exit 1
record_session_touch "$SLUG" "checkpoint"
echo "checkpoint: pushed $SLUG"

# Transcript dump on meaningful status flips only. Silent skip otherwise.
# Doesn't touch task body — only appends to people/$LDAP/transcripts/<slug>.md.
if [[ "$STATUS" == "in-review" || "$STATUS" == "shipping" ]]; then
  SLUG="$SLUG" LDAP="$LDAP" TRIGGER="status:$STATUS" \
    python3 "$(dirname "$0")/_dump_transcript.py" 2>/dev/null || true
fi
