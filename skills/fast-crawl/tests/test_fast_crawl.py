#!/usr/bin/env python3
"""Contracts for the fast-crawl skill.

Offline by default: stub engines in a temporary $FAST_CRAWL_HOME stand in for
lightpanda, crw and the crawl4ai venv, so the fallback, pairing and doctor
logic is tested without network. The stubs return batch rows in REVERSE order
on purpose: crawl4ai's arun_many really does return pages as they finish, and
pairing by position silently gave one URL another URL's document.

One live case runs the real lightpanda against a JS-only page on a loopback
server when $FAST_CRAWL_LIVE_HOME points at an install (bin/lightpanda). It is
skipped, with the reason printed, when that is unset.
"""

from __future__ import annotations

import http.server
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import threading
import unittest

SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]
FCRAWL = SKILL_DIR / "bin" / "fcrawl.py"
BENCH = SKILL_DIR / "bin" / "crawl-bench.py"
INSTALLER = SKILL_DIR / "bin" / "install-fast-crawl.sh"
LONG = "x" * 300

# Stub lightpanda: JS-looking URLs come back as an empty shell (the real
# silent failure is exit 0 with no content), everything else as markdown.
LIGHTPANDA_STUB = f"""#!{sys.executable}
import json, os, sys
args = sys.argv[1:]
if args == ["version"]:
    sys.exit(int(os.environ.get("STUB_LP_VERSION_EXIT", "0")) or print("0.4.1"))
urls = [a for a in args if a.startswith("http")]
# A "slow" URL fails alone when a per-page --http-timeout is passed, as the
# real engine does; without it the whole process hangs past its deadline.
if any("slow" in u for u in urls) and "--http-timeout" not in args:
    import time; time.sleep(30)
WALL = "## Performing security verification\\nThis website uses a security service. " * 3
HOST_OPEN = args[args.index("--http-max-host-open") + 1] if "--http-max-host-open" in args else "unset"
ROBOTS = "--obey-robots" in args
def content(u):
    if "thin" in u or "js" in u:
        return ""
    return WALL if "wall" in u else "lp " + u + " host_open=" + HOST_OPEN + " {LONG}"
def error(u):
    if "slow" in u:
        return "HttpTimeout"
    return "RobotsBlocked" if ROBOTS and "private" in u else None
rows = [{{"url": u + "/", "content": "" if "slow" in u else content(u), "error": error(u)}}
        for u in urls]
print(json.dumps({{"results": rows[::-1]}} if len(urls) > 1 else rows[0]))
"""

# Stub crw: renders everything except URLs marked thin.
CRW_STUB = f"""#!{sys.executable}
import os, sys, time
args = sys.argv[1:]
if args == ["--version"]:
    print("crw 0.36.0"); sys.exit(0)
url = args[1]
log = os.environ.get("STUB_CRW_LOG")
if log:
    with open(log, "a") as f:
        f.write(f"start {{time.time()}}\\n")
    time.sleep(0.3)
    with open(log, "a") as f:
        f.write(f"end {{time.time()}}\\n")
# crw keeps links relative, as the real engine does.
print("" if "thin" in url else "crw " + url + " [login](/login) {LONG}")
"""

# Stub crawl4ai venv python: ignores the -c script, returns reversed rows.
CRAWL4AI_STUB = f"""#!{sys.executable}
import json, sys
args = sys.argv[1:]
if args[:1] == ["-c"] and "import crawl4ai, playwright" in args[1]:
    sys.exit(0)
urls = args[2:]
rows = [{{"url": u, "markdown": "c4 " + u + " {LONG}", "error": None}} for u in urls]
print("[INIT] noise on stdout")
print(json.dumps(rows[::-1]))
"""


def write_exe(path: pathlib.Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)


class StubHome(unittest.TestCase):
    engines = ("lightpanda", "crw")

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name)
        stubs = {"lightpanda": LIGHTPANDA_STUB, "crw": CRW_STUB}
        for name in self.engines:
            if name == "crawl4ai":
                write_exe(self.home / "venv" / "bin" / "python", CRAWL4AI_STUB)
            else:
                write_exe(self.home / "bin" / name, stubs[name])
        # PATH without the developer's tool dirs, so a real engine on PATH
        # cannot answer for a missing stub.
        self.env = {"FAST_CRAWL_HOME": str(self.home), "PATH": "/usr/bin:/bin",
                    "HOME": str(self.home)}

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_tool(self, tool: pathlib.Path, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, str(tool), *args], capture_output=True, text=True,
                              env={**self.env, **env}, check=False, timeout=60)

    def jsonl(self, proc: subprocess.CompletedProcess[str]) -> dict[str, dict]:
        rows = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
        return {r["url"]: r for r in rows}


class AutoFallback(StubHome):
    def test_js_page_falls_back_and_static_page_stays(self) -> None:
        proc = self.run_tool(FCRAWL, "--format", "jsonl", "https://a.test/static", "https://a.test/js")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rows = self.jsonl(proc)
        self.assertEqual(rows["https://a.test/static"]["engine"], "lightpanda")
        self.assertEqual(rows["https://a.test/js"]["engine"], "crw")

    def test_batch_rows_are_paired_by_url_not_position(self) -> None:
        urls = ["https://a.test/one", "https://a.test/two", "https://a.test/three"]
        # One process, so the stub's reversed rows reach the pairing code.
        proc = self.run_tool(FCRAWL, "--engine", "lightpanda", "--format", "jsonl", *urls,
                             FAST_CRAWL_JOBS="1")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for url, row in self.jsonl(proc).items():
            self.assertIn(f"lp {url} ", row["markdown"], f"{url} got another page's document")

    def test_jobs_split_keeps_every_url_and_its_own_document(self) -> None:
        urls = [f"https://a.test/p{i}" for i in range(5)]
        proc = self.run_tool(FCRAWL, "--engine", "lightpanda", "--jobs", "2", "--format", "jsonl", *urls)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rows = self.jsonl(proc)
        self.assertEqual(sorted(rows), sorted(urls))
        for url, row in rows.items():
            self.assertIn(f"lp {url} ", row["markdown"], f"{url} got another page's document")
        self.assertEqual([json.loads(line)["url"] for line in proc.stdout.splitlines()], urls,
                         "output order must follow input order")

    def test_one_slow_url_does_not_lose_its_chunk(self) -> None:
        proc = self.run_tool(FCRAWL, "--engine", "lightpanda", "--jobs", "1", "--timeout", "2",
                             "--format", "jsonl", "https://a.test/fast", "https://a.test/slow")
        rows = self.jsonl(proc)
        self.assertIsNone(rows["https://a.test/fast"]["error"])
        self.assertIn("lp https://a.test/fast ", rows["https://a.test/fast"]["markdown"])
        self.assertEqual(rows["https://a.test/slow"]["error"], "HttpTimeout")

    def test_crw_relative_links_come_back_absolute(self) -> None:
        proc = self.run_tool(FCRAWL, "--engine", "crw", "--format", "jsonl", "https://a.test/dir/page")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        md = self.jsonl(proc)["https://a.test/dir/page"]["markdown"]
        self.assertIn("[login](https://a.test/login)", md)
        self.assertNotIn("](/login)", md)

    def test_host_open_budget_is_split_over_processes(self) -> None:
        for extra, want in ((["--jobs", "4"], "1"), (["--jobs", "1"], "6"),
                            (["--jobs", "4", "--host-open", "12"], "3")):
            proc = self.run_tool(FCRAWL, "--engine", "lightpanda", *extra, "https://a.test/x")
            self.assertIn(f"host_open={want} ", proc.stdout, extra)

    def test_crw_runs_at_most_host_open_at_once_per_host(self) -> None:
        log = pathlib.Path(self.tmp.name) / "crw.log"
        urls = [f"https://one.test/p{i}" for i in range(6)]
        proc = self.run_tool(FCRAWL, "--engine", "crw", "--host-open", "2", "--format", "jsonl", *urls,
                             STUB_CRW_LOG=str(log))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        events = sorted((float(t), kind) for kind, t in
                        (line.split() for line in log.read_text().splitlines()))
        live = peak = 0
        for _, kind in events:
            live += 1 if kind == "start" else -1
            peak = max(peak, live)
        self.assertEqual(len(events), 12)
        self.assertEqual(peak, 2)

    def test_obey_robots_runs_lightpanda_only_and_keeps_the_block(self) -> None:
        proc = self.run_tool(FCRAWL, "--obey-robots", "--format", "jsonl",
                             "https://a.test/private/x", "https://a.test/pub")
        self.assertEqual(proc.returncode, 1)
        rows = self.jsonl(proc)
        self.assertEqual(rows["https://a.test/private/x"]["error"], "RobotsBlocked")
        self.assertEqual(rows["https://a.test/private/x"]["engine"], "lightpanda")
        self.assertIsNone(rows["https://a.test/pub"]["error"])

    def test_obey_robots_refuses_a_forced_other_engine(self) -> None:
        proc = self.run_tool(FCRAWL, "--obey-robots", "--engine", "crw", "https://a.test/x")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("lightpanda only", proc.stderr)

    def test_jobs_below_one_is_refused(self) -> None:
        proc = self.run_tool(FCRAWL, "--jobs", "0", "https://a.test/x")
        self.assertEqual(proc.returncode, 2)

    def test_bot_wall_page_falls_back_to_the_next_engine(self) -> None:
        # The wall page is long enough to pass the thin check, and exits 0.
        proc = self.run_tool(FCRAWL, "--format", "jsonl", "https://a.test/wall")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        row = self.jsonl(proc)["https://a.test/wall"]
        self.assertEqual(row["engine"], "crw")
        self.assertNotIn("security verification", row["markdown"])

    def test_bot_wall_everywhere_exits_1_with_blocked_error(self) -> None:
        proc = self.run_tool(FCRAWL, "--engine", "lightpanda", "--format", "jsonl", "https://a.test/wall")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(self.jsonl(proc)["https://a.test/wall"]["error"],
                         "blocked: bot-wall page from lightpanda")

    def test_thin_everywhere_exits_1_and_names_the_engines(self) -> None:
        proc = self.run_tool(FCRAWL, "--format", "jsonl", "https://a.test/thin")
        self.assertEqual(proc.returncode, 1)
        err = self.jsonl(proc)["https://a.test/thin"]["error"]
        self.assertRegex(err, r"^thin: 0 chars < 100 after lightpanda\+crw$")

    def test_stdin_urls(self) -> None:
        proc = subprocess.run([sys.executable, str(FCRAWL), "--format", "jsonl", "-"],
                              input="https://a.test/x\n\nhttps://a.test/y\n", capture_output=True,
                              text=True, env=self.env, check=False, timeout=60)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(sorted(self.jsonl(proc)), ["https://a.test/x", "https://a.test/y"])

    def test_unknown_order_entry_is_refused(self) -> None:
        proc = self.run_tool(FCRAWL, "https://a.test/x", FAST_CRAWL_ORDER="lightpanda,chrome")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("unknown engine(s): chrome", proc.stderr)

    def test_md_format_single_url_is_bare_markdown(self) -> None:
        proc = self.run_tool(FCRAWL, "https://a.test/page")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(proc.stdout.startswith("lp https://a.test/page "), proc.stdout[:80])
        self.assertNotIn("<!-- fcrawl", proc.stdout)


class Crawl4aiPairing(StubHome):
    engines = ("crawl4ai",)

    def test_unordered_arun_many_rows_are_paired_by_url(self) -> None:
        urls = ["https://a.test/one", "https://a.test/two", "https://a.test/three"]
        proc = self.run_tool(FCRAWL, "--engine", "crawl4ai", "--format", "jsonl", *urls)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rows = self.jsonl(proc)
        self.assertEqual(sorted(rows), sorted(urls))
        for url, row in rows.items():
            self.assertIn(f"c4 {url} ", row["markdown"], f"{url} got another page's document")


class NoEngines(StubHome):
    engines = ()

    def test_no_engine_exits_3_and_names_the_installer(self) -> None:
        proc = self.run_tool(FCRAWL, "https://a.test/x")
        self.assertEqual(proc.returncode, 3)
        self.assertIn("install-fast-crawl.sh", proc.stderr)

    def test_doctor_reports_absent_not_ok(self) -> None:
        proc = self.run_tool(FCRAWL, "doctor")
        self.assertEqual(proc.returncode, 3)
        for name in ("lightpanda", "crw", "crawl4ai"):
            self.assertRegex(proc.stdout, rf"(?m)^{name}\s+absent$")

    def test_bench_exits_3_when_nothing_ran(self) -> None:
        proc = self.run_tool(BENCH, "--trials", "1")
        self.assertEqual(proc.returncode, 3)


class Doctor(StubHome):
    engines = ("lightpanda", "crw", "crawl4ai")

    def test_states(self) -> None:
        proc = self.run_tool(FCRAWL, "doctor", STUB_LP_VERSION_EXIT="7")
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertRegex(proc.stdout, r"(?m)^lightpanda\s+broken \(exit 7\)")
        self.assertRegex(proc.stdout, r"(?m)^crw\s+ok\s")
        self.assertRegex(proc.stdout, r"(?m)^crawl4ai\s+ok\s")


class Bench(StubHome):
    def test_marker_miss_is_reported_even_when_the_fetch_succeeds(self) -> None:
        urls = pathlib.Path(self.tmp.name) / "urls.tsv"
        # Both pages fetch fine; only one contains its marker.
        urls.write_text("# comment\nhttps://a.test/hit\tlp https://a.test/hit\n"
                        "https://a.test/miss\tnot-on-the-page\n")
        out = pathlib.Path(self.tmp.name) / "bench.json"
        proc = self.run_tool(BENCH, "--urls", str(urls), "--engines", "lightpanda",
                             "--modes", "batch", "--trials", "2", "--json", str(out))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        (row,) = json.loads(out.read_text())
        self.assertEqual((row["engine"], row["mode"], row["trials"]), ("lightpanda", "batch", 2))
        self.assertEqual(row["hits"], 1)
        self.assertEqual(row["missed"], ["https://a.test/miss"])
        self.assertIn("missed marker: https://a.test/miss", proc.stdout)

    def test_bad_url_line_is_refused(self) -> None:
        urls = pathlib.Path(self.tmp.name) / "urls.tsv"
        urls.write_text("https://a.test/no-marker\n")
        proc = self.run_tool(BENCH, "--urls", str(urls))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn(":1: expected URL<TAB>marker", proc.stderr)

    def test_absolutize_rules(self) -> None:
        sys.path.insert(0, str(SKILL_DIR / "bin"))
        try:
            import fcrawl
        finally:
            sys.path.pop(0)
        base = "https://a.test/dir/page"
        md = ("[a](/root) [b](rel?x=1) ![i](img.png) [p](//cdn.test/x) [h](https://b.test/) "
              "[f](#top) [m](mailto:x@a.test)\n```\n[code](/not-a-link)\n```\n[after](/z)")
        out = fcrawl.absolutize(md, base)
        for want in ("[a](https://a.test/root)", "[b](https://a.test/dir/rel?x=1)",
                     "![i](https://a.test/dir/img.png)", "[p](https://cdn.test/x)",
                     "[h](https://b.test/)", "[f](#top)", "[m](mailto:x@a.test)",
                     "[code](/not-a-link)", "[after](https://a.test/z)"):
            self.assertIn(want, out)

    def test_absolute_link_ratio(self) -> None:
        sys.path.insert(0, str(SKILL_DIR / "bin"))
        try:
            import importlib
            bench = importlib.import_module("crawl-bench")
        finally:
            sys.path.pop(0)
        md = "[a](https://x.test/a) [b](/b) [c](c?id=1) [top](#top)"
        self.assertAlmostEqual(bench.absolute_ratio(md), 1 / 3)
        self.assertIsNone(bench.absolute_ratio("no links"))


class Installer(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name) / "home"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_installer(self, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        base = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": self.tmp.name,
                "FAST_CRAWL_HOME": str(self.home), "TMPDIR": self.tmp.name}
        return subprocess.run(["bash", str(INSTALLER), *args], capture_output=True, text=True,
                              env={**base, **env}, check=False, timeout=60)

    def test_help(self) -> None:
        proc = self.run_installer("--help")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("--engines LIST", proc.stdout)

    def test_usage_errors_exit_2(self) -> None:
        self.assertEqual(self.run_installer("--nope").returncode, 2)
        proc = self.run_installer("--engines", "lightpanda,chrome")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("unknown engine 'chrome'", proc.stderr)

    def test_unsupported_platform_exits_5(self) -> None:
        proc = self.run_installer(FAST_CRAWL_FAKE_OS="MINGW64_NT", FAST_CRAWL_FAKE_ARCH="x86_64")
        self.assertEqual(proc.returncode, 5)
        self.assertIn("Windows via WSL", proc.stderr)

    def test_dry_run_changes_nothing(self) -> None:
        proc = self.run_installer("--engines", "lightpanda,crw,crawl4ai", "--dry-run")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.count("would "), 3)
        self.assertFalse(self.home.exists())

    def test_checksum_mismatch_installs_nothing(self) -> None:
        mirror = pathlib.Path(self.tmp.name) / "mirror"
        mirror.mkdir()
        for asset in ("lightpanda-aarch64-macos", "lightpanda-x86_64-macos",
                      "lightpanda-x86_64-linux", "lightpanda-aarch64-linux"):
            (mirror / asset).write_text("not the pinned binary\n")
        proc = self.run_installer("--engines", "lightpanda", FAST_CRAWL_MIRROR=mirror.as_uri())
        self.assertEqual(proc.returncode, 4, proc.stderr)
        self.assertIn("checksum mismatch", proc.stderr)
        self.assertFalse((self.home / "bin" / "lightpanda").exists())


class SkillDoc(unittest.TestCase):
    def test_frontmatter_name(self) -> None:
        head = (SKILL_DIR / "SKILL.md").read_text().split("---")[1]
        self.assertIn("name: fast-crawl", head)

    def test_evaluation_names_every_engine(self) -> None:
        text = (SKILL_DIR / "references" / "evaluation.md").read_text()
        for name in ("lightpanda", "crw", "crawl4ai"):
            self.assertIn(name, text)


JS_PAGE = textwrap.dedent("""\
    <!doctype html><html><head><title>js fixture</title></head><body>
    <div id="app"></div>
    <script>document.getElementById('app').innerHTML =
      '<h1>Rendered by script</h1><p>' + 'markerfrom' + 'script' + '</p>';</script>
    </body></html>""")


@unittest.skipUnless(os.environ.get("FAST_CRAWL_LIVE_HOME"),
                     "set FAST_CRAWL_LIVE_HOME to an install root to run the live lightpanda case")
class LiveLightpanda(unittest.TestCase):
    def test_js_only_content_is_rendered(self) -> None:
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                body = JS_PAGE.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args: object) -> None:
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            url = f"http://127.0.0.1:{server.server_address[1]}/"
            proc = subprocess.run(
                [sys.executable, str(FCRAWL), "--engine", "lightpanda", "--min-chars", "10",
                 "--format", "jsonl", url],
                capture_output=True, text=True, check=False, timeout=60,
                env={**os.environ, "FAST_CRAWL_HOME": os.environ["FAST_CRAWL_LIVE_HOME"]})
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
        row = json.loads(proc.stdout)
        # The marker is assembled by script, so it is absent from the raw HTML.
        # No punctuation in it: markdown output escapes `-` as `\-`.
        self.assertNotIn("markerfromscript", JS_PAGE)
        self.assertIn("markerfromscript", row["markdown"])


if __name__ == "__main__":
    unittest.main()
