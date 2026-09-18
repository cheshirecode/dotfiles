# Validate native harnesses

Use this optional development kit when another session needs to validate native
Claude Code, GPT/Codex or OpenCode execution, verifier access and usage receipts.
It adds no scheduler, plugin installation or global configuration. Ordinary
factory work remains on [factory.md](factory.md).

## Scope and evidence

The adapters were extracted from the isolated autoresearch factory study at
research revision `92c1605525d2bf829ec9d5cf1b670ac52e4137e7`. They invoke the
installed native CLIs, preserve operational events and reconcile native usage.
They do not call a replacement API client or treat model prose as verification.

On the development macOS host, one paired workflow repair passed all eight
independent checks in each harness. The candidate's token/time changes were
OpenCode -0.3%/-2.5%, Claude +38.1%/+15.5%, and Codex -10.7%/+57.2%.
This single-case screen establishes neither broad reliability nor portable
savings. No held-out confirmation trial has run. Text-as-image transport remains
a research proposal; these adapters accept text only.

The implementation uses Python's standard library, Git, Unix process groups and
the installed CLI. Python 3.9+ is required. Live validation currently covers
macOS; Linux needs its own run. Native Windows process cancellation is not
implemented. Passing mocked/unit controls on another OS is not live support.

The packaged smoke command passed on 2026-09-17 with Codex CLI
`0.155.0-alpha.2.6`, Claude Code `2.1.274` and OpenCode `1.18.31`: four named
checks, one public-verifier call and complete usage in each lane. The 41 offline
controls also passed under Python 3.9 and 3.14. Recheck on your host; these are
observations, not minimum-version promises or savings measurements.

A second host confirmed the Claude lane on Claude Code `2.1.275` with
`claude-haiku-4-5-20251001`: four checks, one verifier call, complete usage.
That run first failed on usage reconciliation, not on the work. Asking for the
model the harness also uses for its own auxiliary calls collapses both into one
`modelUsage` entry, whose totals then exceed `result.usage`; the dated alias and
its `canonicalModel` are also two names for one model. Both are fixed. Prefer a
model your account can use, and read the artifact rather than the exit code
alone when a run fails: the four checks and the usage verdict fail separately.

## Validate after pulling

Fetch/reconcile the latest dotfiles revision in your own worktree. Keep other
sessions' dirt and refs intact. Run from that checkout so you test its code,
not an older installed skill. No skill refresh or plugin install is necessary.
Use the user's shell environment; on macOS load `~/.zshrc` before commands
that need the user-installed CLI/Node toolchain.

Offline controls make no model calls and need no credentials:

```bash
PYTHONPATH="$PWD/skills/loop-engineering/scripts/native_harness" \
  python3 -m unittest discover \
  -s skills/loop-engineering/tests/native_harness -p 'test_*.py'
/bin/bash tests/run.sh static
```

Live smoke tests consume account quota/provider credit. Run only within the
user's authorized validation scope and budget. Choose one installed harness and
an exact model from its available catalog; do not copy a model name that your
account cannot use. There is no default model or automatic fallback. Astra is
excluded from this research and rejected before a native model process starts.

```bash
python3 skills/loop-engineering/scripts/native_harness/validate.py \
  --harness codex --model '<exact-non-Astra-model-id>' --seconds 180
```

Use `--harness claude` with an explicit `claude-...` ID, or `--harness opencode`
with `openrouter/<provider>/<model>`. The command prints a result artifact path
in private temporary storage; `--output <new-directory>` chooses another path.
Each invocation creates a fresh disposable Git repo with synthetic JSON, asks
the worker for one scoped edit and a public verifier call, then independently
grades all four named checks, write scope, Git identity, timing and usage.
Exit 0 requires all of them. Missing tool access, empty coverage, partial usage,
rerouting and timeouts are failures. Keep failed artifacts; do not replace them
with a successful retry or remove failed costs from a comparison.

## Authentication and isolation

Claude and Codex use their existing native authentication. The OpenCode adapter
reads only the `OPENROUTER_API_KEY` assignment in `~/.env.secrets`, parsing it
without executing the file, and passes the value in the child environment. It
does not print or persist the value, pass it in arguments, or write it to a
configuration file. Never paste a key into a prompt, command argument or receipt.
OpenCode output is redacted before retention; its full session export is not
persisted. Treat retained local receipts as private and review before sharing.

Claude uses an explicit temporary MCP configuration, removes it on close and
excludes ambient settings. OpenCode uses process-local configuration and `--pure`;
the preflight requires exactly the scoped factory verifier to be connected.
Other enabled MCP servers cause failure; resolve that through scoped settings,
not by deleting the user's global configuration. Neither lane delegates work.
The verifier is local, authenticated and accepts only its named empty-argument
tool call. It is controller-side evidence, not worker-side execution.

These permissions and final-state checks are not an adversarial OS sandbox.
Shell access remains available to repair agents; the kit is for trusted,
synthetic work orders, not untrusted repositories or secret-bearing fixtures.
No automatic login, credential rotation, billing change or global skill mutation
is part of validation.

## Report to the accepting session

Send the exact dotfiles revision, OS/Python/CLI versions, harness, requested and
observed model, command exit, four named checks, public-verifier call count,
scope/Git verdict, usage completeness, both clocks and artifact path. Report
unavailable prerequisites explicitly; a skipped lane is not a passing lane.
Share a sanitized summary rather than uploading raw events. For example:

```text
revision=<sha>; host=<os/python/cli>; harness=<name>; model=<requested/observed>
exit=0; checks=4/4; verifier_calls=1; scope=pass; git=unchanged
usage_complete=true; timing_valid=true; artifact=<private local result.json>
```

Token categories vary by provider. Codex cache reads are a subset of input;
Claude totals include reported auxiliary-model usage; OpenCode stream steps must
agree with a sanitized native export. Unknown or inconsistent fields never
become zero. Provider-reported dollar amounts are estimates, not billing proof.
Interrupted usage remains incomplete/lower-bound evidence. A passed smoke test
permits further validation; it does not establish savings or factory quality.

The shared adapter interface is `start(workspace, developer_instructions,
public_verifier)`, `turn(prompt, seconds=...)`, then `close()` in a `finally`
block. Keep acceptance outside the worker's write scope. Preserve source hashes,
complete check names and model/usage receipts when building your own work orders.
Do not reuse the synthetic smoke task as an independent reliability sample.
