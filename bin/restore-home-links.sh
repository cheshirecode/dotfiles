#!/usr/bin/env bash
# Re-create the parts of $HOME that a workspace restart destroys.
#
# CANONICAL COPY: dotfiles bin/restore-home-links.sh. Edit it in
# /workspace/dotfiles (the persistent clone) and push. install.sh copies it to
# /workspace/bin/restore-home-links.sh, which is the path the SessionStart hook
# in ~/.claude/settings.json runs -- a persistent path, so the hook never
# depends on the ephemeral dotfiles clone being present at session start, and a
# failed install leaves the previous working copy in place.
# The installed copy is GENERATED. A hand-edit there is overwritten on the next
# workspace start, silently -- three sessions edited it that way on 2026-09-08.
#
# /workspace and ~/.claude ride the persistent volume; the rest of $HOME is on
# the container overlay and is rebuilt on every start. Two things then break
# silently:
#
#   ~/.gitconfig.local     dotfiles install.sh recreates it as a placeholder
#                          with the [user] lines COMMENTED OUT, so every work
#                          repo loses its identity and commits unattributed.
#   ~/.shell_common.local  vanishes, so WORKLOG_* and every token alias stop
#                          loading -- including in non-interactive shells.
#   ~/.git-credentials     Coder rewrites it with only the gitlab OAuth line,
#                          dropping the github.com line and the glpat- PAT.
#   ~/.vault-token         vanishes, so the next `super` command tries an
#                          interactive OIDC login that cannot complete inside
#                          a tool call.
#
# Idempotent and safe to run on every session start. Never prints a secret.

set -uo pipefail

SECRETS="${ENV_SECRETS:-/workspace/.env.secrets}"
changed=0
note() { printf 'restore-home-links: %s\n' "$*"; changed=1; }

link() {  # link <target> <linkname>
  local tgt="$1" ln_="$2"
  [ -e "$tgt" ] || return 0
  [ "$(readlink "$ln_" 2>/dev/null)" = "$tgt" ] && return 0
  # On a NEW instance the parent may not exist yet (~/.claude is created by the
  # CLI, not the platform), and a bare ln then prints a raw error to stderr.
  mkdir -p "$(dirname "$ln_")" 2>/dev/null
  ln -sfn "$tgt" "$ln_" 2>/dev/null && note "relinked $ln_ -> $tgt"
}

link /workspace/gitconfig.local    "$HOME/.gitconfig.local"
link /workspace/shell_common.local "$HOME/.shell_common.local"
link /workspace/.claude-mcp.json   "$HOME/.claude/.mcp.json"

# Credentials: rebuild only when a token is actually missing, so we never
# churn the file needlessly.
if [ -r "$SECRETS" ]; then
  set -a
# shellcheck disable=SC1090
. "$SECRETS" 2>/dev/null
set +a
  cred="$HOME/.git-credentials"
  want_gl="${GITLAB_TOKEN:-${GITLAB_PAT:-}}"
  need=0
  [ -n "$want_gl" ]        && ! grep -qF "$want_gl"        "$cred" 2>/dev/null && need=1
  [ -n "${GITHUB_TOKEN:-}" ] && ! grep -qF "${GITHUB_TOKEN}" "$cred" 2>/dev/null && need=1
  if [ "$need" = 1 ]; then
    umask 077
    { [ -n "$want_gl" ] && printf 'https://oauth2:%s@gitlab.com\n' "$want_gl"
      [ -n "${GITHUB_TOKEN:-}" ] && printf 'https://cheshirecode:%s@github.com\n' "$GITHUB_TOKEN"
    } > "$cred"
    chmod 0600 "$cred"
    note "rewrote ~/.git-credentials (hosts: $(sed -E 's#.*@##' "$cred" | tr '\n' ' '))"
  fi
fi

# Vault: ~/.vault-token is on the overlay, so a restart destroys it and the next
# `super` command falls back to interactive OIDC (which cannot complete without
# a human pasting a callback URL). The tokens in .env.secrets are on the
# persistent volume, so seed the file from them instead of logging in again.
#
# Renewal extends the SAME token id server-side, so the stored string stays
# valid and never needs rewriting. But renewal is capped at issue+768h (32d) --
# `period` is unset on these tokens, so `explicit_max_ttl: 0` does NOT mean
# uncapped. Past that ceiling only a fresh OIDC login helps; this reports the
# date rather than pretending to fix it.
#
# Network-guarded: one stamp file per day, tight timeouts, always exits 0.
VAULT_STAMP="${VAULT_STAMP:-/workspace/.vault-renew-stamp}"
VAULT_RENEW_BELOW_DAYS="${VAULT_RENEW_BELOW_DAYS:-7}"
VAULT_CEILING_WARN_DAYS="${VAULT_CEILING_WARN_DAYS:-14}"
VAULT_PROD_ADDR="https://vault-production.production-eks-private.internaldns-snaptravel.com"
VAULT_STAGING_ADDR="https://vault-staging.private.staging.superinc.net"

vault_ttl() {  # vault_ttl <addr> <token> -> ttl seconds on stdout, empty on failure
  curl -sS --max-time 8 -H "X-Vault-Token: $2" "$1/v1/auth/token/lookup-self" 2>/dev/null \
    | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["data"]["ttl"])
except Exception: pass' 2>/dev/null
}

vault_renew() {  # vault_renew <addr> <token> <label>
  local ttl days human granted
  ttl=$(vault_ttl "$1" "$2")
  if [ -z "$ttl" ]; then note "vault $3: unreachable or token rejected"; return 0; fi
  days=$(( ttl / 86400 ))
  if [ "$days" -lt 2 ]; then human="$(( ttl / 3600 ))h"; else human="${days}d"; fi

  if [ "$days" -lt "$VAULT_RENEW_BELOW_DAYS" ]; then
    # Ask for more than the ceiling can grant; the GRANTED value names the cap.
    granted=$(curl -sS --max-time 8 -H "X-Vault-Token: $2" -X POST -d '{"increment":"768h"}' \
      "$1/v1/auth/token/renew-self" 2>/dev/null \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["auth"]["lease_duration"])
except Exception: pass' 2>/dev/null)
    # Require a MATERIAL gain: at the ceiling, renew-self still returns a
    # lease a few seconds longer than the decayed TTL, which would otherwise
    # print "renewed 31d -> 31d" and read as success.
    if [ -n "$granted" ] && [ "$granted" -gt "$(( ttl + 3600 ))" ] 2>/dev/null; then
      note "vault $3: renewed $human -> $(( granted / 86400 ))d"
      ttl="$granted"; days=$(( ttl / 86400 ))
    fi
  fi

  # The reminder. Renewal cannot move expiry past creation+768h (period is
  # unset on these tokens), so once the remaining life is short, renewing is
  # no longer the fix -- a fresh interactive OIDC login is, and that needs a
  # human. This fires on every session start inside the window, which is why
  # no separate scheduler is needed: the daily run IS the reminder.
  if [ "$days" -lt "$VAULT_CEILING_WARN_DAYS" ]; then
    note "vault $3: EXPIRES $(date -u -d "+$ttl seconds" +%F) (${days}d left) and renewal no longer extends it -- needs an interactive OIDC login (human in the loop; see worklog vault-daily-startup)"
  fi
}

if [ -n "${VAULT_TOKEN_PROD:-}${VAULT_TOKEN_STAGING:-}${VAULT_TOKEN_PROD_BACKUP:-}" ]; then
  # Seed the file super/hvac reads. hvac checks $VAULT_TOKEN then this path and
  # nothing else, so VAULT_TOKEN_PROD is not picked up by name.
  vt="$HOME/.vault-token"
  if [ ! -s "$vt" ]; then
    # Prefer the primary; fall back to the spare so a revoked or removed
    # VAULT_TOKEN_PROD does not cost a human OIDC login.
    seed_from=""
    [ -n "${VAULT_TOKEN_PROD:-}" ]        && seed_from=VAULT_TOKEN_PROD
    [ -z "$seed_from" ] && [ -n "${VAULT_TOKEN_PROD_BACKUP:-}" ] && seed_from=VAULT_TOKEN_PROD_BACKUP
    if [ -n "$seed_from" ]; then
      umask 077; printf '%s' "${!seed_from}" > "$vt"; chmod 0600 "$vt"
      # Restoring a file is not the same as restoring a working credential.
      # A revoked or expired stored token would OTHERWISE install silently and
      # only fail later, inside whatever command needed it -- so verify it here,
      # in this run. The two arms below are the whole outcome: a dead token
      # takes the failure arm and the success line is never printed. There is no
      # window in which a bad seed looks fine.
      if [ -n "$(vault_ttl "$VAULT_PROD_ADDR" "${!seed_from}")" ]; then
        note "seeded ~/.vault-token from $seed_from (overlay wipe)"
      else
        note "seeded ~/.vault-token from $seed_from BUT IT DOES NOT AUTHENTICATE -- needs an interactive OIDC login"
      fi
    fi
    unset seed_from
  fi

  # Once per day: the daily lease is 24h, so more often is wasted network.
  if [ "$(cat "$VAULT_STAMP" 2>/dev/null)" != "$(date -u +%F)" ]; then
    [ -n "${VAULT_TOKEN_PROD:-}" ]    && vault_renew "$VAULT_PROD_ADDR"    "$VAULT_TOKEN_PROD"    prod
    [ -n "${VAULT_TOKEN_STAGING:-}" ] && vault_renew "$VAULT_STAGING_ADDR" "$VAULT_TOKEN_STAGING" staging
    date -u +%F > "$VAULT_STAMP" 2>/dev/null || true
  fi
  unset vt
fi

# glab hangs ~2min on ssh; there is no SSH auth on this box.
if command -v glab >/dev/null 2>&1; then
  [ "$(glab config get git_protocol 2>/dev/null)" = "https" ] \
    || { glab config set git_protocol https --global >/dev/null 2>&1 && note "glab -> https"; }
fi

[ "$changed" = 0 ] && echo "restore-home-links: nothing to do"
exit 0
