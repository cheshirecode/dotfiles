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

**Prefer `--payload <path>` over `--dense`.** Density is measurable, so the
helper measures it instead of taking the caller's word. An image costs
`width*height/750` tokens, and for monospace text that is
`chars * char_width * line_height / 750` — so cost per character is a constant
per font size, divided by the *fill ratio*: the share of the bounding box that
is really text, since one long line sets a width every short line then pays for.
Against a text baseline of 0.25 tokens/char the payload must fill at least
0.42 of the box at size 10, or 0.81 at size 14; above size 15 no payload can win.
Measured on this repo: uniformly wrapped prose 0.74, a shell/test log 0.58, Python
source 0.33, a worklog task 0.26.

`--payload` refuses three shapes a density number alone would wave through:

- **Machine-parsed data** (`payload-machine-parsed`) — JSON re-parsed after
  reading must survive byte-exactly, and structured data whose fields hold prose
  scores well on both density and identifier share. A truncated or streamed
  fragment does not parse at all, so it is refused too
  (`payload-structured-unparseable`) rather than waved through.
- **Identifier-dense payloads** (`payload-identifier-dense`) — hex runs, base64,
  flags, screaming-snake names, URLs and backticked code. One wrong glyph there
  is unrecoverable and undetectable, and these score *best* on density, so the
  two gates pull against each other.
- **Ragged payloads** (`payload-not-dense`) — reported with the measured
  `fill=`, `need=`, `cols=` and `lines=` so the verdict can be checked.

Every threshold is a flag: `--font-size`, `--char-width-ratio`,
`--line-height-ratio`, `--text-tokens-per-char`, `--max-identifier-share`. The
width and height ratios are measured against DejaVu Sans Mono; override them for
another face.

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

When diagnosing model recognition, inspect the installed CLI help and compare
`caveman-engine pixel simulate --model <id>` with an unknown-id control. A command
accepting an id does not prove recognition; record the current tool version and
observed geometry before claiming support.

The helper never claims a token saving is verified: the caller supplies
measured evidence.
