"""Measurement must count the selected artifact once and fail on missing data."""

import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "tools/measure-skill-context.py"
SPEC = importlib.util.spec_from_file_location("skill_context", SCRIPT)
MEASURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MEASURE)


class ContextMeasurementTest(unittest.TestCase):
    def test_deduplicates_resolved_paths_and_handles_spaces(self):
        with tempfile.TemporaryDirectory(prefix="skill context ") as directory:
            root = Path(directory)
            (root / "selected.md").write_text("selected é", encoding="utf-8")
            (root / "unrelated.md").write_text("unrelated" * 1000)
            text = MEASURE.payload(root, ["selected.md", "./selected.md"])
            self.assertEqual(text, "selected é")
            self.assertEqual(MEASURE.counts(text), {"bytes": 11, "words": 2, "tokens": None})

    def test_missing_reference_cannot_report_a_saving(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                MEASURE.payload(Path(directory), ["missing.md"])

    def test_compares_distinct_baseline_and_current_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "old.md").write_text("alpha beta")
            (root / "new.md").write_text("alpha")
            rows = MEASURE.compare({"route": {"before": ["old.md"], "after": ["new.md"]}}, root, root)
            self.assertEqual(rows[0]["reduction_percent"]["words"], 50)
            self.assertIsNone(rows[0]["reduction_percent"]["tokens"])


if __name__ == "__main__":
    unittest.main()
