"""Tests for scripts/loop_run.py — the single-invocation loop driver.

Contract under test: one command per cycle, no mode parameters. The driver
auto-inits state on the first call, auto-runs crew-radar when a repo is
configured, auto-pulls the next worklog project task when a project is
configured, and prints exactly one line whose tail is the only LLM decision
(`decide: continue or stop` / `decide: stopped`).
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
LOOP_RUN = SKILL_DIR / "scripts" / "loop_run.py"


def run(args, env_extra=None, cwd=None):
    env = dict(os.environ)
    # Isolate from the developer's real worklog unless a test opts in.
    env.pop("WORKLOG_BIN", None)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["python3", str(LOOP_RUN)] + args,
        capture_output=True,
        text=True,
        env=env,
        cwd=cwd,
    )


class LoopRunTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.run_dir = str(Path(self._tmp.name) / "run")
        # Neutral cwd: not a git repo, so no repo is auto-detected.
        self.cwd = self._tmp.name

    def tearDown(self):
        self._tmp.cleanup()

    def init_run(self, extra=None):
        return run(
            [self.run_dir, "--goal", "test goal"] + (extra or []),
            cwd=self.cwd,
        )

    def test_first_call_requires_goal(self):
        r = run([self.run_dir], cwd=self.cwd)
        self.assertEqual(r.returncode, 2)
        self.assertIn("--goal", r.stderr)

    def test_init_creates_state_and_prints_one_decide_line(self):
        r = self.init_run()
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = [l for l in r.stdout.splitlines() if l.strip()]
        self.assertEqual(len(lines), 1)
        self.assertIn("running 0/20", lines[0])
        self.assertTrue(lines[0].endswith("decide: continue or stop"), lines[0])
        self.assertTrue((Path(self.run_dir) / "loop_state.json").exists())

    def test_advance_requires_evidence(self):
        self.init_run()
        r = run([self.run_dir], cwd=self.cwd)
        self.assertEqual(r.returncode, 2)
        self.assertIn("--evidence", r.stderr)

    def test_advance_consumes_budget(self):
        self.init_run(["--budget", "5"])
        r = run(
            [self.run_dir, "--evidence", "command: true — ok"], cwd=self.cwd
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("running 1/5", r.stdout)

    def test_stop_complete_requires_verification(self):
        self.init_run()
        r = run([self.run_dir, "--stop", "complete"], cwd=self.cwd)
        self.assertEqual(r.returncode, 2)
        self.assertIn("--verification", r.stderr)

    def test_stop_complete_is_terminal(self):
        self.init_run()
        r = run(
            [
                self.run_dir,
                "--stop", "complete",
                "--verification", "command: true — rc 0",
                "--evidence", "command: true — done",
            ],
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("complete", r.stdout)
        self.assertTrue(r.stdout.strip().endswith("decide: stopped"), r.stdout)
        # A further advance must be rejected by the state contract (exit 3).
        r2 = run(
            [self.run_dir, "--evidence", "command: true — late"], cwd=self.cwd
        )
        self.assertEqual(r2.returncode, 3)

    def test_stop_blocked_needs_no_verification(self):
        self.init_run()
        r = run(
            [
                self.run_dir,
                "--stop", "blocked",
                "--evidence", "command: false — replay: rerun tests",
            ],
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("blocked", r.stdout)

    def test_stop_cancelled_is_terminal_without_next_action(self):
        # cancelled is non-resumable: loop_state rejects any next_action,
        # so the driver must not default one in.
        self.init_run()
        r = run(
            [
                self.run_dir,
                "--stop", "cancelled",
                "--evidence", "command: user cancelled — stop",
            ],
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("cancelled", r.stdout)
        self.assertTrue(r.stdout.strip().endswith("decide: stopped"), r.stdout)

    def test_radar_off_without_repo(self):
        r = self.init_run()
        self.assertIn("radar: off", r.stdout)

    def test_radar_runs_with_repo(self):
        repo = Path(self._tmp.name) / "repo"
        repo.mkdir()
        subprocess.run(
            ["git", "init", "-q", str(repo)], check=True, capture_output=True
        )
        (repo / "f").write_text("x\n")
        git_env = dict(
            os.environ,
            GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
            GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t",
        )
        subprocess.run(
            ["git", "-C", str(repo), "add", "f"],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["git", "-C", str(repo), "commit", "-qm", "init"],
            check=True, capture_output=True, env=git_env,
        )
        r = self.init_run(["--repo", str(repo)])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("radar: clean", r.stdout)
        # The repo is remembered: the next cycle re-runs the radar unprompted.
        r2 = run(
            [self.run_dir, "--evidence", "command: true — ok"], cwd=self.cwd
        )
        self.assertIn("radar: clean", r2.stdout)

    def test_queue_off_without_project(self):
        r = self.init_run()
        self.assertIn("queue: off", r.stdout)

    def test_queue_reports_next_task_from_stub_worklog(self):
        stub_bin = Path(self._tmp.name) / "wbin"
        stub_bin.mkdir()
        stub = stub_bin / "project.sh"
        stub.write_text("#!/bin/sh\necho task-alpha\n")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        r = run(
            [self.run_dir, "--goal", "test goal", "--project", "prog-x"],
            env_extra={"WORKLOG_BIN": str(stub_bin)},
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("queue: task-alpha", r.stdout)

    def test_queue_reports_empty_when_project_next_exits_1(self):
        stub_bin = Path(self._tmp.name) / "wbin"
        stub_bin.mkdir()
        stub = stub_bin / "project.sh"
        stub.write_text(
            "#!/bin/sh\necho \"project next: all tasks for 'prog-x' are"
            " archived (nothing left)\"\nexit 1\n"
        )
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        r = run(
            [self.run_dir, "--goal", "test goal", "--project", "prog-x"],
            env_extra={"WORKLOG_BIN": str(stub_bin)},
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("queue: empty", r.stdout)


if __name__ == "__main__":
    unittest.main()
