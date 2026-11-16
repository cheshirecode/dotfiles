import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "graph", Path(__file__).parents[1] / "scripts/graph.py"
)
graph = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(graph)


class GraphTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name).resolve()
        self.repo = root / "checkout"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.source = self.repo / "sample.py"
        self.source.write_text("def alpha(): return 1\n")
        self.env = root / "env"
        (self.env / "bin").mkdir(parents=True)
        (self.env / "bin/python").symlink_to(sys.executable)
        fake = self.env / "bin/graphify"
        fake.write_text(
            "#!"
            + sys.executable
            + """
import json, os, pathlib, sys
out = pathlib.Path(os.environ['GRAPHIFY_OUT'])
if os.environ.get('FAIL_GRAPH'): sys.exit(7)
if sys.argv[1] == 'extract':
    assert not (out / 'graph.json').exists()
    assert not (out / 'cache').exists()
    (out / 'graph.json').write_text(json.dumps({p.name:p.read_text() for p in pathlib.Path(sys.argv[2]).glob('*.py')}))
print('x' * 12000)
"""
        )
        fake.chmod(0o755)
        self.w = graph.Workspace(self.repo, self.env)
        self.w.state.mkdir(parents=True)
        self.w.claim()
        self.boundary = patch.object(graph, "offline", return_value=[])
        self.boundary.start()
        self.addCleanup(self.boundary.stop)
        self.stdout = tempfile.TemporaryFile("w+b")
        self.addCleanup(self.stdout.close)
        wrapper = type("Output", (), {"buffer": self.stdout})()
        self.output = patch.object(sys, "stdout", wrapper)
        self.output.start()
        self.addCleanup(self.output.stop)

    def test_same_size_restored_mtime_and_deletion(self):
        self.assertEqual(self.w.refresh(), 0)
        stat = self.source.stat()
        self.source.write_text("def bravo(): return 2\n")
        os.utime(self.source, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        with self.assertRaisesRegex(graph.GraphError, "stale"):
            self.w.fresh()
        self.assertEqual(self.w.refresh(), 0)
        _, generation = self.w.fresh()
        self.assertIn("bravo", (generation / "graph.json").read_text())
        self.source.unlink()
        with self.assertRaisesRegex(graph.GraphError, "stale"):
            self.w.fresh()
        self.assertEqual(self.w.refresh(), 0)
        _, generation = self.w.fresh()
        self.assertEqual(json.loads((generation / "graph.json").read_text()), {})

    def test_other_checkout_and_lock(self):
        other = self.repo.parent / "other"
        subprocess.run(["git", "init", "-q", str(other)], check=True)
        w = graph.Workspace(other, self.env, self.w.state)
        with self.assertRaisesRegex(graph.GraphError, "another physical checkout"):
            w.claim()
        with graph.locked(self.w.state):
            with self.assertRaisesRegex(graph.GraphError, "Lock exists"):
                with graph.locked(self.w.state):
                    self.fail("lock stolen")
        self.assertFalse((self.w.state / "operation.lock").exists())

    def test_failed_refresh_preserves_graph(self):
        self.w.refresh()
        accepted = (self.w.state / "current.json").read_bytes()
        with patch.dict(os.environ, {"FAIL_GRAPH": "1"}):
            self.assertEqual(self.w.refresh(), 7)
        self.assertEqual((self.w.state / "current.json").read_bytes(), accepted)
        self.w.fresh()

    def test_mid_build_edit_not_published(self):
        self.w.refresh()
        accepted = (self.w.state / "current.json").read_bytes()
        original = self.w.run

        def changing(*args):
            result = original(*args)
            self.source.write_text("changed = True\n")
            return result

        with patch.object(self.w, "run", side_effect=changing):
            with self.assertRaisesRegex(graph.GraphError, "Inputs changed"):
                self.w.refresh()
        self.assertEqual((self.w.state / "current.json").read_bytes(), accepted)

    def test_mid_query_edit_withholds_evidence(self):
        self.w.refresh()
        start = self.stdout.tell()
        original = self.w.run

        def changing(*args):
            result = original(*args)
            self.source.write_text("changed = True\n")
            return result

        with patch.object(self.w, "run", side_effect=changing):
            with self.assertRaisesRegex(graph.GraphError, "stale"):
                self.w.query("query", ["alpha"])
        self.assertEqual(self.stdout.tell(), start)

    def test_hard_output_limit_and_exit(self):
        artifact = self.w.state / "large.log"
        artifact.write_bytes(b"x" * 20000)
        shown = graph.preview(artifact, 7)
        self.assertLessEqual(len(shown), graph.CAP)
        self.assertIn(b"exit=7", shown)
        self.assertIn(b"Truncated", shown)
        self.assertEqual(artifact.stat().st_size, 20000)

    def test_configuration_tampering_and_symlinks(self):
        self.w.refresh()
        _, generation = self.w.fresh()
        (generation / "graph.json").write_text("{}")
        with self.assertRaisesRegex(graph.GraphError, "stale"):
            self.w.fresh()
        link = self.repo / "external.py"
        link.symlink_to(self.source)
        with self.assertRaisesRegex(graph.GraphError, "Symlink"):
            self.w.snapshot()
        self.w.excludes = ["external.py"]
        self.w.snapshot()

    def test_environment_symlink_cannot_point_inside_source(self):
        inside = self.repo / "environment"
        inside.mkdir()
        alias = self.repo.parent / "alias"
        alias.symlink_to(inside, target_is_directory=True)
        with self.assertRaisesRegex(graph.GraphError, "outside the source"):
            graph.Workspace(self.repo, alias)

    def test_no_boundary_fails_closed(self):
        self.boundary.stop()
        with patch.object(graph.platform, "system", return_value="unsupported"):
            with self.assertRaisesRegex(graph.GraphError, "No network-denied"):
                self.w.refresh()
        self.assertFalse((self.w.state / "current.json").exists())


if __name__ == "__main__":
    unittest.main()
