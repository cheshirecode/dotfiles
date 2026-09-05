You're picking up a task cold. Assume no prior session memory.

Project root: <workspace>
Relevant repos:
  - <workspace>/dotfiles

Read these first:
  - <dotfiles-checkout>/skills/pr-cost/SKILL.md
  - <dotfiles-checkout>/skills/pr-cost/INSTALL.md

Task:
  Comment the **Claude Code** AI cost for this PR onto the PR itself. Do not
  change product code. Do not rewrite the PR body.

  1. Resolve the PR URL (this dogfood PR):
     `https://github.com/cheshirecode/dotfiles/pull/31`
     or `gh pr view 31 --repo cheshirecode/dotfiles --json url -q .url`
  2. Find this Claude session JSONL. Prefer `$CLAUDE_PROJECT_DIR` transcripts
     under `~/.claude/projects/` matching cwd `dotfiles` or the current
     session id. If several files match, use the one whose `sessionId` matches
     this conversation.
  3. Run:
     `python3 <dotfiles-checkout>/skills/pr-cost/scripts/claude_session_usage.py --jsonl <that-file>`
  4. Live-annotate (this is an explicit write to GitHub):

```bash
export VIRTUAL_ENV=
# PATH: rely on the invoking shell; no machine-specific prefixes.
export PR_COST_HOOK_LIVE=1
PR_URL="$(gh pr view 31 --repo cheshirecode/dotfiles --json url -q .url)"
USAGE="$(python3 <dotfiles-checkout>/skills/pr-cost/scripts/claude_session_usage.py --jsonl "$JSONL")"
python3 <dotfiles-checkout>/skills/pr-cost/scripts/pr_cost_collect.py annotate \
  --harness claude \
  --confidence estimated \
  --usd "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["usd_estimated"])' <<<"$USAGE")" \
  --tokens-in "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tokens_in"])' <<<"$USAGE")" \
  --tokens-out "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tokens_out"])' <<<"$USAGE")" \
  --model "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["model"] or "claude")' <<<"$USAGE")" \
  --session-id "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["session_id"] or "unknown")' <<<"$USAGE")" \
  --window-start "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["window_start"])' <<<"$USAGE")" \
  --window-end "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["window_end"])' <<<"$USAGE")" \
  --pr-url "$PR_URL" \
  --notes "Claude Code session usage summed from unique assistant message.usage on the JSONL. Cache read/write included in tokens_in. USD uses default Opus-class rates in claude_session_usage.py."
```

  Privacy: do not paste prompts, diffs, or file contents into the PR comment.
  The collector already wraps a JSON payload. If annotate reports
  `"status": "duplicate"`, stop — the Claude cost is already on the PR.

Deliverable:
  One PR comment from harness=claude. Print the annotate JSON and the comment
  URL. Do not push or open extra PRs.
