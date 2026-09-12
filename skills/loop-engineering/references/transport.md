# Optional payload transport

Keep ordinary Markdown, source, diffs, state and evidence as text. Compression
is optional at a noisy tool-output boundary, and requires an authorized installed
tool, usable recovery, preserved producer status and a measured readability/size win.

For Caveman, inspect `command -v caveman` and current help. The CLI and engine are
separate capabilities. Missing tools or engine, an empty result, or `no skills
found` establish no measured saving. Use a real directory copy as a control when
symlink discovery is uncertain. Do not install tooling or change agent configuration
without authorization.

- `caveman tools shrink -- <command>` may reduce repetitive output. Preserve the
  command's original exit status and retain the original artifact/recovery handle.
- [Pixel mode](https://github.com/juliusbrussee/caveman#pixel-mode) is only a candidate
  for dense long-line payloads when the receiving model can read it. Require an
  observed win before `caveman wrap --pixel <agent>`; vision support alone is no proof.
- `caveman tools convert --dry-run` must target copies, never canonical source or
  symlinks into a checkout. Preserve a byte-identical `--revert` path and frontmatter.

On missing capability, failed recovery, no win or declined authorization, pass
bytes unchanged and record `pixel-transport: skipped — <reason>` when the choice
matters. Label size/token estimates inferred until real traffic and an evaluation
verify them. An output-only style skill does not establish input-token savings.
Capture verdict-carrying exit codes before parsing; [examples.md](examples.md)
shows the distinction. Never discard evidence to make the visible output shorter.
