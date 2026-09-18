---
name: webmcp-integration
description: Add or assess page-scoped WebMCP tools in an existing application or development workspace. Use for WebMCP adoption and impresspress-inspired sandbox improvements; browser CLI installation belongs to browser-use-setup.
---

# WebMCP integration

Work in the invoking session's target repository. Follow its instructions,
runtime, authentication and delivery workflow. A request to prepare a skill or
assess a design authorizes that artifact; implement the target integration only
when the user's task includes implementation.

## Establish fit

Resolve the intended repo and current revision before editing. Inspect its
existing UI, typed routes, permission checks, job lifecycle and verification
commands. Identify one concrete user operation and its observable success state.
WebMCP supplies a browser-facing tool surface; it does not supply a backend,
an OS sandbox or access to Docker on its own.

For an existing web UI, expose a small useful action through existing application
logic. For a CLI-only repo, first establish why it needs a browser-facing workflow;
do not introduce a web server just to register tools. If that need is missing,
return a scoped adoption proposal with the missing prerequisite.

Read [impresspress.md](references/impresspress.md) for the upstream patterns and
compatibility caveats. For the Docker sandbox use case, also read
[sandbox.md](references/sandbox.md); its snapshot is context, not current truth.

## Implement a narrow integration

- Prefer an explicit tool allowlist projected from existing typed operations.
  Keep names, schemas and invocation mappings tied to the same operation owner;
  do not export every API route automatically.
- Reuse the user's session and existing endpoint authorization. A filtered
  manifest and tool annotations aid discovery; neither replaces enforcement.
  Keep invocation destinations same-origin and scoped to the selected project.
- Match the installed browser API. Feature-detect registration, handle its
  asynchronous result, and remove only this integration's registrations on
  navigation, logout or unmount. Use supported cancellation/lifecycle APIs;
  rediscover tools after a context change. Unsupported browsers retain the UI.
- Preserve state semantics: distinguish staged, running, active and failed work.
  Use existing revision/hash preconditions for writes where concurrent edits
  matter. Report failures as failures. After a timeout with unknown outcome,
  inspect operation status before retrying a mutation.
- Keep secrets, host paths and unrelated workspace data out of schemas and
  results. A browser tool must not become an arbitrary shell/Docker executor.

## Verify the user's operation

Use the target repo's tests for schema/handler parity and authorization. Include
the relevant denied role, invalid input, stale revision and failure paths.
Exercise unsupported-browser behavior and registration cleanup when applicable.

In a disposable workspace or approved development instance, discover the actual
tools, execute the chosen operation, and verify UI plus persisted state or job
receipts independently. Pin the origin and tab before each action. Record browser
version, native versus polyfilled API, tool arguments with secrets removed,
outcome and cleanup. A tool-list probe alone proves only discovery.

For browser connection and discovery, use `browser-use-setup` if installed;
its `references/webmcp.md` and `bin/webmcp-probe.js` provide the tested path.
Otherwise consult the [current Chrome API docs](https://developer.chrome.com/docs/ai/webmcp/imperative-api)
and the session's available browser driver. Do not install a legacy bridge as
a substitute for a missing browser API.

Report what was assessed, implemented and actually exercised, with concrete
evidence and remaining prerequisites. Keep savings claims separate: they need
paired measurements including discovery, failures and verification overhead.

Example: `Use $webmcp-integration in this repo to expose the existing preview
status operation, then verify it in the development UI.`
