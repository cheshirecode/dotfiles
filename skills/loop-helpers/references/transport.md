## Transport gate

Ask the helper for a decision before invoking Caveman. The caller supplies the
facts that cannot be inferred safely from a filename: authorization, measured
win, recovery, producer-status preservation, density, and model legibility.

```bash
python3 <skill-dir>/scripts/transport_gate.py \
  --mode pixel --authorized --measured-win --recoverable \
  --dense --legible --model "<model>"
```

`decision=use` is permission to run the chosen documented command. Any
`decision=skip` keeps the original bytes and records the reason. The helper
**always exits 0** in both the use and the skip case: parse `decision=` from
stdout, never gate on exit status.

Each mode has one extra requirement and the flag that satisfies it:

- `shrink` — producer status preserved: `--producer-status-preserved`
- `convert` — an installed copy exists: `--installed-copy`
- `pixel` — a dense, legible payload for a configured model: `--dense
  --legible --model <id>`

`CAVE_PIXEL_MODELS` is the comma-separated allowlist of model ids that read
pixel payloads, and it is a real Caveman variable: the CLI applies it to
`think.pixel.models`. It defaults here to `claude-fable-5,gpt-5.6`; both are
current ids that Caveman's engine recognises, so the defaults are usable as
they stand. Add the ids actually in use rather than replacing them:
`CAVE_PIXEL_MODELS="<id>,<id>"`. An unlisted `--model` returns
`decision=skip reason=model-not-configured hint=set-CAVE_PIXEL_MODELS`.

**`decision=use` is not sufficient on its own.** Caveman ships pixel *off*:
`think.pixel.models` is `[]` by default, and an empty list passes no allowlist
to the proxy at all. This gate answers "should we attempt pixel", using its own
list; Caveman must be configured separately or it will not pixel whatever this
returns. `caveman tools config set` also accepts an unknown model id without
complaint, so a typo there is caught by nothing — this gate's `skip` is the
only place a wrong id is reported.

For the historical CLI probe and version, read [pixel-verification.md](pixel-verification.md) when diagnosing model recognition.

The helper never claims a token saving is verified: the caller supplies
measured evidence.
