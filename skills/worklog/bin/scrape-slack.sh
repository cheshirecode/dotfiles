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
                       [--ldap=<ldap>] [--threshold=N] [--apply]
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
                    emitted in the same JSON. Does not commit; pipe checkpoint_batch
                    to checkpoint-batch.sh to commit with trailers.
  --include-dms     allow DM-surface fixture entries
  --include-mpims   allow MPIM-surface fixture entries
EOF
    exit 0
    ;;
esac

exec python3 "$SCRIPT_DIR/_scrape_slack.py" "$@"
