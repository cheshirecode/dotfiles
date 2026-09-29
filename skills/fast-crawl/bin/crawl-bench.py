#!/usr/bin/env python3
"""Benchmark the installed crawl engines on one URL set.

Each URL carries a marker: a string that must appear in the markdown when the
page was really read. Exit code and byte count are not enough, because a
JS-rendered page fetched over plain HTTP returns an empty shell with exit 0.

Two modes per engine, each repeated --trials times, median reported:
  batch  all URLs in one engine call (how fcrawl.py uses the engine)
  cold   one engine call per URL (the cost of a single ad-hoc fetch)

Usage:
  crawl-bench.py [--urls FILE] [--engines lightpanda,crw,crawl4ai]
                 [--trials N] [--modes batch,cold] [--json OUT]

FILE has one `URL<TAB>marker` per line; `#` starts a comment.
Exit codes: 0 benchmark ran, 2 usage error, 3 no requested engine installed.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import statistics
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fcrawl  # noqa: E402

DEFAULT_URLS = [
    # Body text: "Example Domain" is only in <title>, so it scored whichever
    # engine prints the title, not whichever engine read the page.
    ("https://example.com/", "documentation examples"),
    ("https://quotes.toscrape.com/js/", "Albert Einstein"),  # content exists only after JS runs
    ("https://books.toscrape.com/", "A Light in the Attic"),
    ("https://docs.python.org/3/library/json.html", "json.dumps"),
    ("https://news.ycombinator.com/", "points by"),
    ("https://en.wikipedia.org/wiki/Web_crawler", "crawler"),
]

LINK = re.compile(r"\]\(([^)\s]+)")


def load_urls(path: str | None) -> list[tuple[str, str]]:
    if not path:
        return list(DEFAULT_URLS)
    pairs = []
    for n, line in enumerate(pathlib.Path(path).read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        url, sep, marker = line.partition("\t")
        if not sep or not marker.strip():
            raise SystemExit(f"crawl-bench: {path}:{n}: expected URL<TAB>marker")
        pairs.append((url.strip(), marker.strip()))
    return pairs


def absolute_ratio(markdown: str) -> float | None:
    """Share of markdown links that are absolute. Relative links break once
    the text leaves the page, so a low ratio is a quality cost."""
    links = [m for m in LINK.findall(markdown) if not m.startswith("#")]
    if not links:
        return None
    return sum(1 for m in links if re.match(r"[a-z][a-z0-9+.-]*:", m)) / len(links)


def score(rows: list[dict], pairs: list[tuple[str, str]]) -> dict:
    markers = dict(pairs)
    hits = [r["url"] for r in rows if r["error"] is None and markers[r["url"]] in r["markdown"]]
    ratios = [x for x in (absolute_ratio(r["markdown"]) for r in rows) if x is not None]
    return {
        "hits": len(hits),
        "missed": [r["url"] for r in rows if r["url"] not in hits],
        "chars": sum(r["chars"] for r in rows),
        "abs_links": round(statistics.mean(ratios), 2) if ratios else None,
        "slowest": max(rows, key=lambda r: r["seconds"])["url"] if rows else None,
        "per_url_s": {r["url"]: r["seconds"] for r in rows},
    }


def run_mode(engine: str, exe: str, pairs: list[tuple[str, str]], mode: str,
             timeout: float) -> tuple[float, list[dict]]:
    urls = [u for u, _ in pairs]
    runner = fcrawl.RUNNERS[engine]
    start = time.perf_counter()
    if mode == "batch":
        rows = runner(exe, urls, timeout)
    else:
        rows = [runner(exe, [u], timeout)[0] for u in urls]
    return time.perf_counter() - start, rows


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="crawl-bench.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--urls")
    ap.add_argument("--engines", default=",".join(fcrawl.ENGINES))
    ap.add_argument("--modes", default="batch,cold")
    ap.add_argument("--trials", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=fcrawl.DEFAULT_TIMEOUT)
    ap.add_argument("--json", dest="json_out")
    args = ap.parse_args(argv)
    pairs = load_urls(args.urls)
    engines = [e.strip() for e in args.engines.split(",") if e.strip()]
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    bad = [e for e in engines if e not in fcrawl.ENGINES] + [m for m in modes if m not in ("batch", "cold")]
    if bad or args.trials < 1:
        ap.error(f"unknown engine/mode or bad --trials: {', '.join(bad) or args.trials}")

    results, ran = [], 0
    print(f"{'engine':<11} {'mode':<6} {'median_s':>9} {'min_s':>7} {'hits':>6} {'chars':>8} {'abs_links':>9}")
    for engine in engines:
        exe = fcrawl.locate(engine)
        if exe is None:
            print(f"{engine:<11} absent")
            results.append({"engine": engine, "state": "absent"})
            continue
        for mode in modes:
            times, last = [], []
            for _ in range(args.trials):
                took, last = run_mode(engine, exe, pairs, mode, args.timeout)
                times.append(took)
            ran += 1
            s = score(last, pairs)
            row = {"engine": engine, "state": "ran", "mode": mode, "urls": len(pairs),
                   "trials": args.trials, "median_s": round(statistics.median(times), 3),
                   "min_s": round(min(times), 3), **s}
            results.append(row)
            ratio = "-" if s["abs_links"] is None else f"{s['abs_links']:.2f}"
            print(f"{engine:<11} {mode:<6} {row['median_s']:>9.2f} {row['min_s']:>7.2f} "
                  f"{s['hits']:>3}/{len(pairs):<2} {s['chars']:>8} {ratio:>9}")
            if mode == "cold":
                print(f"{'':<11} slowest: {s['slowest']} {s['per_url_s'][s['slowest']]:.2f}s")
            for url in s["missed"]:
                print(f"{'':<11} missed marker: {url}")
    if args.json_out:
        pathlib.Path(args.json_out).write_text(json.dumps(results, indent=2) + "\n")
    return 0 if ran else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
