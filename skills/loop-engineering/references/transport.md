# Optional payload transport

At a provider or tool-output boundary, choose a capability-gated,
fail-open, recoverable representation. Measure after selection; if the result
is not both smaller and more legible, send the original bytes.

1. For noisy command output or tool catalogs, an authorized Caveman install may
    use `caveman shrink -- <command>` before using Caveman Pixel Mode. Preserve producer status with
   `set -o pipefail`; keep the original in an artifact store (`/tmp`,
   `$TMPDIR`, or your harness's upload area) and retain its recovery handle.
   Do not install an output-only response skill for input savings: it can add
   prompt overhead while leaving provider input unchanged.
2. Use [Caveman Pixel Mode](https://github.com/juliusbrussee/caveman#pixel-mode)
   only for dense, long-line payloads. Require a legible model and a measured
   win before `caveman wrap --pixel <agent>`. Never pixel sparse code, normal
   Markdown, loop state, evidence, diffs, or small payloads.
3. For installed skill bodies, use `caveman convert --dry-run` first and convert
   only profitable installed copies; keep frontmatter text, preserve the
   byte-identical `--revert` path (the Caveman CLI subcommand), and never rewrite canonical source here.
4. Check `command -v caveman` and authorization first. On missing capability,
   decline, failure, or recovery/verification trouble, record
   `pixel-transport: skipped — <reason>` and pass bytes unchanged.
5. Label token/size estimates `inferred`; call them `verified` only after real
   traffic and an evaluation gate. Do not install Caveman or change agent
   configuration unless the effect boundary authorizes it.

One compact example: `dense long-line log + authorized CLI + measured win` may
use shrink or Pixel; `sparse code`, missing CLI, or no win keeps the original.
