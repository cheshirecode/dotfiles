## What
<!-- One-paragraph summary. What changed and why. -->

## Karpathy checklist
<!-- Apply karpathy-guidelines. Tick honestly. -->

- [ ] **Think Before** — assumptions surfaced; multiple interpretations named where present.
- [ ] **Simplicity First** — minimum diff that solves the asked problem; no speculative abstractions; no error handling for impossible cases.
- [ ] **Surgical Changes** — every changed line traces to the PR's stated scope; no drive-by refactors; matching existing style.
- [ ] **Goal-Driven** — for new guardrail/behavior: red-path fixture in `tests/run.sh` (or commit body cites the verify-command + exit code).

## Verification evidence
<!-- Paste actual command output, not "ran it locally". -->

```
$ ./tests/run.sh all
$ ./bin/doctor.sh | tail -3
…
```

## Risks / follow-ups
<!-- What might break? What did you intentionally defer? -->
