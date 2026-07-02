#!/usr/bin/env bash
# Preview Slack-derived worklog enrichments from a captured/provider result set.
#
# Live Slack access is provider-specific. This helper owns deterministic
# matching, redaction, and worklog-shaped preview output; agent skills may feed
# it connector results, and shell users may feed it an exported JSON fixture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
usage: scrape-slack.sh [--input=<slack-results.json>] [--format=json|markdown]
                       [--ldap=<ldap>] [--threshold=N] [--apply] [--commit]
                       [--include-dms] [--include-mpims]

Preview worklog task enrichments from Slack conversations reachable by the
current clone identity. Default is dry-run JSON and performs no writes.

Identity/coverage:
  Run from the target worklog clone or under `direnv exec <clone> ...`.
  Identity resolves per clone: WORKLOG_LDAP, WORKLOG_NS, git email, USER.
  The command is workspace-agnostic: it only processes Slack workspace(s) the
  resolved identity/provider can access. If no provider/input is available, it
  exits 0 with status=unavailable and writes nothing.

Input fixture shape:
  {
    "workspace": {"id": "T1", "name": "example"},
    "messages": [
      {
        "permalink": "https://example.slack.com/archives/C1/p123",
        "channel": "C1",
        "ts": "123.456",
        "thread_ts": "123.456",
        "surface": "public|private|dm|mpim",
        "text": "mentions slug / ENG-123 / PR #456",
        "summary": "durable decision or blocker"
      }
    ]
  }

Flags:
  --input PATH       captured Slack result JSON; stdin is supported with "-"
  --format FORMAT   json (default) or markdown
  --ldap LDAP       override resolved worklog namespace for ownership checks
  --threshold N     minimum score for editable match (default: 80)
  --apply           mutate task files: add external_refs + ## Notes from Slack
                    section for edit_candidate proposals (own-namespace, active,
                    non-duplicate, unambiguous, score>=threshold). Preview is still
                    emitted in the same JSON. Does not commit on its own.
  --commit          implies --apply, then pipes checkpoint_batch to
                    checkpoint-batch.sh for an atomic commit with trailers.
                    Prints commit summary instead of full JSON. Run without
                    --commit first to preview matches.
  --include-dms     allow DM-surface fixture entries
  --include-mpims   allow MPIM-surface fixture entries
  --no-env          disable env/API provider even if SLACK_BOT_TOKEN is set

Env/API provider:
  If SLACK_BOT_TOKEN (or SLACK_TOKEN) is set in the environment (e.g. via
  .envrc) and no --input is given, the helper calls Slack search.messages
  for each active task slug. No hardcoded workspace — discovers via auth.test.
  Rate-limited (0.5s between API calls). Token is never logged or written.
EOF
    exit 0
    ;;
esac

# Parse for --commit: if present, strip it, add --apply, chain to checkpoint-batch.
COMMIT=0
PY_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--commit" ]]; then
    COMMIT=1
  else
    PY_ARGS+=("$arg")
  fi
done

if [[ "$COMMIT" -eq 1 ]]; then
  # --commit implies --apply
  PY_ARGS+=("--apply" "--format=json")

  # Run python, capture stdout.
  OUTPUT="$(python3 "$SCRIPT_DIR/_scrape_slack.py" "${PY_ARGS[@]}")"
  RC=$?

  # If python failed (e.g. --apply refused), pass through its output + exit code.
  if [[ $RC -ne 0 ]]; then
    printf '%s\n' "$OUTPUT"
    exit $RC
  fi

  # Extract checkpoint_batch and pipe to checkpoint-batch.sh if non-empty.
  BATCH="$(printf '%s\n' "$OUTPUT" | python3 -c "import sys,json; b=json.load(sys.stdin).get('checkpoint_batch',[]); print(json.dumps(b) if b else '')")"

  if [[ -n "$BATCH" ]]; then
    printf '%s\n' "$BATCH" | "$SCRIPT_DIR/checkpoint-batch.sh" 2>&1
  else
    echo "scrape-slack --commit: no edit_candidate proposals to commit (all proposal-only/duplicate/unmatched)"
  fi
else
  exec python3 "$SCRIPT_DIR/_scrape_slack.py" "$@"
fi
