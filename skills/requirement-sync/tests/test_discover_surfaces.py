"""The scanner must never let "I did not look" read as "it is not there"."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import discover_surfaces as ds  # noqa: E402

NOTE = "---\nslug: x\nnext_action: do the thing\n---\nbody\n"


def tree(root, files):
    for rel, body in files.items():
        p = pathlib.Path(root) / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)


class DiscoverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def scan(self):
        return ds.discover(self.root)["surfaces"]

    def test_every_surface_reports_a_state(self):
        # Four states, never collapsed. A surface with no state is a surface
        # nobody looked at, reported as though somebody had.
        for kind, info in self.scan().items():
            self.assertIn(info.get("state"), {"found", "absent", "unknown", "n/a"}, kind)

    def test_unknown_always_carries_a_question(self):
        for kind, info in self.scan().items():
            if info["state"] == "unknown":
                self.assertTrue(info.get("question"), kind)

    def test_live_working_note_is_found(self):
        tree(self.root, {"notes/a.md": NOTE})
        s = self.scan()["working note"]
        self.assertEqual(s["state"], "found")
        self.assertEqual(s["count"], 1)

    def test_fixture_only_notes_are_absent_but_named(self):
        # The dogfooding finding: this repo's own worklog fixtures reported as
        # live working notes. Classified, not filtered -- the count is still
        # reported, so nothing is silently dropped.
        tree(self.root, {"skills/w/tests/fixtures/a.md": NOTE})
        s = self.scan()["working note"]
        self.assertEqual(s["state"], "absent")
        self.assertTrue(any("test/template" in e for e in s["evidence"]))
        self.assertTrue(s.get("question"))

    def test_a_live_note_outranks_fixtures(self):
        tree(self.root, {"notes/a.md": NOTE, "tests/fixtures/b.md": NOTE})
        s = self.scan()["working note"]
        self.assertEqual((s["state"], s["count"], s["fixtures"]), ("found", 1, 1))

    def test_template_html_is_not_a_published_page(self):
        tree(self.root, {"templates/page.html": "<p>x</p>"})
        s = self.scan()["published page"]
        self.assertEqual(s["state"], "absent")
        self.assertTrue(s.get("question"))

    def test_live_html_is_a_published_page(self):
        tree(self.root, {"docs/page.html": "<p>x</p>"})
        self.assertEqual(self.scan()["published page"]["state"], "found")

    def test_memory_and_code_are_found(self):
        tree(self.root, {"AGENTS.md": "rules", "src/a.py": "# invariant\n"})
        s = self.scan()
        self.assertEqual(s["durable memory"]["state"], "found")
        self.assertEqual(s["code comment"]["state"], "found")

    def test_tracker_is_never_found_from_a_remote_alone(self):
        # A forge is where the code lives, not evidence of where work is tracked.
        # Reporting it as found would be the scanner inventing a fact.
        subprocess.run(["git", "init", "-q", self.root], check=True)
        subprocess.run(["git", "-C", self.root, "remote", "add", "origin",
                        "https://forge.example.com/o/r.git"], check=True)
        s = self.scan()["tracked item"]
        self.assertEqual(s["state"], "unknown")
        self.assertIn("forge.example.com", s["question"])

    def test_tracker_without_a_repo_is_unknown_not_absent(self):
        s = self.scan()["tracked item"]
        self.assertEqual(s["state"], "unknown")
        self.assertTrue(s.get("question"))

    def test_scan_writes_nothing(self):
        tree(self.root, {"notes/a.md": NOTE})
        before = sorted(p.name for p in pathlib.Path(self.root).rglob("*"))
        self.scan()
        self.assertEqual(sorted(p.name for p in pathlib.Path(self.root).rglob("*")), before)

    def test_missing_root_exits_2(self):
        self.assertEqual(ds.main(["/nonexistent/path/here"]), 2)


if __name__ == "__main__":
    unittest.main()
