# Historical Pixel model verification

Verified 2026-09-03 against `@caveman-ai/cli` 1.3.1 / binaries `bin-v1.1.4`:
`caveman-engine pixel simulate --model` gives `claude-fable-5` and `gpt-5.6`
their own pixel geometry, while an unknown id, a bogus id and an empty id all
collapse to one identical fallback — which is what makes the first two
*recognised* rather than merely accepted.
