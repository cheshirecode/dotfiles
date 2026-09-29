# Engine evaluation — 2026-09-29

Measured on one machine: macOS 26.2 (Darwin 25.2.0), Apple Silicon (arm64),
home network. All numbers are wall-clock seconds and include network time.
They rank the engines on this machine on this day. They are not limits, and
a different network or site set can change the order. Re-run
`bin/crawl-bench.py` before you rely on a number.

Versions: lightpanda 0.4.1, crw (fastCRW) 0.36.0, crawl4ai 0.9.4 with
Playwright Chrome Headless Shell 153.

## What each engine is

| Engine | What it is | Runs JS | Install size | Licence |
| --- | --- | --- | --- | --- |
| lightpanda | Headless browser written in Zig, with its own DOM and a V8 engine; no Chromium | yes | one 83 MB binary | AGPL-3.0 |
| crw | fastCRW: a Firecrawl-compatible scraper and crawler in Rust; HTTP first | only by starting a separate browser | one 27 MB binary | AGPL-3.0 (engine) |
| crawl4ai | Python library that drives Playwright Chromium | yes | venv 595 MB + Chromium 557 MB | Apache-2.0 |

## Benchmark

`bin/crawl-bench.py --trials 5`. `batch` sends all URLs in one engine call,
the way `fcrawl.py` does. `cold` makes one engine call per URL. `hits` counts
pages whose body contains the marker string. `abs_links` is the mean share of
markdown links that are absolute (`https://…`), not relative (`/login`).

### Six URLs, one of them JS-only

The set is example.com, quotes.toscrape.com/js (its quotes exist only after
JS runs), books.toscrape.com, a docs.python.org page, Hacker News and a
Wikipedia article.

| Engine | Mode | Median s | Hits | Chars | abs_links |
| --- | --- | --- | --- | --- | --- |
| lightpanda | batch (4 jobs) | 0.73 | 6/6 | 174809 | 1.00 |
| lightpanda | cold | 3.03 | 6/6 | 174809 | 1.00 |
| crw | batch (8 parallel) | 18.89 | 6/6 | 97193 | 0.38 |
| crw | cold | 20.63 | 6/6 | 97193 | 0.38 |
| crawl4ai | batch | 2.09 | 5/6 | 187297 | 1.00 |
| crawl4ai | cold | 7.71 | 5/6 | 187168 | 1.00 |

crw spent 19.1 s of its time on the one JS page: plain HTTP gave a 40-char
shell, and crw then started a JS renderer by itself.

### The five static URLs only

| Engine | Mode | Median s | Hits | Chars | abs_links |
| --- | --- | --- | --- | --- | --- |
| lightpanda | batch (4 jobs) | 0.62 | 5/5 | 173007 | 1.00 |
| lightpanda | cold | 2.04 | 5/5 | 173007 | 1.00 |
| crw | batch (8 parallel) | 0.44 | 5/5 | 95721 | 0.46 |
| crw | cold | 1.33 | 5/5 | 95694 | 0.46 |
| crawl4ai | batch | 1.63 | 4/5 | 185547 | 1.00 |
| crawl4ai | cold | 6.58 | 4/5 | 185476 | 1.00 |

crw's lower character count is its main-content extraction: it drops page
chrome such as navigation. That is shorter, but it also keeps relative links,
which break once the text leaves the page.

### Site crawl, 20 pages of books.toscrape.com

| Method | Seconds | Pages ok |
| --- | --- | --- |
| `crw crawl --depth 1 --limit 20 --concurrency 8` | 2.85 | 20 |
| `crw map --depth 1 --limit 20` (URLs only) | 0.99 | — |
| lightpanda, 20 URLs, 1 process | 2.80 | 20/20 |
| lightpanda, 2 processes | 1.80 | 20/20 |
| lightpanda, 4 processes | 1.15 | 20/20 |
| lightpanda, 8 processes | 1.07 | 20/20 |

`crw map` with no `--depth` or `--limit` found 800 URLs in 29.6 s.

## Decision

- **Default order: lightpanda, crw, crawl4ai.** lightpanda read every page,
  including the JS page, with absolute links, in the lowest batch time on the
  mixed set. Four processes per batch was near the best measured result; 8
  added little.
- **crw is second.** It is fastest on pages known to be static, and its `map`
  is the fastest way to list a site's URLs. Force it with `--engine crw` for a
  static site where short main-content text is the goal.
- **crawl4ai is last and opt-in.** It is a real Chromium, so it is the
  fallback when lightpanda's DOM does not support a page. It costs 1.1 GB, a
  2–3 s browser start, and one quality defect below.

## Defects found while measuring

Each one returned exit 0.

1. **crawl4ai returns `arun_many` results in finish order.** Pairing rows by
   position gave the quotes URL the Python docs page. `fcrawl.py` pairs by
   URL; `test_unordered_arun_many_rows_are_paired_by_url` covers it.
2. **crawl4ai joins words split across `<span>` elements.** On example.com it
   printed "Thisdomainisforuse…". The bench marker "documentation examples"
   misses there for that reason.
3. **`crw scrape --js` with `CRW_CDP_URL=http://127.0.0.1:9333`** (a running
   `lightpanda serve`) returned in 0.45 s with none of the JS content. The
   same endpoint as `ws://…` worked but took 9.1 s.
4. **A title-only marker scores the wrong thing.** example.com has "Example
   Domain" only in `<title>`, and a script replaces its body. crw prints the
   title as a heading and scored a hit; the others did not print it. The
   marker now uses body text.
5. **lightpanda escapes `-` in markdown** (`marker-from-js` became
   `marker\-from\-js`), so a hyphenated marker misses.

## Not measured

- Sites behind bot protection, logins or consent walls. Use browser-use.
- crw's own crawl with `--js`, and crw's server mode (`crw serve`).
- lightpanda `--strip-mode clutter` (reader-mode extraction) against crw's
  main-content output.
- Linux. The installer pins Linux assets, but no Linux run was made here.
