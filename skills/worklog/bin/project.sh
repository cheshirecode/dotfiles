#!/usr/bin/env bash
# project.sh — multi-task workstream coordination.
#
# Subcommands:
#   new <slug>                Create a project task file + child task stubs.
#                             Reads optional tasks-JSON from stdin or --tasks-json=.
#                             Required: --goal, --objective. Optional:
#                             --stale-after=30m, --dry-run.
#   next <slug>               Print the first declaration-order claim-eligible
#                             child task slug. Exit 0 with slug; exit 1 if none.
#   claim <child-slug>        Phase 2: claim a child task (writes claim: block).
#                             --dry-run prints decision without writing.
#   claim next <project>      Phase 2: claim the next eligible child task.
#   release <child-slug>      Phase 2: clear a claim you own.
#   reap [--session=ID] [--stale=DUR]
#                             Phase 2: clear claims whose heartbeat is stale.
#   verify <slug> | --all     Phase 3: dep cycles / parent_slug consistency.
#   list                      Phase 3: projects + child task rollup.
#
# See people/cheshirecode/active/worklog-project-mode.md for design.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ $# -eq 0 ]]; then
  usage; exit 2
fi

SUB="$1"; shift || true

case "$SUB" in
  -h|--help|help) usage; exit 0 ;;
esac

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

# ---------- helpers ----------

# find_task <slug> → echo the path under people/*/active|archive or empty.
find_task() {
  local slug="$1"
  local p
  for p in people/*/active/"$slug".md people/*/archive/"$slug".md; do
    [[ -f "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

# project_file <slug> → path to a project task; must be kind: project.
project_file() {
  local slug="$1" p
  p="$(find_task "$slug" || true)"
  [[ -z "$p" ]] && { echo "project: no task file for '$slug'" >&2; return 1; }
  local k
  k="$(awk -F': *' '/^kind:/ {print $2; exit}' "$p" || true)"
  [[ "$k" == "project" ]] || { echo "project: '$slug' is kind:$k not kind:project" >&2; return 1; }
  echo "$p"
}

# ---------- sub: new ----------

cmd_new() {
  local SLUG="" GOAL="" OBJECTIVE="" STALE_AFTER="30m" TASKS_JSON="" REPOS="" DRY=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --goal=*)         GOAL="${1#--goal=}" ;;
      --objective=*)    OBJECTIVE="${1#--objective=}" ;;
      --stale-after=*)  STALE_AFTER="${1#--stale-after=}" ;;
      --tasks-json=*)   TASKS_JSON="${1#--tasks-json=}" ;;
      --repos=*)        REPOS="${1#--repos=}" ;;
      --dry-run)        DRY=1 ;;
      --goal)           GOAL="$2"; shift ;;
      --objective)      OBJECTIVE="$2"; shift ;;
      --stale-after)    STALE_AFTER="$2"; shift ;;
      --tasks-json)     TASKS_JSON="$2"; shift ;;
      --repos)          REPOS="$2"; shift ;;
      -h|--help)
        cat <<EOF
usage: project.sh new <slug> --goal "..." --objective "..." [--stale-after=30m] [--repos=cheshirecode/<repo>,cheshirecode/<repo>] [--dry-run]
       echo '[{"slug":"a"},{"slug":"b","depends_on":["a"]}]' | project.sh new <slug> ...
       project.sh new <slug> --tasks-json='[{"slug":"a"}]' ...
EOF
        return 0 ;;
      *) SLUG="$1" ;;
    esac
    shift
  done
  [[ -z "$SLUG" ]] && { echo "project new: slug required" >&2; return 2; }
  [[ -z "$GOAL" ]] && { echo "project new: --goal required" >&2; return 2; }
  [[ -z "$OBJECTIVE" ]] && { echo "project new: --objective required" >&2; return 2; }

  # Tasks JSON: --tasks-json wins; else stdin (if non-tty).
  if [[ -z "$TASKS_JSON" ]]; then
    if [[ ! -t 0 ]]; then
      TASKS_JSON="$(cat)"
    fi
  fi
  [[ -z "$TASKS_JSON" ]] && { echo "project new: tasks JSON required (--tasks-json= or stdin)" >&2; return 2; }

  local LDAP TODAY
  LDAP="$(resolve_ldap)"
  TODAY="$(date +%Y-%m-%d)"

  # Validate JSON + emit plan: project YAML on stdout fd 3, then for each child
  # a "STUB<TAB>slug<TAB>kind<TAB>YAML-as-base64" line on fd 4. Easier: do
  # everything in Python and emit a single JSON plan we then materialize in shell.
  local PLAN
  PLAN="$(SLUG="$SLUG" GOAL="$GOAL" OBJECTIVE="$OBJECTIVE" STALE_AFTER="$STALE_AFTER" \
          LDAP="$LDAP" TODAY="$TODAY" TASKS_JSON="$TASKS_JSON" REPOS="$REPOS" \
          python3 "$SCRIPT_DIR/_project.py" plan-new)" || {
    echo "project new: plan failed" >&2; return 1
  }

  if (( DRY )); then
    echo "$PLAN" | python3 "$SCRIPT_DIR/_project.py" print-dry-plan
    return 0
  fi

  # Materialize the project file directly. Then dispatch all child stubs via
  # checkpoint-batch.sh? No — checkpoint-batch updates existing tasks. Children
  # are new files. Easier: write each file to disk then call bin/checkpoint.sh
  # per child (atomic create commits, each with proper trailers).
  #
  # But the spec says "creates child task stubs via bin/checkpoint-batch.sh".
  # checkpoint-batch.sh requires the files to already exist (find_task only
  # globs existing). So: write files, then bulk-add via a single git commit
  # crafted here (not via checkpoint.sh per child, which would push 1+N times).
  python3 "$SCRIPT_DIR/_project.py" materialize-new <<< "$PLAN"

  # Stage everything + commit + push in one shot (parent + children atomic).
  verify_provenance || return 1
  git pull --no-rebase --autostash -q

  local META
  META="$(echo "$PLAN" | python3 "$SCRIPT_DIR/_project.py" print-create-meta)"
  local SUBJECT BODY TRAILERS
  SUBJECT="$(echo "$META" | python3 -c 'import json,sys;print(json.load(sys.stdin)["subject"])')"
  BODY="$(echo "$META" | python3 -c 'import json,sys;print(json.load(sys.stdin)["body"])')"
  TRAILERS="$(echo "$META" | python3 -c 'import json,sys;print(json.load(sys.stdin)["trailers"])')"

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    git add "$path"
  done < <(echo "$META" | python3 -c 'import json,sys
for p in json.load(sys.stdin)["paths"]: print(p)')

  if git diff --cached --quiet; then
    echo "project new: no changes staged"; return 0
  fi

  git commit -q -m "$SUBJECT" -m "$BODY" -m "$TRAILERS"
  push_with_retry || return 1
  record_session_touch "$SLUG" "project-new"
  local NCHILD
  NCHILD="$(echo "$PLAN" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["children"]))')"
  echo "project new: created $SLUG with $NCHILD child task(s)"
}

# ---------- sub: next ----------

cmd_next() {
  local SLUG="${1:-}"
  [[ -z "$SLUG" ]] && { echo "project next: slug required" >&2; return 2; }
  PROJECT_SLUG="$SLUG" python3 "$SCRIPT_DIR/_project.py" next
}

# ---------- sub: claim / release / reap (phase 2) ----------

# Lock file for same-machine claim arbitration. Created on demand.
_claim_lockfile() {
  mkdir -p .cache/claims
  echo ".cache/claims/lock"
}

# Run a project.sh subcommand under an exclusive flock. Used for claim/release
# to give same-machine atomicity across concurrent Claude+Codex sessions.
# Re-execs project.sh through bin/_flock.py with WORKLOG_CLAIM_LOCKED=1 set so
# we don't recurse.
_run_under_flock() {
  if [[ "${WORKLOG_CLAIM_LOCKED:-}" == "1" ]]; then
    "$@"
    return $?
  fi
  WORKLOG_CLAIM_LOCKED=1 python3 "$SCRIPT_DIR/_flock.py" \
    "$(_claim_lockfile)" -- "$@"
}

# Resolve a project's stale_after duration via _claim.py; default 30m.
_project_stale_after() {
  python3 "$SCRIPT_DIR/_claim.py" project-stale-after "$1" 2>/dev/null || echo "30m"
}

# Internal: claim a specific child slug for the current session.
# Args: <child_slug> <project_slug> [--dry-run]
_do_claim() {
  local CHILD="$1" PROJECT="$2" DRY="${3:-}"
  local CHILD_PATH SESSION STALE
  CHILD_PATH="$(find_task "$CHILD" || true)"
  [[ -z "$CHILD_PATH" ]] && { echo "claim: no task file for '$CHILD'" >&2; return 1; }
  SESSION="$(resolve_session_id)"
  STALE="$(_project_stale_after "$PROJECT")"

  # Read current claim state.
  local CUR
  CUR="$(python3 "$SCRIPT_DIR/_claim.py" read "$CHILD_PATH")"
  local CUR_SID
  CUR_SID="$(echo "$CUR" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")')"

  if [[ "$DRY" == "--dry-run" ]]; then
    if [[ -z "$CUR_SID" ]]; then
      echo "CLAIM_OK $CHILD"
      return 0
    fi
    if [[ "$CUR_SID" == "$SESSION" ]]; then
      echo "CLAIM_OK $CHILD (already held by me)"
      return 0
    fi
    # Different session — check staleness.
    if python3 "$SCRIPT_DIR/_claim.py" is-stale "$CHILD_PATH" --stale-after="$STALE" >/dev/null 2>&1; then
      echo "STALE $CHILD held by $CUR_SID (can reap)"
      return 0
    fi
    local HOST STARTED
    HOST="$(echo "$CUR" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("host") or "")')"
    STARTED="$(echo "$CUR" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("started_at") or "")')"
    local SUFFIX=""
    [[ -n "$HOST" ]] && SUFFIX=" host=$HOST"
    [[ -n "$STARTED" ]] && SUFFIX="$SUFFIX started=$STARTED"
    echo "LOCKED_BY=$CUR_SID $CHILD$SUFFIX"
    return 1
  fi

  # Write claim block (refuses if non-stale + different session).
  if ! python3 "$SCRIPT_DIR/_claim.py" write "$CHILD_PATH" \
        --session="$SESSION" --stale-after="$STALE"; then
    return 1
  fi

  register_session "$SESSION"

  # Commit + push (claim-aware: refuse to merge over a winning race).
  verify_provenance || return 1
  git pull --no-rebase --autostash -q || true
  # After pull, the on-disk file may have changed. Re-write the claim to
  # reassert it (write enforces arbitration again).
  if ! python3 "$SCRIPT_DIR/_claim.py" write "$CHILD_PATH" \
        --session="$SESSION" --stale-after="$STALE"; then
    echo "claim: lost race after pull — another session holds $CHILD" >&2
    return 1
  fi
  git add "$CHILD_PATH"
  if git diff --cached --quiet; then
    echo "claim: $CHILD already held by $SESSION (idempotent)"
    return 0
  fi
  local SHORT_SID="${SESSION#*:}"
  SHORT_SID="${SHORT_SID:0:8}"
  git commit -q -m "$CHILD: claim (${SESSION%%:*}/${SHORT_SID})" \
    -m "session: $SESSION" \
    -m "Worklog-Slug: $CHILD
Worklog-Claim: $SESSION"
  push_with_retry || return 1
  record_session_touch "$CHILD" "claim"
  echo "claim: $CHILD held by $SESSION"
}

cmd_claim() {
  # Forms:
  #   claim <child-slug> [--project=<slug>] [--dry-run]
  #   claim next <project-slug> [--dry-run]
  local DRY="" PROJECT="" CHILD=""
  if [[ "${1:-}" == "next" ]]; then
    shift
    PROJECT="${1:-}"; shift || true
    [[ -z "$PROJECT" ]] && { echo "project claim next: project slug required" >&2; return 2; }
    while [[ $# -gt 0 ]]; do
      case "$1" in --dry-run) DRY="--dry-run" ;; esac; shift
    done
    # Walk eligible children in declaration order; try to claim the first
    # not-locked one. Re-uses cmd_next logic but loops over candidates.
    local CANDIDATES
    CANDIDATES="$(PROJECT_SLUG="$PROJECT" python3 "$SCRIPT_DIR/_project.py" eligible-list)" || {
      echo "$CANDIDATES" >&2; return 1
    }
    [[ -z "$CANDIDATES" ]] && { echo "project claim next: no eligible tasks" >&2; return 1; }
    while IFS= read -r cand; do
      [[ -z "$cand" ]] && continue
      if _do_claim "$cand" "$PROJECT" "$DRY"; then
        return 0
      fi
    done <<< "$CANDIDATES"
    echo "project claim next: all eligible tasks are locked by other sessions" >&2
    return 1
  fi

  CHILD="${1:-}"; shift || true
  [[ -z "$CHILD" ]] && { echo "project claim: child slug required (or 'claim next <project>')" >&2; return 2; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project=*) PROJECT="${1#--project=}" ;;
      --dry-run)   DRY="--dry-run" ;;
    esac
    shift
  done
  # If --project missing, derive from child's parent_slug.
  if [[ -z "$PROJECT" ]]; then
    local CP; CP="$(find_task "$CHILD" || true)"
    if [[ -n "$CP" ]]; then
      PROJECT="$(awk -F': *' '/^parent_slug:/ {print $2; exit}' "$CP" || true)"
    fi
  fi
  _do_claim "$CHILD" "$PROJECT" "$DRY"
}

cmd_release() {
  local CHILD="${1:-}"
  [[ -z "$CHILD" ]] && { echo "project release: child slug required" >&2; return 2; }
  local CHILD_PATH SESSION
  CHILD_PATH="$(find_task "$CHILD" || true)"
  [[ -z "$CHILD_PATH" ]] && { echo "release: no task file for '$CHILD'" >&2; return 1; }
  SESSION="$(resolve_session_id)"

  if ! python3 "$SCRIPT_DIR/_claim.py" clear "$CHILD_PATH" --session="$SESSION"; then
    return 1
  fi
  verify_provenance || return 1
  git pull --no-rebase --autostash -q || true
  python3 "$SCRIPT_DIR/_claim.py" clear "$CHILD_PATH" --session="$SESSION" || true
  git add "$CHILD_PATH"
  if git diff --cached --quiet; then
    echo "release: $CHILD not held by $SESSION (no-op)"
    return 0
  fi
  git commit -q -m "$CHILD: release" \
    -m "session: $SESSION" \
    -m "Worklog-Slug: $CHILD
Worklog-Release: $SESSION"
  push_with_retry || return 1
  record_session_touch "$CHILD" "release"
  echo "release: $CHILD cleared"
}

cmd_reap() {
  local SESSION_FILTER="" STALE_OVERRIDE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session=*) SESSION_FILTER="${1#--session=}" ;;
      --stale=*)   STALE_OVERRIDE="${1#--stale=}" ;;
      --session)   SESSION_FILTER="$2"; shift ;;
      --stale)     STALE_OVERRIDE="$2"; shift ;;
    esac
    shift
  done

  # Walk every active task; for each claim block, decide whether to clear.
  local CLEARED=()
  local f
  for f in people/*/active/*.md; do
    [[ -f "$f" ]] || continue
    local INFO SID HB
    INFO="$(python3 "$SCRIPT_DIR/_claim.py" read "$f" 2>/dev/null)" || continue
    SID="$(echo "$INFO" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")')"
    [[ -z "$SID" ]] && continue
    # Determine stale_after for this task: use override if provided, else
    # look up the parent project (parent_slug:) and ask _claim.py.
    local STALE="$STALE_OVERRIDE"
    if [[ -z "$STALE" ]]; then
      local PARENT
      PARENT="$(awk -F': *' '/^parent_slug:/ {print $2; exit}' "$f" || true)"
      if [[ -n "$PARENT" ]]; then
        STALE="$(_project_stale_after "$PARENT")"
      else
        STALE="30m"
      fi
    fi
    # Filter: if --session set, only clear matching SID; else only clear stale.
    local CLEAR=0
    if [[ -n "$SESSION_FILTER" ]]; then
      [[ "$SID" == "$SESSION_FILTER" ]] && CLEAR=1
    else
      if python3 "$SCRIPT_DIR/_claim.py" is-stale "$f" --stale-after="$STALE" >/dev/null 2>&1; then
        CLEAR=1
      fi
    fi
    (( CLEAR )) || continue
    # Clear (no session filter — reap operates above ownership).
    python3 "$SCRIPT_DIR/_claim.py" clear "$f" || continue
    CLEARED+=("$(basename "$f" .md):$SID")
  done

  if (( ${#CLEARED[@]} == 0 )); then
    echo "reap: no claims to clear"
    return 0
  fi

  verify_provenance || return 1
  git pull --no-rebase --autostash -q || true
  for entry in "${CLEARED[@]}"; do
    local slug="${entry%%:*}"
    local sf
    sf="$(find_task "$slug" || true)"
    [[ -n "$sf" ]] && git add "$sf"
  done
  if git diff --cached --quiet; then
    echo "reap: cleared in-memory but nothing to commit (already at HEAD?)"
    return 0
  fi
  local SUBJECT BODY TRAILERS
  SUBJECT="reap: ${#CLEARED[@]} claim(s) cleared"
  BODY="$(printf '%s\n' "${CLEARED[@]}")"
  TRAILERS="$(for entry in "${CLEARED[@]}"; do
    slug="${entry%%:*}"; sid="${entry#*:}"
    printf 'Worklog-Slug: %s\nWorklog-Reap: %s\n' "$slug" "$sid"
  done)"
  git commit -q -m "$SUBJECT" -m "$BODY" -m "$TRAILERS"
  push_with_retry || return 1
  echo "reap: cleared ${#CLEARED[@]} claim(s)"
}

cmd_verify() {
  # verify <slug> | verify --all
  # Exit codes: 0 clean, 1 warnings, 2 errors.
  python3 "$SCRIPT_DIR/_project.py" verify "$@"
}

cmd_list() {
  python3 "$SCRIPT_DIR/_project.py" list "$@"
}

# ---------- dispatch ----------

case "$SUB" in
  new)     cmd_new "$@" ;;
  next)    cmd_next "$@" ;;
  claim|release|reap)
    # Same-machine atomicity for the mutex ops.
    if [[ "${WORKLOG_CLAIM_LOCKED:-}" == "1" ]]; then
      case "$SUB" in
        claim)   cmd_claim "$@" ;;
        release) cmd_release "$@" ;;
        reap)    cmd_reap "$@" ;;
      esac
    else
      mkdir -p .cache/claims
      WORKLOG_CLAIM_LOCKED=1 exec python3 "$SCRIPT_DIR/_flock.py" \
        "$(_claim_lockfile)" -- "$0" "$SUB" "$@"
    fi
    ;;
  verify)  cmd_verify "$@" ;;
  list)    cmd_list "$@" ;;
  *)       echo "project: unknown subcommand '$SUB'" >&2; usage >&2; exit 2 ;;
esac
