# Applying the patterns to the Docker sandbox

This is a preparation note for the session owning `cheshirecode/sandbox`, not
an implemented feature. Read-only inspection on 2026-09-18 found clean revision
`c976182c900b7a3f434fdbc2f714d0399849f5b6`. Resolve the repo from that session's
workspace; `../sandbox` relative to a dotfiles worktree may not be the clone.
Refresh its `AGENTS.md`, `README.md`, lifecycle skill and current Git state.

## Fit and smallest candidate

This repo runs an ephemeral Docker development environment with CLI lifecycle
operations and persisted run receipts. It is not Impresspress's browser-local
site builder. No browser workspace UI was identified in the reviewed entry
points. The existing WhatsApp bridge is unrelated; do not repurpose its server
or authentication as a sandbox control plane without a separate design need.

If a browser workspace is an explicit user need, start with a read-only view of
one selected sandbox profile and one selected run. Possible tool contracts are
`sandbox_status(profile_id)` and `sandbox_run_result(profile_id, run_id)`.
These names are proposed, not existing APIs. Adapt existing `status` output and
the `run-headless` receipt files; select permitted profiles and runs server-side,
return bounded redacted data, and reject traversal or cross-workspace access.

Only add a run trigger when requested: accept a configured check identifier and
project identifier mapped to a fixed command, timeout and runtime user. Do not
expose `exec`, arbitrary command strings, free-form environment variables, raw
Docker requests or a browser-accessible Docker socket. Keep authentication,
origin/CSRF checks and authorization on any local bridge; loopback alone does
not make a browser caller trusted.

The repo's own adoption criteria require a real observed pain and proportionate
cost. If no browser workflow is needed, stop with an assessment: stronger typed
receipts or stale-state checks may be useful independently, but WebMCP does not
justify adding an otherwise unused web service. Do not port the Rust/WASM
compiler, OPFS storage, public demo credentials or shop/payment tools.

## Preserve the existing isolation contract

Read the target's current instructions for the exact implementation. The
reviewed contract uses a non-root `dev` container user, credential transfer via
tmpfs instead of Docker environment/build arguments, HTTPS Git without SSH-agent
forwarding, and separate identity rules for personal and work-repo operations.
The generated egress policy has its own source and sync helper. A tool adapter
must preserve these boundaries rather than independently recreating credentials,
mounts, policy or lifecycle behavior.

Use stable profile/run identity and existing receipts to distinguish queued,
running, exited and unknown states. A successful launch is not a successful
test. If adding concurrent file writes later, adapt expected-hash preconditions;
do not add a generation/rollback system before the repo needs one. Starting,
stopping and deleting containers or volumes have different effects and must
remain separate operations within the user's authorized scope.

## Acceptance for the owning session

Verify read-only queries leave files/container state unchanged. Check denied
profile/run IDs, bounded output and redaction. For an authorized run trigger,
verify the configured command runs as `dev`, timeout and nonzero exit survive
into the receipt, and retry/status behavior cannot launch duplicate work.
Run the repository's required checks and real-repo dogfood path; a dotfiles
skill validation is not a sandbox runtime pass. Coordinate cleanup with other
container users and follow the target's commit/delivery rules.

Suggested initial invocation: `Use $webmcp-integration to assess a read-only
browser view of sandbox status and run receipts in this repo. Identify the
existing owners and missing prerequisites; do not build or start services.`
