# Host and operating-system capabilities

Model identity does not establish tool availability, filesystem isolation,
synchrony, cwd persistence or recurrence. Inspect the active tool schemas and
verify the selected target. Use the same state/evidence contract on every host.

## Session capability check

| Capability | Establish | If unavailable |
| --- | --- | --- |
| Shell and Python | Interpreter path/version and actual cwd | Manual five-field state, labelled non-deterministic; no CLI verification claim |
| Git and Bash | Repo root/remote; Bash required by crew tools | State-only loop; report unavailable radar |
| Delegate dispatch | Current callable tool, permissions and sync/async behavior | Execute authorized work in-band |
| Worker isolation | Separate code worktree/sandbox and correct repo per worker | Read-only parallel workers; parent is single writer |
| Roster/messages/wait | Actual supported operations and worker identities | Parent tracks returns explicitly; do not invent mailbox tools |
| Durable context | Verified Worklog environment or authorized store | Explicit local fallback and recovery limitation |
| Recurrence | Authorized scheduler created and confirmed, with stop rule | `needs_human` when later execution is required |

Use an event wait only when work depends on a pending result; otherwise continue
independent work. A synchronous dispatch blocks its caller. A mailbox wait does
not observe files. On any host, code isolation leaves shared Worklog serialized.

## Host discovery hints

These are candidates to inspect, not guaranteed APIs:

| Host | Skill roots | Dispatch and tracking candidates |
| --- | --- | --- |
| Codex | `~/.agents/skills/`, `~/.codex/skills/` | `spawn_agent`, `list_agents`, `send_message`, `followup_task`, `wait_agent`, `interrupt_agent`; without an isolation option, delegates share files |
| Claude Code | `~/.claude/skills/` | Agent and task tracker; if `isolation: "worktree"` is supported, request it and verify worker root/remote before writes |
| Cursor | `~/.agents/skills/`, `~/.cursor/skills/`, project skill roots | Exposed todos/subagents; verify isolation |
| OpenCode | Project-configured roots or repo `skills/` | `task` with exposed subagent types; inspect synchrony and resume support |

Resolve the loaded directory first; [resolvers.md](resolvers.md) carries tested
fallback commands. Do not infer a dispatch directory from `loop_run.py --repo`.
A worker checks `git rev-parse --show-toplevel`, expected source paths and
`git remote get-url origin`; mismatch stops that worker before edits.

## OS verification

Python state/driver commands and Bash crew tools have different prerequisites.
Run Bash examples with Bash rather than the login shell. Keep paths quoted and
use `mktemp -d` or the host's temporary-directory API; do not assume GNU utilities.

| Environment | Verification scope |
| --- | --- |
| macOS | Python CLI and `/bin/bash` fixtures, including Bash 3.2 behavior |
| Linux | Same source and checks under the image's Python/Bash; record architecture |
| Windows | Python commands may use `py -3`; Bash/Git crew checks require a verified WSL or compatible shell environment. Native PowerShell support is unverified until exercised |

For a sibling sandbox, read its instructions, use the required non-root user,
and test an identified source snapshot. Preserve shared containers and avoid
forwarding credentials for offline fixtures. Record OS, architecture, interpreter,
source identity, commands and exit status. Container tests prove that environment;
they do not prove a model ran, a different architecture passed, or Windows works.

## Recurrence

The driver is pull-only. Discover the current host's automation, scheduled task
or hook only when later execution is requested. End `continue_scheduled` only
after verifying an authorized wakeup. Without it, use `needs_human` with the
missing capability and replay action. A prompt cannot manufacture a scheduler.
After a wakeup, use a bound successor and replay the stopping check.

An optional watch fingerprint must cover independent changes it claims to
observe: worker identity/status, inbox and conflict verdict. Re-arm and verify
the watcher after host restarts; a quiet or missing sensor is not health evidence.
Keep monitoring bounded and report changes rather than repeating unchanged rows.

## Installation

Keep this skill as the canonical source. Inspect `scripts/install_audit.py --help`
before consolidation. `--canonical <skill-dir> --link-identical` replaces only
identical copies; any divergent root rejects all writes. Check `--root <dir>
--dry-run` before an authorized `--apply`; nonstandard roots must be explicit.
Exit 0 is clean, 2 usage error, 3 divergence. Installation permission is separate
from permission to edit source. Never overwrite a divergent installed copy.
