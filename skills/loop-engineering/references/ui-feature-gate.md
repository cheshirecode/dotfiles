# UI feature gate contract

Use `scripts/ui_feature_gate.py` for one committed, clean source revision. Put
the manifest and output directory in system temporary storage, outside the
worktree. Each command is an argv list run from the repository root; the runner
does not invoke a shell unless the argv explicitly names one. For Node-managed
commands, use the user's login `zsh` environment in that argv.

The manifest requires `revision` (full Git commit ID), `browser` (the user's
main browser), `build` (argv), `preview` (null when inapplicable, otherwise an
object with `verify` argv and optional `deploy` argv), and a nonempty `cases`
list. Each case requires a unique lowercase `id`, `given`, `when`, `then`, a
browser `check` argv, and a unique relative `artifact` path. Example shape:

```json
{
  "revision": "<full-commit-id>", "browser": "Chrome",
  "build": ["zsh", "-lic", "npm run build"],
  "preview": {"verify": ["./scripts/check-preview-revision.sh"]},
  "cases": [{
    "id": "visible-result", "given": "the page is open",
    "when": "the action runs", "then": "the result appears",
    "check": ["./scripts/browser-case.sh", "visible-result"],
    "artifact": "cases/visible-result.png"
  }]
}
```

The preview verification command must inspect the served preview and print the
exact `UI_VALIDATION_REVISION` as a line by itself only when it matches. A
successful deploy command or URL response alone does not satisfy this check.
Include `deploy` only for an authorized deployment, and pass `--allow-deploy`
when running the gate; the flag does not grant deployment permission.

Each case command must exercise and assert its Given/When/Then behavior in the
named main browser. It receives `UI_VALIDATION_REVISION`,
`UI_VALIDATION_BROWSER`, `UI_VALIDATION_CASE_ID`, and
`UI_VALIDATION_OUTPUT_DIR`. Write a nonempty screenshot, trace, or other
browser-observed artifact at the declared path under that output directory.
The runner fails if a command exits nonzero, an artifact is missing or empty,
the revision changes, or the worktree becomes dirty. A fresh output directory
prevents stale artifacts from passing a new run.

The runner writes `result.json` and per-step logs locally, and prints only a
summary and report path. It checks execution and coverage; inspect the browser
test and artifact to judge whether they actually prove the requested behavior.
Record the result and that relevance check in `$evidence-gate` before claiming
completion. If any case cannot run through automation, record its direct browser
observation separately and keep the scripted case unverified.
