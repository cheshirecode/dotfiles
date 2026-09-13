"""Tests for scripts/loop_run.py — the single-invocation loop driver.

Contract under test: one command per cycle, no mode parameters. The driver
auto-inits state on the first call, auto-runs crew-radar when a repo is
configured, auto-pulls the next worklog project task when a project is
configured, and prints exactly one line whose tail is the only LLM decision
(`decide: continue or stop` / `decide: stopped`).
"""

import os
import json
import io
from contextlib import redirect_stdout
import shlex
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
LOOP_RUN = SKILL_DIR / "scripts" / "loop_run.py"

# radar_line is exercised in-process: crew-radar's path is a module constant,
# so a stub cannot be reached through PATH the way project.sh can.
sys.path.insert(0, str(SKILL_DIR / "scripts"))
import loop_run  # noqa: E402


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


def queue_stub(status, task=None, reason=None, stderr=""):
    data = json.dumps({"schema_version":"worklog-project-next/v1", "project":"prog-x",
                       "status":status, "task":task, "reason":reason})
    return ("#!/bin/sh\n[ \"$*\" = 'next prog-x --json' ] || exit 2\n"
            + "printf '%s' " + shlex.quote(data) + "\n"
            + "printf '%s' " + shlex.quote(stderr) + " >&2\n"
            + "exit %d\n" % (0 if status == "eligible" else 1))


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
        lines = [line for line in r.stdout.splitlines() if line.strip()]
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

    def test_stop_is_terminal_for_every_status(self):
        # Partial enum coverage let the cancelled bug reach a live smoke:
        # exercise every terminal status the driver's --stop accepts.
        statuses = (
            "blocked", "budget_exhausted", "cancelled",
            "complete", "continue_scheduled", "needs_human",
        )
        for status in statuses:
            with self.subTest(status=status):
                run_dir = str(Path(self._tmp.name) / ("stop-" + status))
                run([run_dir, "--goal", "test goal"], cwd=self.cwd)
                args = [
                    run_dir,
                    "--stop", status,
                    "--evidence", "command: stop probe — %s" % status,
                ]
                if status == "complete":
                    args += ["--verification", "command: probe — rc 0"]
                r = run(args, cwd=self.cwd)
                self.assertEqual(r.returncode, 0, "%s: %s" % (status, r.stderr))
                self.assertIn(status, r.stdout)
                self.assertTrue(
                    r.stdout.strip().endswith("decide: stopped"), r.stdout
                )

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
        # One worktree: the radar ran, and says so honestly rather than
        # grading a comparison it could not make.
        self.assertIn("radar: single-owner", r.stdout)
        # The repo is remembered: the next cycle re-runs the radar unprompted.
        r2 = run(
            [self.run_dir, "--evidence", "command: true — ok"], cwd=self.cwd
        )
        self.assertIn("radar: single-owner", r2.stdout)

    def _radar_cell(self, code, stdout, stderr=""):
        """Run radar_line against a crew-radar stub with a fixed exit code."""
        stub = Path(self._tmp.name) / "crew-radar-stub"
        body = "#!/bin/sh\nprintf '%%s' %s\n" % shlex.quote(stdout)
        if stderr:
            body += "printf '%%s' %s >&2\n" % shlex.quote(stderr)
        body += "exit %d\n" % code
        stub.write_text(body)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        real = loop_run.CREW_RADAR
        loop_run.CREW_RADAR = stub
        self.addCleanup(setattr, loop_run, "CREW_RADAR", real)
        return loop_run.radar_line(str(Path(self._tmp.name)))

    def test_radar_rejects_malformed_payloads_at_the_process_boundary(self):
        for payload in ("not json", "[]", "null"):
            with self.subTest(payload=payload):
                self.assertEqual(self._radar_cell(0, payload), "radar: error=unrunnable")

    def test_radar_payload_validation_preserves_error_categories(self):
        for changes, expected in (
            ({"overlaps": "bad"}, "invalid-overlaps"),
            ({"overlaps": [None]}, "invalid-overlaps"),
            ({"overlaps": [{"severity": "warn", "path": 3}]}, "invalid-overlaps"),
            ({"overlaps": [{"severity": "unknown", "path": "x"}]}, "invalid-overlaps"),
            ({"warn": True}, "inconsistent-verdict"),
            ({"info": True}, "inconsistent-verdict"),
            ({"warn": 1}, "inconsistent-verdict"),
        ):
            with self.subTest(changes=changes):
                payload = dict(warn=0, info=0, overlaps=[])
                payload.update(changes)
                self.assertEqual(
                    self._radar_cell(0, json.dumps(payload)),
                    "radar: error=" + expected,
                )

    def test_radar_interpretation_needs_no_process_or_artifact_access(self):
        payload = {"warn": 1, "info": 1, "remote_fetch": "stale",
                   "overlaps": [{"severity": "warn", "path": "a.py"},
                                {"severity": "info", "path": "b.py"}]}
        with mock.patch.object(loop_run, "run_probe", side_effect=AssertionError("IO")), \
                mock.patch.object(loop_run, "write_json", side_effect=AssertionError("IO")):
            self.assertEqual(
                loop_run.radar_verdict(payload, 2, ref=" artifact=/tmp/result", remote=True),
                "radar: warn=1 info=1 paths=a.py artifact=/tmp/result remote=stale",
            )

    def test_radar_unavailable_process_is_an_error(self):
        with mock.patch.object(loop_run, "run_probe", side_effect=OSError("missing")):
            self.assertEqual(loop_run.radar_line("repo"), "radar: error=unrunnable")

    def test_radar_usage_or_repo_error_is_not_a_conflict_verdict(self):
        # crew.md: exit 1 is a usage or repo error, exit 2 the collision
        # verdict. A radar that could not inspect the repo must never render
        # as a `warn=` cell -- that reads as "the radar ran and found N".
        cell = self._radar_cell(
            1,
            '{"base":"HEAD","worktrees":0,"warn":0,"info":0,"overlaps":[]}',
            "crew-radar: repo unreadable",
        )
        self.assertTrue(cell.startswith("radar: error="), cell)
        self.assertNotIn("warn=", cell)

    def test_radar_never_renders_an_unknown_verdict_label(self):
        # A payload with no warn count cannot be reported as a verdict at all;
        # `warn=?` is indistinguishable from a real verdict whose label is
        # unknown, so the unknown must surface as an error.
        for code in (1, 2, 3):
            with self.subTest(code=code):
                cell = self._radar_cell(code, "{}")
                self.assertNotIn("warn=?", cell)
                self.assertTrue(cell.startswith("radar: error="), cell)

    def test_radar_info_only_overlap_is_not_reported_as_a_warn(self):
        # Exit 0 with overlaps is the info-only (stacked-branch) case. Sharing
        # the `warn=` prefix with the exit-2 collision cell makes a clean run
        # look like a graded conflict.
        cell = self._radar_cell(
            0,
            '{"base":"HEAD","worktrees":2,"warn":0,"info":1,'
            '"overlaps":[{"severity":"info","path":"a.py","owners":"f-a"}]}',
        )
        self.assertEqual(cell, "radar: info=1 paths=a.py")

    def test_radar_collision_reports_count_and_paths(self):
        # Pin (passes before and after the fix): exit 2 stays the one cell
        # that carries a warn count.
        cell = self._radar_cell(
            2,
            '{"base":"HEAD","worktrees":2,"warn":2,"info":0,'
            '"overlaps":[{"severity":"warn","path":"a.py","owners":"f-a"},'
            '{"severity":"warn","path":"b.py","owners":"f-b"}]}',
        )
        self.assertEqual(cell, "radar: warn=2 info=0 paths=a.py,b.py")

    def test_radar_single_owner_is_not_rendered_as_clean(self):
        # A repo with one owner cannot express an overlap, so exit 0 there is
        # the absence of a comparison. Rendering it `clean` is the reading that
        # makes an orchestrator skip serializing writes: subagents sharing one
        # worktree collide under a single label and the radar cannot see it.
        cell = self._radar_cell(
            0,
            '{"base":"HEAD","worktrees":1,"comparable":false,'
            '"remote_branches":0,"remote_fetch":"off",'
            '"warn":0,"info":0,"overlaps":[]}',
        )
        self.assertEqual(cell, "radar: single-owner")

    def test_radar_clean_requires_an_actual_comparison(self):
        cell = self._radar_cell(
            0,
            '{"base":"HEAD","worktrees":2,"comparable":true,'
            '"remote_branches":0,"remote_fetch":"off",'
            '"warn":0,"info":0,"overlaps":[]}',
        )
        self.assertEqual(cell, "radar: clean")

    def test_radar_without_comparable_field_still_reads_clean(self):
        # An older crew-radar omits the field; absence is not proof of a
        # single owner, so the cell must not invent one.
        cell = self._radar_cell(
            0, '{"base":"HEAD","worktrees":2,"warn":0,"info":0,"overlaps":[]}'
        )
        self.assertEqual(cell, "radar: clean")

    def test_radar_remote_flag_reaches_crew_radar(self):
        argv = Path(self._tmp.name) / "radar-argv"
        stub = Path(self._tmp.name) / "crew-radar-argv"
        stub.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + shlex.quote(str(argv))
            + "\nprintf '%s' '{\"base\":\"H\",\"worktrees\":2,"
              "\"comparable\":true,\"warn\":0,\"info\":0,\"overlaps\":[]}'\n"
        )
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        real = loop_run.CREW_RADAR
        loop_run.CREW_RADAR = stub
        self.addCleanup(setattr, loop_run, "CREW_RADAR", real)

        loop_run.radar_line(str(Path(self._tmp.name)))
        self.assertNotIn("--remote", argv.read_text().split("\n"))

        loop_run.radar_line(str(Path(self._tmp.name)), remote=True)
        self.assertIn("--remote", argv.read_text().split("\n"))

    def test_queue_off_without_project(self):
        r = self.init_run()
        self.assertIn("queue: off", r.stdout)

    def test_queue_reports_next_task_from_stub_worklog(self):
        stub_bin = Path(self._tmp.name) / "wbin"
        stub_bin.mkdir()
        stub = stub_bin / "project.sh"
        stub.write_text(queue_stub("eligible", "task-alpha"))
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
        stub.write_text(queue_stub("empty"))
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        r = run(
            [self.run_dir, "--goal", "test goal", "--project", "prog-x"],
            env_extra={"WORKLOG_BIN": str(stub_bin)},
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("queue: empty", r.stdout)

    def _stub(self, body):
        """Write a project.sh stub and return its bin dir."""
        stub_bin = Path(self._tmp.name) / "wbin"
        stub_bin.mkdir(exist_ok=True)
        stub = stub_bin / "project.sh"
        stub.write_text(body)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        return str(stub_bin)

    def _queue_cell(self, stdout):
        for cell in stdout.strip().split(" | "):
            if cell.startswith("queue:"):
                return cell
        self.fail("no queue cell in: %r" % stdout)

    def init_with_stub(self, body):
        return run(
            [self.run_dir, "--goal", "test goal", "--project", "prog-x"],
            env_extra={"WORKLOG_BIN": self._stub(body)},
            cwd=self.cwd,
        )

    def test_queue_slug_is_read_from_stdout_only(self):
        # project.sh prints the slug on stdout and warnings on stderr. Reading
        # a merged stream hands the last warning back as a task name.
        r = self.init_with_stub(queue_stub("eligible", "task-alpha", stderr="warning: vault is behind origin"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self._queue_cell(r.stdout), "queue: task-alpha")

    def test_queue_rejects_output_that_is_not_a_slug(self):
        # A zero exit carrying prose is a broken contract, not a task name.
        r = self.init_with_stub("#!/bin/sh\necho 'up to date, nothing to do'\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(
            self._queue_cell(r.stdout).startswith("queue: error="),
            self._queue_cell(r.stdout),
        )
        # The cell must not break the one-line contract.
        body = [ln for ln in r.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(body), 1)

    def test_queue_blocked_only_for_the_dependency_verdict(self):
        r = self.init_with_stub(queue_stub("blocked"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self._queue_cell(r.stdout), "queue: blocked")

    def test_queue_configuration_failure_is_an_error_not_a_lull(self):
        # orchestrator.md: exit 1 alone is not proof of an empty or blocked
        # queue -- it also covers a missing or misconfigured project. Reporting
        # those as `blocked` lets a loop spin forever claiming nothing.
        for stderr_line in (
            "project next: no task file for 'prog-x'",
            "project next: 'prog-x' has no tasks: block",
            "_lib.sh::resolve_worklog_repo: cannot locate a worklog data repo.",
        ):
            with self.subTest(stderr_line):
                self._tmp.cleanup()
                self._tmp = tempfile.TemporaryDirectory()
                self.run_dir = str(Path(self._tmp.name) / "run")
                self.cwd = self._tmp.name
                r = self.init_with_stub(
                    "#!/bin/sh\necho \"%s\" >&2\nexit 1\n" % stderr_line
                )
                self.assertEqual(r.returncode, 0, r.stderr)
                cell = self._queue_cell(r.stdout)
                self.assertTrue(cell.startswith("queue: error="), cell)
                self.assertNotIn("blocked", cell)

    # --- WORKLOG_BIN resolution -------------------------------------------
    # A queue the caller asked for and did not get used to print
    # "queue: off (no WORKLOG_BIN)" -- the same word the driver uses when no
    # --project was passed at all. Two worklog checkouts can exist on one
    # machine, so a profile exporting WORKLOG_BIN at the wrong one is the
    # expected failure, not an exotic one. Each test below is RED against the
    # pre-fix driver.

    def test_requested_queue_with_wrong_worklog_bin_is_an_error(self):
        # RED before the fix: this printed "queue: off (no WORKLOG_BIN)".
        # WORKLOG_BIN set but pointing at a directory with no project.sh --
        # the "two copies that can drift" case, pointed at the wrong copy.
        # A deliberately long name, so the reason exceeds cell()'s cap on
        # every platform. macOS /var/folders tmp roots did that on their own
        # and this assertion caught the clipping there; Linux /tmp paths are
        # short enough to fit under any plausible cap, so on this platform the
        # regression was invisible and the cap could be lowered back to 80
        # with the suite still green.
        empty = Path(self._tmp.name) / ("not-worklog-" + "d" * 120)
        empty.mkdir()
        r = run(
            [self.run_dir, "--goal", "test goal", "--project", "prog-x"],
            env_extra={"WORKLOG_BIN": str(empty)},
            cwd=self.cwd,
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        cell = self._queue_cell(r.stdout)
        self.assertTrue(cell.startswith("queue: error="), cell)
        # The reason must name the path, so "wrong copy" is distinguishable
        # from "no copy" without re-running anything.
        self.assertIn(str(empty), cell)
        # An asked-for queue must never be reported with the idle word.
        self.assertNotIn("off", cell)
        body = [ln for ln in r.stdout.splitlines() if ln.strip()]
        self.assertEqual(len(body), 1)

    def test_requested_queue_with_no_worklog_anywhere_is_an_error(self):
        # RED before the fix: also printed "queue: off (no WORKLOG_BIN)".
        # In-process so both fallback roots can be emptied: $HOME and the
        # skill's own sibling directory are real on a dev box, and a
        # subprocess would resolve the developer's installed worklog and
        # pass for the wrong reason.
        home = Path(self._tmp.name) / "home"
        (home / ".claude/skills").mkdir(parents=True)
        siblings = Path(self._tmp.name) / "skills"
        siblings.mkdir()
        with mock.patch.dict(os.environ, {"HOME": str(home)}, clear=False), \
                mock.patch.object(loop_run, "SKILL_DIR", siblings / "loop-engineering"):
            os.environ.pop("WORKLOG_BIN", None)
            found, why = loop_run.resolve_project_sh()
            self.assertIsNone(found)
            self.assertIn("no WORKLOG_BIN", why)
            cell, slug = loop_run.queue_line("prog-x")
        self.assertIsNone(slug)
        self.assertTrue(cell.startswith("queue: error="), cell)
        self.assertNotIn("off", cell)

    def test_installed_worklog_resolves_without_worklog_bin(self):
        # GREEN half of the pair: the fallback must actually find an installed
        # skill, or the two RED cases above would pass on a resolver that can
        # only ever fail.
        home = Path(self._tmp.name) / "home"
        bin_dir = home / ".claude/skills/worklog/bin"
        bin_dir.mkdir(parents=True)
        (bin_dir / "project.sh").write_text("#!/bin/sh\necho task-alpha\n")
        siblings = Path(self._tmp.name) / "skills"
        siblings.mkdir()
        with mock.patch.dict(os.environ, {"HOME": str(home)}, clear=False), \
                mock.patch.object(loop_run, "SKILL_DIR", siblings / "loop-engineering"):
            os.environ.pop("WORKLOG_BIN", None)
            found, why = loop_run.resolve_project_sh()
        self.assertIsNone(why)
        self.assertEqual(found, bin_dir / "project.sh")


    def test_corrupt_config_rejected_without_transition(self):
        self.init_run()
        config = Path(self.run_dir) / "run.json"
        state = Path(self.run_dir) / "loop_state.json"
        for corrupt in ["{", "[]", '{"repo": true}', None]:
            if corrupt is None:
                config.unlink(missing_ok=True)
            else:
                config.write_text(corrupt)
            before = state.read_bytes()
            r = run([self.run_dir, "--evidence", "command: check — ok"], cwd=self.cwd)
            self.assertEqual(r.returncode, 3, r.stdout)
            self.assertEqual(state.read_bytes(), before)
            self.assertEqual(config.read_text() if config.exists() else None, corrupt)

    def test_rejected_calls_do_not_change_config(self):
        self.init_run()
        config = Path(self.run_dir) / "run.json"
        before = config.read_bytes()
        for args in [[], ["--stop", "complete"], ["--evidence", " "]]:
            r = run([self.run_dir, "--repo", "different"] + args, cwd=self.cwd)
            self.assertNotEqual(r.returncode, 0)
            self.assertEqual(config.read_bytes(), before)

    def test_remote_selection_on_later_cli_invocation(self):
        self.init_run()
        argv_file = Path(self._tmp.name)/"argv"
        stub = Path(self._tmp.name)/"radar"
        stub.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > " + shlex.quote(str(argv_file))
                        + "\necho '{\"comparable\":true,\"warn\":0,\"overlaps\":[],\"remote_fetch\":\"stale\"}'\n")
        stub.chmod(0o755)
        argv = [str(LOOP_RUN), self.run_dir, "--repo", "fixture", "--evidence", "command: check — ok", "--radar-remote"]
        out = io.StringIO()
        with mock.patch.object(sys, "argv", argv), mock.patch.object(loop_run, "CREW_RADAR", stub), redirect_stdout(out):
            self.assertEqual(loop_run.main(), 0)
        self.assertIn("--remote", argv_file.read_text().splitlines())
        self.assertIn("remote=stale", out.getvalue())
        self.assertTrue(json.loads((Path(self.run_dir)/"run.json").read_text())["remote"])

    def test_concurrent_config_changes_are_not_lost(self):
        self.init_run()
        env = {**os.environ, "WORKLOG_BIN":str(Path(self._tmp.name)/"absent")}
        common = [sys.executable, str(LOOP_RUN), self.run_dir, "--evidence", "command: concurrent — ok"]
        procs = [subprocess.Popen(common + args, cwd=self.cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                 for args in [["--project","prog-x"], ["--radar-remote"]]]
        for proc in procs:
            stdout, stderr = proc.communicate(timeout=20)
            self.assertEqual(proc.returncode, 0, (stdout,stderr))
        config = json.loads((Path(self.run_dir)/"run.json").read_text())
        self.assertEqual(config["project"], "prog-x")
        self.assertTrue(config["remote"])
        self.assertEqual(json.loads((Path(self.run_dir)/"loop_state.json").read_text())["budget"]["used"],2)

    def test_permission_denied_probe_still_reports_stopped(self):
        self.init_run(["--project", "prog-x"])
        stub_bin = Path(self._tmp.name)/"wbin"
        stub_bin.mkdir()
        (stub_bin/"project.sh").write_text("not executable")
        r = run([self.run_dir, "--stop", "complete", "--verification", "command: test — passed"],
                env_extra={"WORKLOG_BIN":str(stub_bin)}, cwd=self.cwd)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("queue: error=", r.stdout)
        self.assertIn("decide: stopped", r.stdout)
        state = json.loads((Path(self.run_dir)/"loop_state.json").read_text())
        self.assertEqual(state["terminal_status"], "complete")
        self.assertEqual(state["budget"]["used"], 0)

    def test_probe_timeout_has_a_bounded_error(self):
        stub_bin = self._stub("#!/bin/sh\nsleep 60 &\nwait\n")
        with mock.patch.dict(os.environ, {"WORKLOG_BIN":stub_bin}), mock.patch.object(loop_run, "QUEUE_TIMEOUT", 0.05), \
                mock.patch.object(loop_run, "RADAR_TIMEOUT", 0.05):
            self.assertIn("error=timeout", loop_run.queue_line("prog-x")[0])
            with mock.patch.object(loop_run, "CREW_RADAR", Path(stub_bin)/"project.sh"):
                self.assertIn("error=timeout", loop_run.radar_line("repo"))

    def test_slow_radar_outlives_queue_budget_and_preserves_verdict(self):
        payload = {"warn":1, "info":0, "overlaps":[{"severity":"warn", "path":"shared.py"}]}
        stub_bin = self._stub("#!/bin/sh\nsleep 0.2\nprintf '%s' " + shlex.quote(json.dumps(payload)) + "\nexit 2\n")
        with mock.patch.dict(os.environ, {"WORKLOG_BIN":stub_bin}), \
                mock.patch.object(loop_run, "QUEUE_TIMEOUT", 0.05), \
                mock.patch.object(loop_run, "RADAR_TIMEOUT", 2), \
                mock.patch.object(loop_run, "CREW_RADAR", Path(stub_bin)/"project.sh"):
            line = loop_run.radar_line("repo", artifact_dir=Path(self._tmp.name))
            self.assertIn("radar: warn=1 info=0 paths=shared.py", line)
            saved = json.loads(next(Path(self._tmp.name).glob("radar-*.json")).read_text())
            self.assertEqual(saved["returncode"], 2)
            self.assertEqual(json.loads(saved["stdout"]), payload)
            self.assertEqual(loop_run.queue_line("prog-x")[0], "queue: error=timeout")

    @unittest.skipIf(os.name == "nt", "POSIX process-group cleanup")
    def test_timeout_kills_shell_grandchildren(self):
        marker = Path(self._tmp.name)/"survived"
        child = "import time; from pathlib import Path; time.sleep(0.4); Path(%r).touch()" % str(marker)
        stub_bin = self._stub("#!/bin/sh\n" + shlex.quote(sys.executable) + " -c " + shlex.quote(child) + " &\nwait\n")
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            loop_run.run_probe([str(Path(stub_bin)/"project.sh")], 0.1)
        self.assertLess(time.monotonic() - started, 2)
        time.sleep(0.5)
        self.assertFalse(marker.exists(), "grandchild survived timeout and wrote its marker")

    def test_radar_artifacts_are_immutable(self):
        with mock.patch.object(loop_run, "run_probe") as probe:
            for name in ("first", "second"):
                probe.return_value = subprocess.CompletedProcess([],2,json.dumps({"warn":1,"info":0,"overlaps":[{"severity":"warn","path":name}]}),"")
                loop_run.radar_line("repo", artifact_dir=Path(self._tmp.name))
        files = list(Path(self._tmp.name).glob("radar*.json"))
        self.assertEqual(len(files),2)
        self.assertEqual({json.loads(json.loads(p.read_text())["stdout"])["overlaps"][0]["path"] for p in files},{"first","second"})

    def test_inconsistent_radar_is_an_error(self):
        for code, data in [(0,{"warn":1,"info":0,"overlaps":[{"severity":"warn","path":"a"}]}),
                           (0,{"warn":0,"info":1,"overlaps":[{"severity":"unknown","path":"a"}]}),
                           (2,{"warn":1,"info":0,"overlaps":[]})]:
            with self.subTest(code=code,data=data):
                self.assertIn("radar: error=",self._radar_cell(code,json.dumps(data)))

    def test_mixed_radar_preview_and_full_artifact(self):
        overlaps = [{"severity":"warn", "path":f"warn-{i}"} for i in range(8)]
        overlaps += [{"severity":"info", "path":f"info-{i}"} for i in range(1000)]
        payload = {"warn":8,"info":1000,"overlaps":overlaps,"remote_fetch":"stale"}
        proc = subprocess.CompletedProcess([],2,json.dumps(payload),"")
        with mock.patch.object(loop_run, "run_probe", return_value=proc):
            line = loop_run.radar_line("repo", remote=True, artifact_dir=Path(self._tmp.name))
        self.assertIn("warn=8 info=1000", line)
        self.assertIn("omitted=3", line)
        self.assertIn("remote=stale", line)
        self.assertNotIn("info-0", line)
        self.assertNotIn("warn-5", line)
        self.assertLess(len(line.encode()), 600)
        saved = json.loads(next(Path(self._tmp.name).glob("radar-*.json")).read_text())
        self.assertEqual(json.loads(saved["stdout"])["overlaps"], overlaps)


if __name__ == "__main__":
    unittest.main()
