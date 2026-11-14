# Measurement and load-test decisions

## Before execution

Reuse existing evidence when it answers the question. For new load, establish the
authorized target/environment, routes and identities, traffic mix, rate/concurrency,
duration, outstanding-request/deadline limits, cost/resource budget, and stop
conditions. Specify who may change configuration and which resources are owned.
A command's remote opt-in flag is not user authorization. If authority is missing,
produce a concrete bounded plan and continue read-only analysis; do not send load.

Prefer isolated fixtures for harness mechanics and isolated representative targets
for capacity experiments. Do not copy private production data to fixtures. Use
existing credential mechanisms/environment variables without logging secrets or
following identity requests to unexpected hosts. Do not create IAM grants or
weaken access to make a benchmark work. Put cancellation, timeout and failure
cleanup in the plan before provisioning; retain enough evidence to diagnose a
failed run, remove only owned temporary resources, verify their absence, and
restore only configuration this task changed. Stop on the agreed error, latency,
resource or cost limit; do not automatically retry an overload until it looks green.

## Design a discriminating comparison

Bind baseline and candidate to source/image/configuration and input hashes. Keep
machine/region, dependency versions, traffic mix, response validation, warmup,
sample duration and scaling policy comparable. Change one causal factor where
practical. Alternate or randomize repeated trials; distinguish fresh/warm,
post-stress recovery, cold start and scale-out. Report grouped-order confounding
or other unavoidable differences rather than claiming causality.

Choose arrival-rate tests for a traffic-rate objective; fixed concurrency is a
different workload and can reduce offered traffic when the service slows. Record
offered, started and completed rates plus missed starts, queue delay, outstanding
requests, deadlines and retries. A concurrency ceiling is neither RPS nor actual
in-flight occupancy. Verify generator CPU/event loop, network, HTTP stream limits,
connection count and body consumption before blaming the server. See the primary
[k6 workload-model explanation](https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/open-vs-closed/)
for coordinated omission; tool choice remains open.

Validate representative full responses and route mix, not just HTTP 200. Separate
transport, application, authorization and validation failures; a mutable security
wrapper may require semantic body validation rather than byte identity. Never
relax a checker until it accepts an actual error page. Match provider logs by
revision/run ID when available; absence of a response from application logs does
not establish which upstream layer failed.

## Interpret and bound the result

Retain trial-level data, sample counts, aggregation method and excluded/interrupted
runs. Compare medians and tail latency, errors, throughput, CPU/memory and relevant
phase timings. Small-sample p95 may just be the maximum; do not invent significance.
Look for heavy-tail workload wins hiding balanced-workload regressions, averages
hiding failures, and successful fresh tests hiding degraded recovery.

Keep these proof boundaries explicit:

| Evidence | Supports | Does not establish by itself |
| --- | --- | --- |
| Loopback/mock fixture | Runner pacing, gates, cancellation, expected synthetic behavior | Real storage latency, quotas, signing, production capacity |
| Isolated fixed-instance service | That image/configuration and workload under measured conditions | Autoscaling, cold starts, fleet diversity, live browser UX |
| HTML-only load | HTML response correctness and latency for tested routes | Asset/video loading, expiry/renewal, rendering or management mutations |
| Controlled local optimization | Candidate behavior and measured local tradeoffs | General or production speedup |
| Deployment or CI success | The selected workflow/checks succeeded | Work actually ran, customer behavior, performance improvement |

Correlate saturation signals, but do not call the highest utilization the proven
bottleneck. Explain what measurement is missing. Provider limits and costs change;
consult primary docs for the chosen platform. For example, Cloud Run's
[concurrency documentation](https://docs.cloud.google.com/run/docs/about-concurrency)
distinguishes configured maxima from admission under CPU pressure. This is an
example, not a recommendation to use that provider or a particular setting.

Finish with a claim no broader than the evidence, an acceptance/reversion gate,
and cleanup results. If raw data was lost, preserve the available summaries and
label the resulting limits on reanalysis.
