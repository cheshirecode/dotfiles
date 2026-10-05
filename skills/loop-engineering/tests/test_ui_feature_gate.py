import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


GATE = Path(__file__).resolve().parent.parent / "scripts" / "ui_feature_gate.py"


class UiFeatureGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(["git", "-C", str(self.repo), "config", "user.name", "test"], check=True)
        subprocess.run(
            ["git", "-C", str(self.repo), "config", "user.email", "test@example.invalid"],
            check=True,
        )
        (self.repo / "app.txt").write_text("source\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "app.txt"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "commit", "-qm", "fixture"], check=True)
        self.revision = subprocess.check_output(
            ["git", "-C", str(self.repo), "rev-parse", "HEAD"], text=True
        ).strip()
        self.manifest = {
            "revision": self.revision,
            "browser": "Test browser",
            "build": [sys.executable, "-c", "print('built')"],
            "preview": {
                "verify": [
                    sys.executable,
                    "-c",
                    "import os; print(os.environ['UI_VALIDATION_REVISION'])",
                ]
            },
            "cases": [
                {
                    "id": "visible-result",
                    "given": "the page is open",
                    "when": "the action runs",
                    "then": "the result appears",
                    "check": [
                        sys.executable,
                        "-c",
                        "import os,pathlib; p=pathlib.Path(os.environ['UI_VALIDATION_OUTPUT_DIR'])/'cases/result.txt'; p.parent.mkdir(); p.write_text('observed')",
                    ],
                    "artifact": "cases/result.txt",
                }
            ],
        }
        self.runs = 0

    def run_gate(self, *, allow_deploy=False):
        self.runs += 1
        manifest = self.root / f"manifest-{self.runs}.json"
        manifest.write_text(json.dumps(self.manifest))
        output = self.root / f"output-{self.runs}"
        args = [sys.executable, str(GATE), str(manifest), "--output-dir", str(output)]
        if allow_deploy:
            args.append("--allow-deploy")
        result = subprocess.run(args, cwd=self.repo, capture_output=True, text=True)
        report = json.loads((output / "result.json").read_text()) if output.exists() else None
        return result, report, output

    def test_runs_all_steps_and_records_exact_revision(self):
        result, report, output = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["revision"], self.revision)
        self.assertEqual(
            [step["name"] for step in report["steps"]],
            ["build", "preview:verify", "case:visible-result"],
        )
        self.assertEqual((output / "cases/result.txt").read_text(), "observed")

    def test_build_failure_stops_before_browser(self):
        self.manifest["build"] = [sys.executable, "-c", "raise SystemExit(7)"]
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["failed_step"], "build")
        self.assertEqual([step["name"] for step in report["steps"]], ["build"])

    def test_build_that_changes_source_cannot_pass(self):
        self.manifest["build"] = [
            sys.executable,
            "-c",
            "import pathlib; pathlib.Path('app.txt').write_text('changed')",
        ]
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["failed_step"], "build")
        self.assertIn("worktree became dirty", report["reason"])

    def test_preview_must_report_exact_revision(self):
        self.manifest["preview"]["verify"] = [sys.executable, "-c", "print('other revision')"]
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["failed_step"], "preview:verify")
        self.assertNotIn("case:visible-result", [step["name"] for step in report["steps"]])

    def test_browser_case_needs_nonempty_artifact(self):
        self.manifest["cases"][0]["check"] = [sys.executable, "-c", "print('passed')"]
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["failed_step"], "case:visible-result")
        self.assertEqual(report["reason"], "browser evidence artifact missing or empty")

    def test_dirty_source_cannot_claim_exact_revision(self):
        (self.repo / "app.txt").write_text("modified\n")
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIsNone(report)

    def test_deploy_requires_explicit_flag(self):
        self.manifest["preview"]["deploy"] = [sys.executable, "-c", "print('deploy')"]
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIsNone(report)
        result, report, _ = self.run_gate(allow_deploy=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["steps"][1]["name"], "preview:deploy")

    def test_missing_cases_is_rejected_before_commands(self):
        self.manifest["cases"] = []
        result, report, _ = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIsNone(report)


if __name__ == "__main__":
    unittest.main()
