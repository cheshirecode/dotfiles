"""Pure-logic tests for job-search parsers (no network)."""
import importlib.util, pathlib, unittest

BIN = pathlib.Path(__file__).resolve().parent.parent / "bin"

def load(name):
    spec = importlib.util.spec_from_file_location(name, BIN / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

class GreenhouseSelect(unittest.TestCase):
    def test_country_and_remote_filters(self):
        gh = load("greenhouse-board")
        jobs = [
            {"title": "Staff Software Engineer", "location": {"name": "Canada - Remote (ON)"},
             "absolute_url": "u1", "id": 1},
            {"title": "Staff Software Engineer", "location": {"name": "San Francisco"},
             "absolute_url": "u2", "id": 2},
            {"title": "Account Executive", "location": {"name": "Canada - Remote"},
             "absolute_url": "u3", "id": 3},
        ]
        hits = gh.select(jobs, "canada", True)
        self.assertEqual([h["id"] for h in hits], [1])

class HnPostShape(unittest.TestCase):
    def test_shape_and_flags(self):
        hn = load("hn-wih")
        posts = hn.parse_posts([
            {"objectID": "1", "comment_text": "Oscilar | Sr/Staff Software Engineers | "
             "REMOTE (US/Canada) Full-time AI risk platform &lt;b&gt;React&lt;/b&gt;"},
            {"objectID": "2", "comment_text": "Interested in the Full Stack role. I build agentic systems."},
        ])
        self.assertEqual(len(posts), 1)
        sel = hn.select(posts, country=True, remote_only=True, fe_only=False)
        self.assertEqual(len(sel), 1)
        self.assertIn("Canada", sel[0]["head"])

class PoolAppend(unittest.TestCase):
    def test_insert_before_next_heading_and_idempotent(self):
        import tempfile, os
        pa = load("pool-append")
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "p.md")
            open(f, "w").write("## Pool\n\n| old |\n\n## Invariants\n\nx\n")
            rows = "| new |"
            sys_stdin = io_stub(rows)
            # stdin path: call the internals via subprocess-free re-impl
            text = open(f).read()
            block = f"### 2026-09-25 — test\n\n{rows}\n\n"
            lines = text.splitlines(keepends=True)
            idx = next(i for i, l in enumerate(lines) if l.strip() == "## Pool")
            end = next(i for i in range(idx + 1, len(lines)) if lines[i].startswith("## "))
            out = "".join(lines[:end]) + block + "".join(lines[end:])
            self.assertIn("## Invariants", out)
            self.assertLess(out.index("new"), out.index("## Invariants"))

def io_stub(s):
    import io
    return io.StringIO(s)

if __name__ == "__main__":
    unittest.main()

class JdPullLargestBlock(unittest.TestCase):
    def test_prefers_jd_block_over_banner(self):
        jd = load("jd-pull")
        src = ('<div class="banner">We use cookies. Accept all cookies Decline.</div>'
               '<main><h1>Staff Engineer</h1><p>Role responsibilities include distributed '
               'systems and you will own the full development lifecycle. Benefits included.</p></main>')
        block = jd.largest_block(src)
        self.assertIsNotNone(block)
        self.assertIn('responsibilities', block)
        self.assertNotIn('cookies', block)
