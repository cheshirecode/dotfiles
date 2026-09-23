#!/usr/bin/env bash
# Bring up a worklog instance on this machine, for this login, from nothing.
#
#   bootstrap.sh probe
#       Read-only. Prints what this machine and login have: tools, git
#       identity, gh accounts, and every worklog vault already on disk.
#       Emits KEY=VAL lines, then one TSV row per vault found.
#
#   bootstrap.sh apply --repo <path> [--remote <url>] [--ns <name>]
#                      [--name <git name>] [--email <git email>]
#                      [--identity-domain <domain>] [--instance <id>]
#                      [--no-hooks]
#       Clones <url> into <path>, or creates a new vault there. Then writes
#       this instance's settings into the clone's own .git/config and checks
#       them from a shell with no direnv and no WORKLOG_* variables.
#
# One instance = one (machine, login, vault). Its settings live in the clone's
# .git/config, because that file is per clone, per machine and never pushed:
#
#   worklog.namespace       people/<ns>/ this instance writes to
#   worklog.instance        <host>/<login>, unless --instance says otherwise
#   worklog.identityDomain  author email domain the identity hook accepts
#   user.name, user.email   author for commits in this clone
#
# The per-clone .envrc stays a convenience. A tool shell (hook, agent, MCP
# server) loads no .envrc, so anything only .envrc carried was lost there.
#
# With no git identity anywhere and no --email, apply sets a placeholder
# `<ns>@<host>.invalid` (RFC 2606 reserved TLD) so the first commit works, and
# reports IDENTITY=placeholder. Fix it before the vault gets a remote.
#
# Exit codes: 0 ok, 1 verification failed, 2 usage, 3 refused (target conflict).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

# Four states per tool: ok, absent, broken (present but fails to run).
tool_state() {
  local t="$1" v
  command -v "$t" >/dev/null 2>&1 || { printf 'absent'; return; }
  case "$t" in
    python3) v="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)" ;;
    direnv)  v="$(direnv version 2>/dev/null)" ;;
    *)       v="$("$t" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)" ;;
  esac
  if [[ -n "$v" ]]; then printf 'ok %s' "$v"; else printf 'broken'; fi
}

host_short() { hostname -s 2>/dev/null || hostname 2>/dev/null || uname -n 2>/dev/null || echo unknown; }
login_name() { id -un 2>/dev/null || printf '%s' "${USER:-unknown}"; }

# Namespace-safe: lowercase, [a-z0-9._-] only. Strips a GitHub noreply prefix.
sanitize_ns() {
  printf '%s' "$1" | sed -E 's|^[0-9]+\+||; s|@.*||' | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

# Git identity as git itself resolves it outside any clone: env, then global.
git_identity() {
  local name email src
  if [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
    name="${GIT_AUTHOR_NAME:-}"; email="$GIT_AUTHOR_EMAIL"; src="env"
  else
    name="$(git config --global --get user.name 2>/dev/null || true)"
    email="$(git config --global --get user.email 2>/dev/null || true)"
    src="global"
  fi
  if [[ -n "$email" ]]; then printf 'ok\t%s\t%s\t%s' "$src" "$name" "$email"; else printf 'absent'; fi
}

# gh accounts per host. gh masks tokens in `auth status`; nothing secret prints.
gh_accounts() {
  command -v gh >/dev/null 2>&1 || { printf 'absent'; return; }
  local out
  if ! out="$(gh auth status 2>&1)"; then
    if grep -q 'not logged' <<<"$out"; then printf 'unauthenticated'; else printf 'unknown'; fi
    return
  fi
  awk '
    /Logged in to/ { acct=""; host=""; for (i=1;i<NF;i++) { if ($i=="to" && host=="") host=$(i+1); if ($i=="account") acct=$(i+1) } }
    /Active account: true/ && acct != "" { list = list sep host ":" acct "*"; sep=","; acct="" }
    /Active account: false/ && acct != "" { list = list sep host ":" acct; sep=","; acct="" }
    END { if (list == "") print "unknown"; else print list }
  ' <<<"$out"
}

# Vault = a git clone named _worklog with a people/ dir. Bounded depth; skips
# directories that are large and never hold a vault.
find_vaults() {
  {
    [[ -n "${WORKLOG_REPO:-}" && -d "$WORKLOG_REPO" ]] && printf '%s\n' "$WORKLOG_REPO"
    # A non-zero find (an unreadable dir) is reported, not read as "no vaults".
    find "$HOME" -maxdepth 4 \( -name Library -o -name node_modules -o -name .Trash -o -name .cache \) -prune \
      -o -type d -name _worklog -print 2>/dev/null || echo "__scan_incomplete__"
  } | while IFS= read -r d; do
    [[ "$d" == __scan_incomplete__ ]] && { printf '%s\n' "$d"; continue; }
    [[ -e "$d/.git" && -d "$d/people" ]] || continue
    (cd "$d" && pwd -P)
  done | sort -u
}

suggest_repo() {
  local base
  for base in "$HOME/Documents/projects" "$HOME/projects" "$HOME/src" "$HOME/code"; do
    [[ -d "$base" ]] && { printf '%s/_worklog' "$base"; return; }
  done
  printf '%s/_worklog' "$HOME"
}

cmd_probe() {
  local id ns
  id="$(git_identity)"
  printf 'OS=%s\n' "$(uname -s)"
  printf 'HOST=%s\n' "$(host_short)"
  printf 'LOGIN=%s\n' "$(login_name)"
  printf 'HOME=%s\n' "$HOME"
  printf 'INSTANCE=%s/%s\n' "$(host_short)" "$(login_name)"
  local t
  for t in git python3 direnv gh glab node; do
    printf 'tool.%s=%s\n' "$t" "$(tool_state "$t")"
  done
  if [[ "$id" == absent ]]; then
    printf 'GIT_IDENTITY=absent\n'
    ns="$(sanitize_ns "$(login_name)")"
  else
    IFS=$'\t' read -r _ src name email <<<"$id"
    printf 'GIT_IDENTITY=ok source=%s name=%s email=%s\n' "$src" "$name" "$email"
    ns="$(sanitize_ns "$email")"
  fi
  printf 'GH_ACCOUNTS=%s\n' "$(gh_accounts)"
  printf 'WORKLOG_REPO_ENV=%s\n' "${WORKLOG_REPO:-unset}"
  printf 'SUGGESTED_REPO=%s\n' "$(suggest_repo)"
  printf 'SUGGESTED_NS=%s\n' "${WORKLOG_LDAP:-${WORKLOG_NS:-$ns}}"
  local n=0 v origin vns vmail scan=complete
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    [[ "$v" == __scan_incomplete__ ]] && { scan=incomplete; continue; }
    origin="$(git -C "$v" remote get-url origin 2>/dev/null || echo none)"
    vns="$(git -C "$v" config --local --get worklog.namespace 2>/dev/null || echo unset)"
    vmail="$(git -C "$v" config --local --get user.email 2>/dev/null || echo unset)"
    printf 'vault\t%s\t%s\t%s\t%s\n' "$v" "$origin" "$vns" "$vmail"
    n=$((n + 1))
  done < <(find_vaults)
  printf 'VAULTS=%s\n' "$n"
  printf 'VAULTS_SCAN=%s\n' "$scan"
}

cmd_apply() {
  local repo="" remote="" ns="" name="" email="" domain="" instance="" hooks=1
  while (($#)); do
    case "$1" in
      --repo) repo="${2:?}"; shift 2 ;;
      --remote) remote="${2:?}"; shift 2 ;;
      --ns) ns="${2:?}"; shift 2 ;;
      --name) name="${2:?}"; shift 2 ;;
      --email) email="${2:?}"; shift 2 ;;
      --identity-domain) domain="${2:?}"; shift 2 ;;
      --instance) instance="${2:?}"; shift 2 ;;
      --no-hooks) hooks=0; shift ;;
      -h|--help) usage 0 ;;
      *) echo "bootstrap: unknown arg: $1" >&2; usage 2 ;;
    esac
  done
  [[ -n "$repo" ]] || { echo "bootstrap: apply needs --repo <path> (run 'probe' for a suggestion)" >&2; exit 2; }
  command -v git >/dev/null 2>&1 || { echo "bootstrap: git is absent; install git first" >&2; exit 2; }

  # Target: clone, create, or adopt an existing clone.
  local action
  if [[ -e "$repo/.git" ]]; then
    if [[ -n "$remote" ]]; then
      local have; have="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
      if [[ "$have" != "$remote" ]]; then
        echo "bootstrap: $repo is a clone of '${have:-no origin}', not '$remote'; refusing" >&2
        exit 3
      fi
    fi
    action=adopted
  elif [[ -e "$repo" && -n "$(ls -A "$repo" 2>/dev/null)" ]]; then
    echo "bootstrap: $repo exists, is not empty and is not a git clone; refusing" >&2
    exit 3
  elif [[ -n "$remote" ]]; then
    mkdir -p "$(dirname "$repo")"
    git clone -q "$remote" "$repo"
    action=cloned
  else
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    action=created
  fi
  repo="$(cd "$repo" && pwd -P)"

  # Precedence for each setting: flag, then the clone's own value (so a re-run
  # never replaces an earlier decision), then env/global git, then default.
  local_get() { git -C "$repo" config --local --get "$1" 2>/dev/null || true; }
  local email_flag="$email"
  [[ -n "$email" ]] || email="$(local_get user.email)"
  [[ -n "$name" ]] || name="$(local_get user.name)"
  # The clone's namespace outranks an inherited WORKLOG_LDAP: an installer run
  # from one tree must not stamp that tree's namespace onto another vault.
  [[ -n "$ns" ]] || ns="$(local_get worklog.namespace)"
  [[ -n "$ns" ]] || ns="${WORKLOG_LDAP:-${WORKLOG_NS:-}}"
  [[ -n "$instance" ]] || instance="$(local_get worklog.instance)"
  # A new --email re-derives the domain; a kept email keeps the stored one.
  [[ -n "$domain" || -n "$email_flag" ]] || domain="$(local_get worklog.identityDomain)"
  local id id_state=ok
  id="$(git_identity)"
  if [[ -z "$email" && "$id" != absent ]]; then
    IFS=$'\t' read -r _ _ gname gemail <<<"$id"
    email="$gemail"; [[ -n "$name" ]] || name="$gname"
  fi
  [[ -n "$ns" ]] || ns="$(sanitize_ns "${email:-$(login_name)}")"
  [[ "$ns" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "bootstrap: invalid namespace '$ns'" >&2; exit 2; }
  if [[ -z "$email" ]]; then
    email="$ns@$(sanitize_ns "$(host_short)").invalid"
  fi
  [[ "$email" == *.invalid ]] && id_state=placeholder
  [[ -n "$name" ]] || name="$ns"
  [[ -n "$instance" ]] || instance="$(host_short)/$(login_name)"
  if [[ -z "$domain" && "$id_state" == ok ]]; then domain="${email#*@}"; fi

  # Instance settings, clone-local. Set before seeding so the first commit
  # carries this identity rather than failing on an unset user.email.
  git -C "$repo" config --local user.name "$name"
  git -C "$repo" config --local user.email "$email"
  git -C "$repo" config --local worklog.namespace "$ns"
  git -C "$repo" config --local worklog.instance "$instance"
  if [[ -n "$domain" ]]; then
    git -C "$repo" config --local worklog.identityDomain "$domain"
  else
    git -C "$repo" config --local --unset worklog.identityDomain 2>/dev/null || true
  fi

  # Seed templates + namespace. Idempotent; commits only in an empty repo.
  WORKLOG_LDAP="$ns" bash "$SCRIPT_DIR/init-new-data-repo.sh" "$repo" "$ns" >/dev/null

  local hook_state=skipped
  if (( hooks )); then
    if bash "$SCRIPT_DIR/install-hooks.sh" --data-root="$repo" --write --git-hooks-only >/dev/null 2>&1; then
      hook_state=installed
    else
      hook_state=failed
    fi
  fi

  # Verify from where the values are READ: a shell with no direnv and no
  # WORKLOG_* env, cwd inside the clone. This is the shell a hook or an agent
  # tool call gets.
  local seen
  seen="$(cd "$repo" && env -i HOME="$HOME" PATH="$PATH" TMPDIR="$(mktemp -d)" \
    bash -c ". '$SCRIPT_DIR/_lib.sh'; resolve_ldap" 2>/dev/null || true)"

  printf 'REPO=%s\n' "$repo"
  printf 'ACTION=%s\n' "$action"
  printf 'ORIGIN=%s\n' "$(git -C "$repo" remote get-url origin 2>/dev/null || echo none)"
  printf 'NS=%s\n' "$ns"
  printf 'INSTANCE=%s\n' "$instance"
  printf 'IDENTITY=%s %s <%s>\n' "$id_state" "$name" "$email"
  printf 'IDENTITY_DOMAIN=%s\n' "${domain:-unset}"
  printf 'HOOKS=%s\n' "$hook_state"
  if [[ "$seen" == "$ns" ]]; then
    printf 'VERIFY=ok tool-shell namespace=%s\n' "$seen"
  else
    printf 'VERIFY=mismatch tool-shell namespace=%s want=%s\n' "${seen:-empty}" "$ns"
    exit 1
  fi
  [[ "$id_state" == placeholder ]] && \
    printf 'NEXT=git -C %q config user.email <you@domain>  # placeholder identity\n' "$repo"
  [[ "$hook_state" == failed ]] && \
    printf 'NEXT=%q --data-root=%q --write --git-hooks-only  # hooks failed\n' "$SCRIPT_DIR/install-hooks.sh" "$repo"
  return 0
}

case "${1:-}" in
  probe) shift; cmd_probe "$@" ;;
  apply) shift; cmd_apply "$@" ;;
  -h|--help|help) usage 0 ;;
  *) usage 2 ;;
esac
