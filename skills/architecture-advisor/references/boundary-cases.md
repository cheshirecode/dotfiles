# Boundary cases for reviews

These are anonymized patterns, not architecture prescriptions or current capacity
claims. Use them to form questions, not to substitute for inspecting the system.

## Move work without moving the contract

A static publishing system can generate management HTML before requests arrive,
while the reader still checks fresh authorization and serves identity/CSRF state
dynamically. A frontend bundler need not become an HTML server. Separate build
artifacts and cache keys by their real owners, and verify clean builds and actual
runtime payloads after a source-tree move. Preserving an authoring workflow is a
separate acceptance condition from improving reader latency.

Immutable assets can be served from a CDN while navigational links remain on an
entry host. A base URL changes how relative links and fragments resolve. Tests
must exercise real browser navigation and preserve labels, CSS strings and JS
program data that merely resemble URLs. Syntactically valid transformed output
can be semantically wrong. Porting a broad literal-rewrite heuristic and matching
its old output does not establish that non-navigation content remains unchanged.
Check the context that owns the value; conservative handling of uncertain program
expressions may be preferable to an increasingly broad replacement rule.

Stage and validate immutable releases before conditional activation. Evaluate
lost responses, concurrent replacement, rollback ownership and old-client asset
retention when changing publication concurrency. Parallelizing work does not
justify parallelizing every state transition or widening permissions.

## Read a benchmark as a conditional observation

A larger per-item work window can help one heavy item use a shared request budget
while worsening balanced-workload tails. Output hashes, request bounds and
conditional-activation tests establish different facts from a runtime reduction.
Local delayed fixtures can test the mechanism; actual stage timing and provider
telemetry are needed to locate the production bottleneck. A merge that selects no
publication does not supply that evidence.

Likewise, one clean warm arrival-rate sample cannot promise burst latency or
recovery after overload. More RAM is not supported by an unproven memory
hypothesis; more CPU is not a substitute for distinguishing client pacing,
downstream waits and bandwidth. Record workload-specific operating points and
uncertain failure attribution instead of promoting a sample into an SLA.
