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
import shutil
import subprocess
import sys
import time

ENGINES = ("lightpanda", "crw", "crawl4ai")
DEFAULT_MIN_CHARS = 100
DEFAULT_TIMEOUT = 60.0
CRW_PARALLEL = 8
DEFAULT_JOBS = 4


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


def record(url: str, engine: str, markdown: str, error: str | None, seconds: float) -> dict:
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
    cmd = [exe, "fetch", "--json", "--dump", "markdown", "--wait-until", "load", *urls]
    start = time.perf_counter()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                              env=engine_env(), check=False)
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
    # crw scrape takes one URL per process; run them side by side.
    with concurrent.futures.ThreadPoolExecutor(max_workers=CRW_PARALLEL) as pool:
        return list(pool.map(lambda u: _crw_one(exe, u, timeout), urls))


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
    engines = order() if args.engine == "auto" else [args.engine]
    rows = fetch(urls, engines, args.min_chars, args.timeout)
    if not rows:
        print(f"fcrawl: no engine installed among {', '.join(engines)}; "
              "run bin/install-fast-crawl.sh or `fcrawl.py doctor`", file=sys.stderr)
        return 3
    emit(rows, args.format)
    return 0 if all(ok(r, args.min_chars) for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
