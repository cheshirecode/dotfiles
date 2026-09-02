#!/usr/bin/env python3
"""Single-invocation loop driver: one command per cycle, no mode parameters.

Wraps loop_state.py and defaults the orchestrator and crew mechanics so an
agent never chooses a mode:

- first call with --goal auto-initializes a bounded run in RUN_DIR
- crew: when a repo is known (--repo, or the cwd's git toplevel at init),
  bin/crew-radar runs on every cycle and its verdict is folded into the line
- orchestrator: when a worklog project is configured (--project plus
  $WORKLOG_BIN), the next eligible child task is folded into the line
- every later call either advances (--evidence) or stops (--stop)

The driver prints exactly one line per call. Its tail is the only decision
left to the model: `decide: continue or stop` (or `decide: stopped`).

Exit codes match loop_state.py: 0 success, 2 usage, 3 contract rejection.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
LOOP_STATE = SKILL_DIR / "scripts" / "loop_state.py"
CREW_RADAR = SKILL_DIR / "bin" / "crew-radar"

# Single source of truth for status classification; a hand-copy here already
# caused one live bug (--stop cancelled rejected a defaulted next_action).
from loop_state import RESUMABLE_STATUSES, TERMINAL_STATUSES  # noqa: E402

TERMINAL = TERMINAL_STATUSES


def loop_state(args):
    """Run loop_state.py; return (rc, one-line stdout)."""
    proc = subprocess.run(
        [sys.executable, str(LOOP_STATE)] + args + ["--quiet"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
    return proc.returncode, proc.stdout.strip()


def radar_line(repo):
    """One radar verdict cell; never fails the cycle."""
    if not repo:
        return "radar: off"
    try:
        proc = subprocess.run(
            [str(CREW_RADAR), "--json", repo], capture_output=True, text=True
        )
        data = json.loads(proc.stdout)
    except (OSError, ValueError):
        return "radar: error=unrunnable"
    if data.get("error"):
        return "radar: error=%s" % data["error"]
    paths = [o.get("path", "?") for o in data.get("overlaps") or []]
    if proc.returncode == 0 and not paths:
        return "radar: clean"
    return "radar: warn=%s paths=%s" % (
        data.get("warn", "?"),
        ",".join(paths) or "-",
    )


def queue_line(project):
    """One project-queue cell; never fails the cycle."""
    if not project:
        return "queue: off", None
    worklog_bin = os.environ.get("WORKLOG_BIN")
    project_sh = Path(worklog_bin) / "project.sh" if worklog_bin else None
    if not project_sh or not project_sh.exists():
        return "queue: off (no WORKLOG_BIN)", None
    proc = subprocess.run(
        [str(project_sh), "next", project], capture_output=True, text=True
    )
    out = (proc.stdout + proc.stderr).strip()
    if proc.returncode == 0 and out:
        slug = out.splitlines()[-1].strip()
        return "queue: %s" % slug, slug
    if "nothing left" in out:
        return "queue: empty", None
    return "queue: blocked", None


def main():
    parser = argparse.ArgumentParser(
        description="One call per loop cycle; everything but the "
        "continue/stop decision is defaulted."
    )
    parser.add_argument("run_dir", help="directory holding this run's state")
    parser.add_argument("--goal", help="first call only: success condition")
    parser.add_argument("--budget", type=int, default=20)
    parser.add_argument("--evidence", help="one typed line for this cycle")
    parser.add_argument("--next-action", dest="next_action")
    parser.add_argument("--stop", choices=sorted(TERMINAL))
    parser.add_argument("--verification")
    parser.add_argument("--repo", help="repo for the crew radar (default: "
                        "cwd git toplevel at init)")
    parser.add_argument("--project", help="worklog project slug for the "
                        "orchestrator queue")
    parser.add_argument("--allowed-effect", dest="allowed_effect",
                        default="read-only until a wider effect is declared")
    parser.add_argument("--approval-boundary", dest="approval_boundary",
                        default="no merge, deploy, publish, or force-push")
    ns = parser.parse_args()

    run_dir = Path(ns.run_dir)
    state = run_dir / "loop_state.json"
    config_path = run_dir / "run.json"

    if not state.exists():
        if not ns.goal:
            parser.error("--goal is required on the first call for a run dir")
        run_dir.mkdir(parents=True, exist_ok=True)
        repo = ns.repo
        if repo is None:
            probe = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True,
                text=True,
            )
            repo = probe.stdout.strip() if probe.returncode == 0 else ""
        config = {"repo": repo or "", "project": ns.project or ""}
        config_path.write_text(json.dumps(config))
        rc, line = loop_state([
            "init", "--state", str(state),
            "--goal", ns.goal,
            "--evidence", ns.evidence or "artifact: %s — run initialized"
            % run_dir,
            "--budget-unit", "turns",
            "--budget-limit", str(ns.budget),
            "--next-action", ns.next_action or "first cycle",
            "--allowed-effect", ns.allowed_effect,
            "--approval-boundary", ns.approval_boundary,
        ])
    else:
        try:
            config = json.loads(config_path.read_text())
        except (OSError, ValueError):
            config = {"repo": "", "project": ""}
        if ns.repo is not None:
            config["repo"] = ns.repo
        if ns.project is not None:
            config["project"] = ns.project
        config_path.write_text(json.dumps(config))
        if ns.stop:
            if ns.stop == "complete" and not ns.verification:
                parser.error("--verification is required with --stop complete")
            args = [
                "finish", "--state", str(state),
                "--status", ns.stop,
                "--evidence", ns.evidence or "command: run stopped — %s"
                % ns.stop,
            ]
            if ns.verification:
                args += ["--verification", ns.verification]
            # Resumable stops need a replay action; non-resumable ones
            # (complete, cancelled) reject any next_action.
            if ns.stop in RESUMABLE_STATUSES:
                args += ["--next-action", ns.next_action
                         or "replay the check that stopped this run"]
            rc, line = loop_state(args)
        else:
            if not ns.evidence:
                parser.error(
                    "--evidence is required to advance (or use --stop)"
                )
            rc, line = loop_state([
                "advance", "--state", str(state),
                "--evidence", ns.evidence,
                "--next-action", ns.next_action
                or "claim next queue task or run next cycle",
            ])

    if rc != 0:
        return rc

    q_line, _slug = queue_line(config.get("project"))
    status = line.split(" ", 1)[0]
    decide = "stopped" if status in TERMINAL else "continue or stop"
    print("%s | %s | %s | decide: %s" % (
        line, radar_line(config.get("repo")), q_line, decide,
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
