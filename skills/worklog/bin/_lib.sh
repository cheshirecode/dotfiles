#!/usr/bin/env bash
# Shared helpers for bin/ scripts. Source with `. "$(dirname "$0")/_lib.sh"`.
# Not executable on its own.

# Resolve the active worklog data repo. Precedence:
#   1. $WORKLOG_REPO env (set by per-clone .envrc — the SoT)
#   2. git rev-parse --show-toplevel, if cwd is inside a clone with people/
#   3. fail with a clear remediation message
# Writes nothing; just prints the resolved path or returns non-zero.
resolve_worklog_repo() {
  if [[ -n "${WORKLOG_REPO:-}" ]]; then
    if [[ -d "$WORKLOG_REPO/.git" || -f "$WORKLOG_REPO/.git" ]]; then
      printf '%s' "$WORKLOG_REPO"
      return 0
    fi
    echo "_lib.sh::resolve_worklog_repo: WORKLOG_REPO=$WORKLOG_REPO is not a git repo." >&2
    return 1
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" && -d "$top/people" ]]; then
    printf '%s' "$top"
    return 0
  fi
  echo "_lib.sh::resolve_worklog_repo: cannot locate a worklog data repo." >&2
  echo "  Either set WORKLOG_REPO in your shell (via .envrc) or run from inside a clone." >&2
  return 1
}

# Resolve the caller's worklog namespace (historically named LDAP). Precedence:
# $WORKLOG_LDAP -> $WORKLOG_NS -> git email -> $USER. Cache key includes the
# resolved repo path so projects/_worklog and oss/_worklog cannot poison each
# other's fallback result on the same machine. Cached 24h to avoid re-running
# git config / gcloud on every invocation.
resolve_ldap() {
  local explicit_ns="${WORKLOG_LDAP:-${WORKLOG_NS:-}}"
  local repo_key repo_hash
  repo_key="${WORKLOG_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  if command -v shasum >/dev/null 2>&1; then
    repo_hash="$(printf '%s' "$repo_key" | shasum | awk '{print $1}')"
  else
    repo_hash="$(printf '%s' "$repo_key" | cksum | awk '{print $1}')"
  fi
  local cache_key="${explicit_ns:-default-${USER:-anon}}-${repo_hash}"
  local cache="${TMPDIR:-/tmp}/worklog-ldap-${cache_key}"
  if [[ -f "$cache" ]]; then
    local age
    local mtime
    mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null || echo 0)
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    age=$(( $(date +%s) - mtime ))
    if [[ "$age" -lt 86400 ]]; then
      cat "$cache"
      return
    fi
  fi
  local ldap
  ldap="$explicit_ns"
  # Strip GitHub noreply prefix `<digits>+` BEFORE stripping `@...`, so
  # 1631630+cheshirecode@users.noreply.github.com -> cheshirecode
  # (was returning "1631630+cheshirecode" which broke namespace lookups).
  [[ -z "$ldap" ]] && ldap="$(git config user.email 2>/dev/null | sed -E 's|^[0-9]+\+||; s|@.*||' || true)"
  [[ -z "$ldap" ]] && ldap="${USER:-user}"
  printf '%s' "$ldap" > "$cache" 2>/dev/null || true
  echo "$ldap"
}

# Verify namespace/git-author provenance. Explicit namespaces (WORKLOG_LDAP or
# WORKLOG_NS) are allowed to differ from git user.email: oss/_worklog writes
# under people/oss while committing as cheshirecode. Without an explicit
# namespace, the git email local-part must match the derived namespace. Runs at
# most once per clone+identity tuple via .cache/provenance-verified.
verify_provenance() {
  [[ "${WORKLOG_SKIP_PROVENANCE:-0}" == "1" ]] && return 0
  local sentinel=".cache/provenance-verified"

  local ldap email_local git_email
  ldap="$(resolve_ldap)"
  git_email="$(git config user.email 2>/dev/null || true)"
  if [[ -f "$sentinel" ]]; then
    local sent_ldap sent_email
    sent_ldap="$(awk 'NR==1 {print $1}' "$sentinel" 2>/dev/null || true)"
    sent_email="$(awk 'NR==1 {print $2}' "$sentinel" 2>/dev/null || true)"
    if [[ "$sent_ldap" == "$ldap" && "$sent_email" == "$git_email" ]]; then
      return 0
    fi
  fi
  if [[ -z "$git_email" ]]; then
    echo "verify_provenance: git config user.email is empty — set it before checkpointing." >&2
    echo "  git config user.email \"${ldap}@users.noreply.github.com\"" >&2
    return 1
  fi
  email_local="${git_email%@*}"
  if [[ -z "${WORKLOG_LDAP:-${WORKLOG_NS:-}}" && "$email_local" != "$ldap" ]]; then
    echo "verify_provenance: LDAP/email mismatch — refusing to commit." >&2
    echo "  resolved namespace:  $ldap (from git email / cache)" >&2
    echo "  git config user.email: $git_email (local part: $email_local)" >&2
    echo "" >&2
    echo "  This usually means git user.email points at the wrong account," >&2
    echo "  or this clone needs WORKLOG_LDAP / WORKLOG_NS in .envrc." >&2
    echo "" >&2
    echo "  Fix:    git config user.email \"${ldap}@users.noreply.github.com\"" >&2
    echo "  Bypass: WORKLOG_SKIP_PROVENANCE=1 (one-shot)" >&2
    return 1
  fi
  mkdir -p .cache
  printf '%s\t%s\n' "$ldap" "$git_email" > "$sentinel"
  return 0
}

# Push with bounded retry. Default 3 attempts. On failure, `git pull
# --no-rebase --autostash` then retry — handles the common non-fast-forward
# / push-lock case from concurrent sessions. Surfaces the final error to
# stderr instead of swallowing with `|| true`. Why: silent push failures
# left commits stuck locally for hours without surfacing — caller has no
# idea state has drifted.
push_with_retry() {
  local attempts=3 i=1
  while (( i <= attempts )); do
    if git push -q 2>/tmp/worklog-push-err.$$; then
      rm -f /tmp/worklog-push-err.$$
      return 0
    fi
    if (( i == attempts )); then
      echo "push: failed after $attempts attempts:" >&2
      cat /tmp/worklog-push-err.$$ >&2
      rm -f /tmp/worklog-push-err.$$
      return 1
    fi
    echo "push: attempt $i failed; pulling --autostash and retrying" >&2
    git pull --no-rebase --autostash -q 2>/dev/null || true
    i=$((i+1))
    sleep 1
  done
}

# Detect uncommitted edits under the worklog-managed surfaces (people/, docs/,
# bin/). Returns 0 if clean, 1 + lists dirty files on stderr if not. Used by
# the SKILL.md preamble before `git pull --autostash`: silent autostashes can
# pop with conflicts that go unnoticed; running bin/autosave.sh first is the
# safer path. Advisory only — never short-circuits the pull itself.
detect_dirty_worklog() {
  local dirty
  dirty="$(git status --porcelain -- people/ docs/ bin/ 2>/dev/null || true)"
  [[ -z "$dirty" ]] && return 0
  {
    echo "⚠ worklog has uncommitted edits:"
    printf '%s\n' "$dirty" | sed 's/^/  /'
    echo "  Running bin/autosave.sh first is safer than --autostash."
  } >&2
  return 1
}

# Resolve a session ID for claim arbitration. Returns "<host>:<id>" on stdout.
# Precedence:
#   Claude Code   $CLAUDE_CODE_SESSION_ID
#   Codex CLI     $CODEX_SESSION_ID, else $OPENAI_SESSION_ID
#   Cursor        $CURSOR_SESSION_ID
#   Fallback      UUID at ~/.config/worklog/session-id (per-machine, generated on first call)
#
# Host label is informational only — the full "<host>:<id>" string is the
# arbitration key. Same `id` from different hosts is treated as distinct.
resolve_session_id() {
  if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    printf 'claude-code:%s' "$CLAUDE_CODE_SESSION_ID"; return 0
  fi
  if [[ -n "${CODEX_SESSION_ID:-}" ]]; then
    printf 'codex:%s' "$CODEX_SESSION_ID"; return 0
  fi
  if [[ -n "${OPENAI_SESSION_ID:-}" ]]; then
    printf 'codex:%s' "$OPENAI_SESSION_ID"; return 0
  fi
  if [[ -n "${CURSOR_SESSION_ID:-}" ]]; then
    printf 'cursor:%s' "$CURSOR_SESSION_ID"; return 0
  fi
  # Per-machine UUID fallback.
  local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/worklog"
  local id_file="$cfg_dir/session-id"
  if [[ ! -s "$id_file" ]]; then
    mkdir -p "$cfg_dir"
    local uuid
    if command -v uuidgen >/dev/null 2>&1; then
      uuid="$(uuidgen | tr 'A-Z' 'a-z')"
    else
      uuid="$(python3 -c 'import uuid;print(uuid.uuid4())')"
    fi
    printf '%s' "$uuid" > "$id_file"
  fi
  printf 'machine:%s' "$(cat "$id_file")"
}

# Register the current session in .cache/sessions/<id>.json (idempotent overwrite).
# Records {host, pid, started_at}. Called on first claim by project.sh.
register_session() {
  local sid="$1"
  local safe="${sid//:/_}"
  local dir=".cache/sessions"
  mkdir -p "$dir"
  local host pid ts
  host="${sid%%:*}"
  pid="$$"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"host":"%s","pid":%s,"started_at":"%s"}\n' "$host" "$pid" "$ts" > "$dir/$safe.json"
}

# Append a session-touch record to .cache/sessions.jsonl. Called by checkpoint.sh
# and archive.sh on every successful operation. The companion `detect_session_collision`
# tails the file and warns if another (machine, ldap) touched the same slug recently.
# Lightweight cross-session signal; gitignored (.cache/ is); bounded to last 1000 lines.
record_session_touch() {
  local slug="$1" action="${2:-touch}"
  local log=".cache/sessions.jsonl"
  local ldap; ldap="$(resolve_ldap)"
  local machine; machine="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p .cache
  printf '{"ts":"%s","machine":"%s","ldap":"%s","slug":"%s","action":"%s"}\n' \
    "$ts" "$machine" "$ldap" "$slug" "$action" >> "$log"
  # Bound the file at ~1000 lines.
  local lines; lines="$(wc -l <"$log" 2>/dev/null | tr -d '[:space:]' || echo 0)"
  if [[ "${lines:-0}" -gt 1100 ]]; then
    tail -n 1000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
  fi
}

# Warn if another (machine, ldap) touched the given slug in the last 5 minutes.
# Never blocks; advisory output to stderr only. Caller passes the slug they're
# about to operate on; we look back through .cache/sessions.jsonl.
detect_session_collision() {
  local slug="$1"
  local log=".cache/sessions.jsonl"
  [[ -f "$log" ]] || return 0
  local ldap; ldap="$(resolve_ldap)"
  local machine; machine="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
  local now_epoch; now_epoch="$(date -u +%s)"
  # Grep last 100 lines for matching slug; check if any are <300s old AND from a different (machine, ldap).
  local hits
  hits="$(tail -n 100 "$log" 2>/dev/null | python3 -c "
import json, sys, datetime
slug = sys.argv[1]
me = (sys.argv[2], sys.argv[3])
now = int(sys.argv[4])
for line in sys.stdin:
  try:
    r = json.loads(line)
  except Exception:
    continue
  if r.get('slug') != slug:
    continue
  if (r.get('machine'), r.get('ldap')) == me:
    continue
  try:
    ts = datetime.datetime.fromisoformat(r['ts'].replace('Z', '+00:00')).timestamp()
  except Exception:
    continue
  age = int(now - ts)
  if age <= 300:
    print(f\"{r['machine']}/{r['ldap']} touched {slug} {age}s ago (action={r.get('action')})\")
" "$slug" "$machine" "$ldap" "$now_epoch" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    {
      echo "⚠ session-collision: another session touched '$slug' recently:"
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  $line"
      done <<< "$hits"
      echo "  Coordinate or wait — concurrent edits risk lost work."
    } >&2
  fi
}

# Stage paths for bin/autosave.sh. Default: caller's people/$LDAP/ only.
# WORKLOG_AUTOSAVE_WIDE=1 stages people/, docs/, bin/, projects/.
# Returns 1 when nothing was staged (tree may still be dirty outside scope).
autosave_stage_paths() {
  local ldap path
  ldap="$(resolve_ldap)"
  if [[ "${WORKLOG_AUTOSAVE_WIDE:-0}" == "1" ]]; then
    for path in people docs bin projects; do
      [[ -e "$path" ]] && git add -A "$path" 2>/dev/null || true
    done
  else
    [[ -d "people/$ldap" ]] && git add -A "people/$ldap/"
  fi
  if git diff --cached --quiet; then
    return 1
  fi
  return 0
}

# True when HEAD is an unpushed autosave commit safe to amend into.
autosave_can_amend_head() {
  local subject upstream unpushed non_autosave
  subject="$(git log -1 --format=%s 2>/dev/null || true)"
  [[ "$subject" == autosave:* ]] || return 1
  upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
  [[ -n "$upstream" ]] || return 0
  unpushed="$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
  (( unpushed > 0 )) || return 1
  non_autosave="$(git log "${upstream}..HEAD" --format=%s | { grep -vc '^autosave:' || true; })"
  (( non_autosave == 0 ))
}

# Comma-separated staged paths for Worklog-Paths trailer (sorted, stable).
autosave_paths_trailer() {
  git diff --cached --name-only | LC_ALL=C sort | paste -sd, -
}
