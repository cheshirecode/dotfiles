# Impresspress patterns to adapt

Inspected 2026-09-18 at upstream revision
`fb781f01bfa1b36a216f5e08178740c12c4643ae`. These are source observations, not a
deployment audit or a recommendation to replace the target's stack. Refresh
upstream and browser compatibility before implementation.

## Select tools from existing contracts

Impresspress projects selected typed HTTP endpoints into a visitor-filtered
manifest. Its frontend maps declared path, query and body parameters into a
same-origin request; the endpoint still checks authorization. Non-success HTTP
responses become explicit tool errors. Adapt that ownership pattern to the
target's existing router/schema system. Avoid introducing a second independent
schema or a new backend solely to emulate Impresspress.

Sources: [manifest registration](https://github.com/impresspress/impresspress/blob/fb781f01bfa1b36a216f5e08178740c12c4643ae/crates/impresspress-core/src/ui/assets/webmcp.js),
[request adapter](https://github.com/impresspress/impresspress/blob/fb781f01bfa1b36a216f5e08178740c12c4643ae/crates/impresspress-core/src/ui/assets/webmcp-core.js),
[curated dev tools](https://github.com/impresspress/impresspress/blob/fb781f01bfa1b36a216f5e08178740c12c4643ae/crates/impresspress-core/src/blocks/dev/tools.rs).

## Preserve edits and expose activation state

The browser-local workspace uses expected file hashes to reject stale edits.
It records generations and implements rollback by appending a new generation.
Mutating operations expose progress through activation; source staging and
publication are different states. These are useful patterns for an existing
preview/build workflow, with limits and terminology chosen by its owner.

Its service worker, OPFS storage and in-browser Rust/WASM compiler solve a
different deployment problem from a Docker dev container. Browser-local storage
is not a drop-in implementation of host credential or process isolation. The
documented throwaway administrator credentials depend on that disposable local
instance; do not copy them into a host service or exported deployment.

Source: [dev sandbox behavior and limits](https://github.com/impresspress/impresspress/blob/fb781f01bfa1b36a216f5e08178740c12c4643ae/docs/dev-sandbox.md).

## Adapt lifecycle code rather than copying it

The inspected registration script attempts `unregisterTool` when available.
Current Chrome documentation describes registration lifetimes using
`AbortSignal`; copying the older conditional cleanup can leave stale tools.
Likewise, invocation argument and result shapes depend on the actual API and
browser version. Verify the intended contract, including error handling, on
the target runtime before choosing an adapter.

Impresspress also distinguishes an active service worker from one controlling
the document. If a manifest is served through a service worker, check actual
control before fetching it and validate the response format; a successful HTML
fallback is not a JSON manifest. Apply this only to service-worker deployments.

Sources: [registration lifecycle and worker control](https://github.com/impresspress/impresspress/blob/fb781f01bfa1b36a216f5e08178740c12c4643ae/crates/impresspress-core/src/ui/assets/webmcp.js),
[current browser API](https://developer.chrome.com/docs/ai/webmcp/imperative-api).

The similarly named [webmcp.dev implementation](https://github.com/jasonjmcghee/WebMCP#readme)
is an earlier widget/local MCP bridge. Its author explicitly distinguishes it
from the current specification. It is not the dependency this skill prescribes.
