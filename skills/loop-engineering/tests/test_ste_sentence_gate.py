#!/usr/bin/env python3
"""Check that the user-output gate catches long wrapped prose."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


GATE = Path(__file__).resolve().parents[1] / "scripts/ste_sentence_gate.py"


class SentenceGateTest(unittest.TestCase):
    def run_gate(self, content: str):
        with tempfile.TemporaryDirectory() as temp:
            draft = Path(temp) / "draft.md"
            draft.write_text(content)
            return subprocess.run(
                [sys.executable, str(GATE), str(draft)],
                text=True, capture_output=True, check=False,
            )

    def test_wrapped_sentence_over_limit_fails_without_echoing_text(self):
        sentence = "private " + " ".join(f"word{i}" for i in range(20)) + "."
        result = self.run_gate(sentence[:20] + "\n" + sentence[20:])
        self.assertEqual(result.returncode, 1)
        self.assertIn("21 words", result.stdout)
        self.assertNotIn("private", result.stdout)

    def test_fenced_code_and_link_target_are_not_prose(self):
        result = self.run_gate(
            "Read the [report](https://example.invalid/a.long.path).\n\n"
            "```text\n" + "long " * 30 + "\n```\n"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("pass", result.stdout)

    def test_relative_link_target_is_not_prose(self):
        target = "/".join(f"part{i}" for i in range(30)) + ".md"
        result = self.run_gate(f"Read the [report]({target}).\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
