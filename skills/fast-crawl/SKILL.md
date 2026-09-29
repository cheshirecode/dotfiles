---
name: fast-crawl
description: Fetch and crawl web pages as markdown locally, fast, with no browser session. Picks among lightpanda, fastCRW (crw) and crawl4ai with a fallback chain. Use for bulk page reads, site crawls and JS-rendered pages; use browser-use for clicks, logins and bot walls.
---

# fast-crawl

Read many web pages as markdown on this machine, as fast as possible. Three
self-installed engines sit behind one wrapper. Measured results and the
reasons for the default order are in
[references/evaluation.md](references/evaluation.md).

## Pick the tool

| Task | Use |
| --- | --- |
| One public page, read once | `curl` or the fetch tool; no install |
| Many pages, or pages that need JS to show content | `bin/fcrawl.py` |
| A whole site | `crw map` for URLs, then `bin/fcrawl.py -` |
| Click, type, log in, a bot wall, the user's session | the vendor `browser-use` skill |

## Install

```bash
bin/install-fast-crawl.sh                    # lightpanda + crw, ~110 MB
bin/install-fast-crawl.sh --engines crawl4ai # opt-in: uv venv + Chromium, ~1.1 GB
python3 bin/fcrawl.py doctor                 # ok / broken / absent per engine
```

Versions and SHA-256 values are pinned in the installer. A mismatch installs
nothing (exit 4). Files go under `$FAST_CRAWL_HOME` (default
`~/.local/share/fast-crawl`). The installer does not change `PATH` or any
shell profile.

## Fetch

```bash
python3 bin/fcrawl.py https://example.com/                 # markdown to stdout
python3 bin/fcrawl.py --format jsonl URL1 URL2 URL3         # one JSON row per URL
python3 bin/fcrawl.py --engine crw URL                      # force one engine
```

`auto` tries lightpanda, then crw, then crawl4ai. Each engine gets only the
URLs that are still failing. A page is failing when the engine errors or the
markdown has fewer than `--min-chars` (default 100) characters. Check the
character count, not only the exit code: a JS page read over plain HTTP gives
an empty shell and exit 0. Change the order with `FAST_CRAWL_ORDER`.

Exit codes: 0 every URL ok, 1 a URL failed or was thin, 2 usage error,
3 no engine installed. A JSONL row has `url`, `engine`, `chars`, `error`,
`seconds` and `markdown`.

## Crawl a site

```bash
FC="$FAST_CRAWL_HOME/bin"   # or ~/.local/share/fast-crawl/bin
"$FC/crw" map https://books.toscrape.com/ --depth 1 --limit 50 \
  | python3 bin/fcrawl.py --format jsonl - > pages.jsonl
```

`crw map` finds URLs. `fcrawl.py` fetches them with 4 lightpanda processes
(`--jobs N` changes that). This gives absolute links. `crw crawl URL --depth N
--limit N` does the same in one step and is also fast on static sites, but
about half of its links stay relative.

`crw map` with no `--depth` or `--limit` walks the whole site: 800 URLs took
30 s on books.toscrape.com. Always set a limit.

## Benchmark

```bash
python3 bin/crawl-bench.py --trials 3                  # built-in URL set
python3 bin/crawl-bench.py --urls my.tsv --engines lightpanda,crw
```

`my.tsv` has one `URL<TAB>marker` per line. The marker is text that must
appear in the page body. Do not use the `<title>`: some engines print it and
some do not, so the marker then scores the engine, not the read.

## Known traps

- `crw` escalates a thin page to a JS renderer that it starts itself. That
  took 19–20 s for one page here. lightpanda renders the same page in under
  1 s. `auto` puts lightpanda first for this reason.
- `crw scrape --js` with `CRW_CDP_URL=http://…` returned in 0.45 s with none
  of the page content and no error. A `ws://` URL worked, but took 9 s.
- crawl4ai `arun_many` returns pages in finish order, not input order.
  `fcrawl.py` pairs rows by URL.
- crawl4ai joined the words on a page that puts each word in its own `<span>`
  ("Thisdomainisforuse…").
- lightpanda sends usage telemetry unless `LIGHTPANDA_DISABLE_TELEMETRY=true`.
  `fcrawl.py` sets it; set it yourself when you call the binary directly.
- lightpanda markdown escapes `-` (`a-b` becomes `a\-b`), so a marker with a
  hyphen misses. Use plain words as benchmark markers.

## Tests

`tests/test_fast_crawl.py` runs offline with stub engines. To add the live
lightpanda case (a JS-only page on a loopback server), set
`FAST_CRAWL_LIVE_HOME` to an install root.
