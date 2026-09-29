#!/usr/bin/env python3
"""Fetch web pages as markdown with the fastest local engine that works.

Engines, in default fallback order (see references/evaluation.md for why):

  lightpanda  headless browser in Zig; runs JS; one process fetches many URLs
  crw         fastCRW single binary in Rust; HTTP first, own crawl/map
  crawl4ai    Python + Playwright Chromium; heaviest, widest web-API support

`auto` tries each installed engine in order and keeps the first result that is
not thin (fewer than --min-chars characters of markdown). A thin page is the
silent failure here: a JS-rendered page fetched over plain HTTP returns an
empty shell with exit 0, so the character count is checked, not the exit code.

Engines are looked up in $FAST_CRAWL_HOME/bin (default
~/.local/share/fast-crawl/bin), then on PATH. crawl4ai uses
$FAST_CRAWL_HOME/venv/bin/python. bin/install-fast-crawl.sh installs all three.

Usage:
  fcrawl.py [--engine auto|lightpanda|crw|crawl4ai] [--format md|jsonl]
            [--min-chars N] [--timeout S] [--jobs N] URL... | -
  fcrawl.py doctor

Exit codes: 0 every URL ok, 1 at least one URL failed or thin, 2 usage error,
3 no requested engine is installed.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse

ENGINES = ("lightpanda", "crw", "crawl4ai")
DEFAULT_MIN_CHARS = 100
DEFAULT_TIMEOUT = 60.0
CRW_PARALLEL = 8
DEFAULT_JOBS = 4
# Connections one host may see from one fcrawl run, summed over processes.
# Measured on 20 pages of one site: 4 processes x 1 connection took 1.13 s,
# 4 x 6 (lightpanda's own default, 24 in total) took 1.14 s. The speed comes
# from process count, not per-host connections.
DEFAULT_HOST_OPEN = 6


def host_open_wanted() -> int:
    try:
        return max(1, int(os.environ.get("FAST_CRAWL_HOST_OPEN", DEFAULT_HOST_OPEN)))
    except ValueError:
        return DEFAULT_HOST_OPEN


def obey_robots() -> bool:
    return os.environ.get("FAST_CRAWL_OBEY_ROBOTS") == "1"


def jobs_wanted() -> int:
    try:
        return int(os.environ.get("FAST_CRAWL_JOBS", DEFAULT_JOBS))
    except ValueError:
        return DEFAULT_JOBS

# Runs inside the crawl4ai venv. Reads URLs as argv, prints one JSON list.
CRAWL4AI_SCRIPT = r"""
import asyncio, json, sys
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode

async def main(urls):
    run = CrawlerRunConfig(cache_mode=CacheMode.BYPASS, verbose=False)
    async with AsyncWebCrawler(config=BrowserConfig(headless=True, verbose=False)) as c:
        results = await c.arun_many(urls, config=run)
    out = []
    for r in results:
        out.append({"url": r.url, "markdown": str(r.markdown or ""),
                    "error": None if r.success else (r.error_message or "failed")})
    print(json.dumps(out))

asyncio.run(main(sys.argv[1:]))
"""


def home() -> pathlib.Path:
    raw = os.environ.get("FAST_CRAWL_HOME") or "~/.local/share/fast-crawl"
    return pathlib.Path(raw).expanduser()


def locate(engine: str) -> str | None:
    """Return the executable for an engine, or None when it is absent."""
    if engine == "crawl4ai":
        py = home() / "venv" / "bin" / "python"
        return str(py) if py.is_file() and os.access(py, os.X_OK) else None
    local = home() / "bin" / engine
    if local.is_file() and os.access(local, os.X_OK):
        return str(local)
    return shutil.which(engine)


def engine_env() -> dict[str, str]:
    env = dict(os.environ)
    env.setdefault("LIGHTPANDA_DISABLE_TELEMETRY", "true")
    env.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(home() / "playwright"))
    return env


LINK_TARGET = re.compile(r"(\]\()([^)\s]+)")
FENCE = re.compile(r"(?ms)^```.*?^```[^\n]*$")


def absolutize(markdown: str, base: str) -> str:
    """Resolve relative markdown link and image targets against the page URL.

    crw keeps them relative (measured: 196 of 231 links on one news page), and
    a relative link is useless once the text leaves the page. Targets with a
    scheme, `#fragment` targets and fenced code blocks are left alone.
    """
    def fix(m: re.Match) -> str:
        target = m.group(2)
        if target.startswith("#") or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            return m.group(0)
        return m.group(1) + urllib.parse.urljoin(base, target)

    out, last = [], 0
    for fence in FENCE.finditer(markdown):
        out.append(LINK_TARGET.sub(fix, markdown[last:fence.start()]))
        out.append(fence.group(0))
        last = fence.end()
    out.append(LINK_TARGET.sub(fix, markdown[last:]))
    return "".join(out)


def record(url: str, engine: str, markdown: str, error: str | None, seconds: float) -> dict:
    markdown = absolutize(markdown, url) if markdown else markdown
    return {"url": url, "engine": engine, "chars": len(markdown.strip()), "error": error,
            "seconds": round(seconds, 3), "markdown": markdown}


def _norm(url: str) -> str:
    return url.split("#", 1)[0].rstrip("/").lower()


def pair(urls: list[str], rows: list[dict]) -> list[dict | None]:
    """Match output rows to input URLs by normalised URL.

    Neither batch engine promises input order: crawl4ai's arun_many returns
    pages as they finish, so pairing by position silently swaps documents.
    Rows whose url field does not match (a redirect, say) fill the remaining
    slots in output order.
    """
    by_url: dict[str, list[dict]] = {}
    for row in rows:
        if isinstance(row, dict):
            by_url.setdefault(_norm(str(row.get("url", ""))), []).append(row)
    paired: list[dict | None] = []
    for u in urls:
        bucket = by_url.get(_norm(u))
        paired.append(bucket.pop(0) if bucket else None)
    leftovers = [r for bucket in by_url.values() for r in bucket]
    return [p if p is not None else (leftovers.pop(0) if leftovers else None) for p in paired]


def run_lightpanda(exe: str, urls: list[str], timeout: float) -> list[dict]:
    # Round-robin the URLs over `jobs` processes. Measured on 20 pages of one
    # site: 1 process 2.80s, 2 1.80s, 4 1.15s, 8 1.07s (references/evaluation.md).
    jobs = max(1, min(jobs_wanted(), len(urls)))
    if jobs == 1:
        return _lightpanda_batch(exe, urls, timeout)
    chunks = [urls[i::jobs] for i in range(jobs)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        done = list(pool.map(lambda c: _lightpanda_batch(exe, c, timeout), chunks))
    by_url = {row["url"]: row for rows in done for row in rows}
    return [by_url[u] for u in urls]


def _lightpanda_batch(exe: str, urls: list[str], timeout: float) -> list[dict]:
    # One process per chunk. More than one URL requires --json, and --json
    # with one URL prints a bare object instead of {"results": [...]}.
    #
    # `timeout` is per page. lightpanda enforces it per transfer
    # (--http-timeout), so one slow URL fails alone and the rest of the chunk
    # survives. The subprocess deadline is only a backstop for a hung process:
    # with it as the only limit, one slow URL marked every URL in its chunk
    # "timeout" and their content was lost.
    cmd = [exe, "fetch", "--json", "--dump", "markdown", "--wait-until", "load",
           "--http-timeout", str(int(timeout * 1000)),
           "--http-max-host-open", str(max(1, host_open_wanted() // jobs_wanted())),
           *(["--obey-robots"] if obey_robots() else []), *urls]
    start = time.perf_counter()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout * len(urls) + 10, env=engine_env(), check=False)
    except subprocess.TimeoutExpired:
        took = time.perf_counter() - start
        return [record(u, "lightpanda", "", "timeout", took) for u in urls]
    took = time.perf_counter() - start
    try:
        payload = json.loads(proc.stdout)
    except ValueError:
        err = f"exit {proc.returncode}: {proc.stderr.strip()[:200] or 'no JSON output'}"
        return [record(u, "lightpanda", "", err, took) for u in urls]
    rows = payload.get("results", [payload]) if isinstance(payload, dict) else []
    out = []
    for u, row in zip(urls, pair(urls, rows)):
        md = (row or {}).get("content") or ""
        err = row.get("error") if row else "missing from output"
        out.append(record(u, "lightpanda", md if isinstance(md, str) else "", err, took / len(urls)))
    return out


def _crw_one(exe: str, url: str, timeout: float) -> dict:
    start = time.perf_counter()
    try:
        proc = subprocess.run([exe, "scrape", url, "-f", "markdown"], capture_output=True,
                              text=True, timeout=timeout, env=engine_env(), check=False)
    except subprocess.TimeoutExpired:
        return record(url, "crw", "", "timeout", time.perf_counter() - start)
    err = None if proc.returncode == 0 else f"exit {proc.returncode}: {proc.stderr.strip()[:200]}"
    return record(url, "crw", proc.stdout, err, time.perf_counter() - start)


def run_crw(exe: str, urls: list[str], timeout: float) -> list[dict]:
    # crw scrape takes one URL per process and has no rate limit of its own,
    # so cap how many run at once against one host.
    slots: dict[str, threading.Semaphore] = {}
    for u in urls:
        slots.setdefault(urllib.parse.urlsplit(u).netloc, threading.Semaphore(host_open_wanted()))

    def one(u: str) -> dict:
        with slots[urllib.parse.urlsplit(u).netloc]:
            return _crw_one(exe, u, timeout)

    with concurrent.futures.ThreadPoolExecutor(max_workers=CRW_PARALLEL) as pool:
        return list(pool.map(one, urls))


def run_crawl4ai(exe: str, urls: list[str], timeout: float) -> list[dict]:
    start = time.perf_counter()
    try:
        proc = subprocess.run([exe, "-c", CRAWL4AI_SCRIPT, *urls], capture_output=True,
                              text=True, timeout=timeout, env=engine_env(), check=False)
    except subprocess.TimeoutExpired:
        took = time.perf_counter() - start
        return [record(u, "crawl4ai", "", "timeout", took) for u in urls]
    took = time.perf_counter() - start
    try:
        # crawl4ai logs to stdout too; the JSON list is the last line.
        rows = json.loads(proc.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        err = f"exit {proc.returncode}: {proc.stderr.strip()[-200:] or 'no JSON output'}"
        return [record(u, "crawl4ai", "", err, took) for u in urls]
    out = []
    for u, row in zip(urls, pair(urls, rows if isinstance(rows, list) else [])):
        row = row or {"markdown": "", "error": "missing from output"}
        out.append(record(u, "crawl4ai", row.get("markdown") or "", row.get("error"), took / len(urls)))
    return out


RUNNERS = {"lightpanda": run_lightpanda, "crw": run_crw, "crawl4ai": run_crawl4ai}


def order() -> list[str]:
    raw = os.environ.get("FAST_CRAWL_ORDER", ",".join(ENGINES))
    names = [n.strip() for n in raw.split(",") if n.strip()]
    unknown = [n for n in names if n not in ENGINES]
    if unknown:
        raise SystemExit(f"fcrawl: FAST_CRAWL_ORDER has unknown engine(s): {', '.join(unknown)}")
    return names


# Bot-wall interstitials: short pages that exit 0 and pass the thin check.
# Measured 2026-09-29: lightpanda got a 438-char Cloudflare challenge from
# a Cloudflare-fronted landing page while crw read the real page. Only short
# pages are checked, so a long article that quotes a phrase is not flagged.
BOT_WALL_MARKERS = (
    "Performing security verification",
    "Checking your browser before accessing",
    "Enable JavaScript and cookies to continue",
    "Attention Required! | Cloudflare",
)
BOT_WALL_MAX_CHARS = 2000


def walled(markdown: str) -> bool:
    return len(markdown) <= BOT_WALL_MAX_CHARS and any(m in markdown for m in BOT_WALL_MARKERS)


def ok(row: dict, min_chars: int) -> bool:
    return row["error"] is None and row["chars"] >= min_chars


def fetch(urls: list[str], engines: list[str], min_chars: int, timeout: float) -> list[dict]:
    """Try engines in order; each later engine only sees URLs still failing."""
    best: dict[str, dict] = {}
    pending = list(urls)
    tried = []
    for name in engines:
        if not pending:
            break
        exe = locate(name)
        if exe is None:
            continue
        tried.append(name)
        for row in RUNNERS[name](exe, pending, timeout):
            if row["error"] is None and walled(row["markdown"]):
                row["error"] = f"blocked: bot-wall page from {name}"
            prev = best.get(row["url"])
            if prev is None or ok(row, min_chars) or row["chars"] > prev["chars"]:
                best[row["url"]] = row
        pending = [u for u in pending if not ok(best[u], min_chars)]
    if not tried:
        return []
    for u in pending:
        row = best[u]
        if row["error"] is None:
            row["error"] = f"thin: {row['chars']} chars < {min_chars} after {'+'.join(tried)}"
    return [best[u] for u in urls]


def doctor() -> int:
    """Report each engine as ok, broken or absent. Exit 0 only if one is ok."""
    any_ok = False
    for name in ENGINES:
        exe = locate(name)
        if exe is None:
            print(f"{name:<11} absent")
            continue
        probe = [exe, "-c", "import crawl4ai, playwright"] if name == "crawl4ai" else (
            [exe, "version"] if name == "lightpanda" else [exe, "--version"])
        try:
            proc = subprocess.run(probe, capture_output=True, text=True, timeout=30,
                                  env=engine_env(), check=False)
            state = "ok" if proc.returncode == 0 else f"broken (exit {proc.returncode})"
            detail = (proc.stdout.strip() or proc.stderr.strip()).splitlines()[:1]
        except (OSError, subprocess.TimeoutExpired) as exc:
            state, detail = "broken", [type(exc).__name__]
        any_ok = any_ok or state == "ok"
        print(f"{name:<11} {state:<9} {exe} {' '.join(detail)}".rstrip())
    return 0 if any_ok else 3


def emit(rows: list[dict], fmt: str) -> None:
    if fmt == "jsonl":
        for row in rows:
            print(json.dumps(row, ensure_ascii=False))
        return
    many = len(rows) > 1
    for row in rows:
        if many:
            print(f"\n<!-- fcrawl url={row['url']} engine={row['engine']} chars={row['chars']} -->")
        if row["error"]:
            print(f"fcrawl: {row['url']}: {row['error']} (engine {row['engine']})", file=sys.stderr)
        sys.stdout.write(row["markdown"])
        if not row["markdown"].endswith("\n"):
            sys.stdout.write("\n")


def main(argv: list[str]) -> int:
    if argv[:1] == ["doctor"]:
        return doctor()
    ap = argparse.ArgumentParser(prog="fcrawl.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("urls", nargs="+", help="URLs, or - to read one URL per line from stdin")
    ap.add_argument("--engine", default="auto", choices=("auto", *ENGINES))
    ap.add_argument("--format", default="md", choices=("md", "jsonl"))
    ap.add_argument("--min-chars", type=int, default=DEFAULT_MIN_CHARS)
    ap.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    ap.add_argument("--obey-robots", action="store_true",
                    help="honour robots.txt; runs lightpanda only, the one engine that can")
    ap.add_argument("--host-open", type=int, help=f"connections per host, summed over processes "
                    f"(default {DEFAULT_HOST_OPEN}, or $FAST_CRAWL_HOST_OPEN)")
    ap.add_argument("--jobs", type=int, help=f"lightpanda processes per batch (default {DEFAULT_JOBS}, "
                    "or $FAST_CRAWL_JOBS)")
    args = ap.parse_args(argv)
    if args.jobs is not None:
        if args.jobs < 1:
            ap.error("--jobs must be 1 or more")
        os.environ["FAST_CRAWL_JOBS"] = str(args.jobs)
    urls = [u for u in args.urls if u != "-"]
    if "-" in args.urls:
        urls += [line.strip() for line in sys.stdin if line.strip()]
    if not urls:
        ap.error("no URLs given")
    if args.host_open is not None:
        if args.host_open < 1:
            ap.error("--host-open must be 1 or more")
        os.environ["FAST_CRAWL_HOST_OPEN"] = str(args.host_open)
    engines = order() if args.engine == "auto" else [args.engine]
    if args.obey_robots:
        if engines != ["lightpanda"] and args.engine != "auto":
            ap.error("--obey-robots works with lightpanda only")
        os.environ["FAST_CRAWL_OBEY_ROBOTS"] = "1"
        engines = ["lightpanda"]
    rows = fetch(urls, engines, args.min_chars, args.timeout)
    if not rows:
        print(f"fcrawl: no engine installed among {', '.join(engines)}; "
              "run bin/install-fast-crawl.sh or `fcrawl.py doctor`", file=sys.stderr)
        return 3
    emit(rows, args.format)
    return 0 if all(ok(r, args.min_chars) for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
