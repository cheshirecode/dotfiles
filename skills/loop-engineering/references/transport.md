# Optional payload transport

At a provider or tool-output boundary, choose a capability-gated,
fail-open, recoverable representation. Measure after selection; if the result
is not both smaller and more legible, send the original bytes.

1. For noisy command output or tool catalogs, an authorized Caveman install may
    use `caveman tools shrink -- <command>` before using Caveman Pixel Mode.
   Preserve producer status with
   `set -o pipefail`; keep the original in an artifact store (`/tmp`,
   `$TMPDIR`, or your harness's upload area) and retain its recovery handle.
   Do not install an output-only response skill for input savings: it can add
   prompt overhead while leaving provider input unchanged.
2. Use [Caveman Pixel Mode](https://github.com/juliusbrussee/caveman#pixel-mode)
   only for dense, long-line payloads. Require a legible model and a measured
   win before `caveman wrap --pixel <agent>`. Never pixel sparse code, normal
   Markdown, loop state, evidence, diffs, or small payloads.
3. For installed skill bodies, use `caveman tools convert --dry-run` first and
   convert only copies that are NOT symlinks into a source checkout (under this
   repo's layout `~/.claude/skills/*` are symlinks into the clone the loader
   reads); keep frontmatter text, preserve the byte-identical `--revert` path
   (the Caveman CLI subcommand), and never rewrite canonical source here.
   Measured 2026-09-03 (CLI 1.3.1 / `bin-v1.1.4`): Caveman does not traverse
   symlinked skills at all — `convert --dry-run --dir ~/.claude/skills` prints
   **`no skills found`, rc=0**, while the same command on a real directory
   reports a token delta. So the rewrite hazard does not materialise; the
   hazard that remains is the message. `no skills found` is the same output as
   the engine-missing case in item 4 and as a genuinely empty directory, so
   read it as "measured nothing", never as "nothing to gain". Distinguish them
   with a control run against a real directory copy before concluding anything
   from it.
4. Check `command -v caveman` and authorization first, and note the engine is a
   separate binary — with only the npm CLI present, `convert` reports
   `caveman-engine not found` and skips every skill, which reads as "nothing to
   gain" rather than "not installed yet"; run `caveman setup --install`.
   On missing capability,
   decline, failure, or recovery/verification trouble, record
   `pixel-transport: skipped — <reason>` and pass bytes unchanged.
5. Label token/size estimates `inferred`; call them `verified` only after real
   traffic and an evaluation gate. Do not install Caveman or change agent
   configuration unless the effect boundary authorizes it.
6. What a win actually looks like, so `--measured-win` is a reading and not a
   guess. Measured 2026-09-03, CLI 1.3.1 / `bin-v1.1.4`, all binaries present,
   `caveman tools compress`:

   | payload | before | after | method |
   | --- | --- | --- | --- |
   | 800 repetitive log lines | 24000 | 181 | `log` |
   | 300-object repeated JSON | 5402 | 137 | `elision` |
   | `git log --oneline -60` via `shrink` | 1228 | 1228 | none |
   | a 9.5k-token Python source file | 9591 | 9591 | none |
   | a 3.8k-token Markdown skill | 3847 | 3847 | none |

   Structure and repetition are what compress; prose, code and short terminal
   output do not, and Caveman reports that honestly as `ratio: 0` rather than
   inventing a saving. Note the shrink lane in item 1 returned **0% on ordinary
   `git log` output** — "noisy command output" means volume and repetition, not
   any command. Measure the actual payload; do not assume the lane implies a
   win.

   Both compressed rows carry `lossless_to_model: false`: the model sees the
   compressed form, and the original comes back only through recovery. That is
   what makes the recoverability requirement in items 1-2 load-bearing rather
   than ceremonial.

One compact example: `dense long-line log + authorized CLI + measured win` may
use shrink or Pixel; `sparse code`, missing CLI, or no win keeps the original.
