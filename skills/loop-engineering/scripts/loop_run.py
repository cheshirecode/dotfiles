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
import hashlib
import json
import os
import re
import signal
import tempfile
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
LOOP_STATE = SKILL_DIR / "scripts" / "loop_state.py"
CREW_RADAR = SKILL_DIR / "bin" / "crew-radar"

# Single source of truth for status classification; a hand-copy here already
# caused one live bug (--stop cancelled rejected a defaulted next_action).
from loop_state import RESUMABLE_STATUSES, TERMINAL_STATUSES, state_lock  # noqa: E402

TERMINAL = TERMINAL_STATUSES
# Local radar measured ~0.55s; allow headroom without an unbounded cycle.
PROBE_TIMEOUT = 10


def write_json(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix="." + path.name)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(value, out)
            out.write("\n")
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def run_probe(cmd):
    # Kill the POSIX process group, including shell grandchildren, on timeout.
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, errors="replace", start_new_session=os.name != "nt")
    try:
        stdout, stderr = proc.communicate(timeout=PROBE_TIMEOUT)
    except subprocess.TimeoutExpired:
        if os.name != "nt":
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            proc.kill()
        proc.communicate()
        raise
    return subprocess.CompletedProcess(cmd, proc.returncode, stdout, stderr)


# A worklog task slug: one bare token. project.sh prints nothing else on
# stdout when it finds one, so anything wider is a broken contract, not a task.
QUEUE_SLUG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\Z")


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


def radar_line(repo, remote=False, artifact_dir=None):
    """Bounded verdict preview; full probe output stays in the run artifact."""
    if not repo:
        return "radar: off"
    cmd = [str(CREW_RADAR), "--json"]
    if remote:
        cmd.append("--remote")
    cmd.append(repo)
    ref = ""
    try:
        proc = run_probe(cmd)
        if artifact_dir is not None:
            captured = {"returncode":proc.returncode, "stdout":proc.stdout, "stderr":proc.stderr}
            digest = hashlib.sha256(json.dumps(captured, sort_keys=True).encode()).hexdigest()[:20]
            artifact = Path(artifact_dir) / ("radar-" + digest + ".json")
            write_json(artifact, captured)
            ref = " artifact=" + str(artifact)
        data = json.loads(proc.stdout)
        if not isinstance(data, dict):
            raise ValueError("radar result is not an object")
    except subprocess.TimeoutExpired:
        return "radar: error=timeout"
    except (OSError, ValueError):
        return "radar: error=unrunnable" + ref
    freshness = " remote=" + cell(str(data.get("remote_fetch", "unknown"))) if remote else ""
    if data.get("error") or proc.returncode not in (0, 2):
        reason = str(data.get("error") or proc.stderr.strip() or "exit %d" % proc.returncode)
        return "radar: error=" + cell(reason[:160] if ref else reason) + ref + freshness
    overlaps = data.get("overlaps") or []
    if not isinstance(overlaps, list) or any(not isinstance(o, dict) for o in overlaps):
        return "radar: error=invalid-overlaps" + ref + freshness
    if any(o.get("severity") not in ("warn", "info") or not isinstance(o.get("path"), str) for o in overlaps):
        return "radar: error=invalid-overlaps" + ref + freshness
    warn_count = sum(o["severity"] == "warn" for o in overlaps)
    info_count = len(overlaps) - warn_count
    if (type(data.get("warn")) is not int or data["warn"] != warn_count
            or ("info" in data and (type(data["info"]) is not int or data["info"] != info_count))
            or (proc.returncode == 2) != (warn_count > 0)):
        return "radar: error=inconsistent-verdict" + ref + freshness
    selected = [o for o in overlaps if o.get("severity") == ("warn" if proc.returncode == 2 else "info")]
    paths = ",".join(str(o.get("path", "?")) for o in selected[:5])
    preview = (" paths=" + cell(paths)) if paths else ""
    if len(selected) > 5:
        preview += " omitted=%d" % (len(selected) - 5)
    if proc.returncode == 0:
        if overlaps:
            return "radar: info=%d%s%s%s" % (len(selected), preview, ref, freshness)
        verdict = "single-owner" if data.get("comparable") is False else "clean"
        return "radar: " + verdict + freshness
    warn = data.get("warn")
    if not isinstance(warn, int) or isinstance(warn, bool) or warn < 0:
        return "radar: error=exit 2 carried no warn count" + ref + freshness
    info = sum(o.get("severity") == "info" for o in overlaps)
    return "radar: warn=%d info=%d%s%s%s" % (warn, info, preview, ref, freshness)


def cell(text):
    """Collapse text into one driver-line cell: single line, no separator.

    No length cap: a capped cell clipped filesystem paths out of queue
    errors (macOS /var/folders tmp roots at 80; any fixed cap loses to a
    long enough path), making "wrong copy" read like "no copy". Line
    integrity comes from the collapse and the pipe swap, not from length.
    """
    return " ".join(text.split()).replace("|", "/")


def resolve_project_sh():
    """Locate the worklog skill's project.sh, or return (None, reason).

    $WORKLOG_BIN is the source of truth, but two worklog checkouts can exist
    on one machine (an installed skill and a working tree) and a profile can
    export the variable at the wrong one. Honour the variable first, then fall
    back to the installed skill roots so the driver works in development, and
    say which candidates were tried when none resolves -- "not found" and
    "found the other copy" must not read the same.
    """
    env_bin = os.environ.get("WORKLOG_BIN")
    if env_bin:
        candidate = Path(env_bin) / "project.sh"
        if candidate.exists():
            return candidate, None
        return None, "WORKLOG_BIN=%s has no project.sh" % env_bin
    home = Path(os.path.expanduser("~"))
    roots = [
        home / ".claude/skills/worklog/bin",
        home / ".agents/skills/worklog/bin",
        home / ".cursor/skills/worklog/bin",
        SKILL_DIR.parent / "worklog/bin",
    ]
    for root in roots:
        candidate = root / "project.sh"
        if candidate.exists():
            return candidate, None
    return None, "no WORKLOG_BIN and no worklog skill at %s" % ", ".join(
        str(r) for r in roots
    )


def queue_line(project):
    """One project-queue cell; never fails the cycle."""
    if not project:
        return "queue: off", None
    # A queue the caller asked for and did not get is a configuration failure,
    # not an idle one. Reporting it as "off" -- the same word used when no
    # --project was passed -- hides a mistyped or wrongly-pointed WORKLOG_BIN
    # behind a cell that reads as "nothing to do here".
    project_sh, why = resolve_project_sh()
    if project_sh is None:
        return "queue: error=%s" % cell(why), None
    try:
        proc = run_probe([str(project_sh), "next", project, "--json"])
    except subprocess.TimeoutExpired:
        return "queue: error=timeout", None
    except OSError as exc:
        return "queue: error=" + cell(str(exc)), None
    try:
        data = json.loads(proc.stdout)
        if (not isinstance(data, dict) or data.get("schema_version") != "worklog-project-next/v1"
                or data.get("project") != project):
            raise ValueError("invalid queue schema")
        status = data.get("status")
        slug = data.get("task")
        expected_rc = 0 if status == "eligible" else 1
        if proc.returncode != expected_rc:
            raise ValueError("queue status/exit mismatch")
        if status == "eligible" and isinstance(slug, str) and QUEUE_SLUG.fullmatch(slug):
            return "queue: " + slug, slug
        if slug is not None:
            raise ValueError("invalid queue task")
        if status in ("empty", "blocked"):
            return "queue: " + status, None
        if status in ("error", "missing"):
            return "queue: error=" + cell(str(data.get("reason") or status)), None
        raise ValueError("invalid queue status")
    except (ValueError, TypeError) as exc:
        return "queue: error=" + cell(proc.stderr.strip() or str(exc)), None


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
    parser.add_argument("--radar-remote", dest="radar_remote",
                        action="store_true",
                        help="include pushed remote branches as radar owners; "
                             "needed only for peers with no local worktree "
                             "(remote-isolated subagents, other machines)")
    parser.add_argument("--project", help="worklog project slug for the "
                        "orchestrator queue")
    parser.add_argument("--allowed-effect", dest="allowed_effect",
                        default="read-only until a wider effect is declared")
    parser.add_argument("--approval-boundary", dest="approval_boundary",
                        default="no merge, deploy, publish, or force-push")
    ns = parser.parse_args()

    try:
        with state_lock(Path(ns.run_dir) / "driver"):
            return drive(ns, parser)
    except (OSError, ValueError) as exc:
        print("loop-run: " + str(exc), file=sys.stderr)
        return 3


def drive(ns, parser):
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
        config = {"repo": repo or "", "project": ns.project or "",
                  "remote": bool(ns.radar_remote)}
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
        except (OSError, ValueError) as exc:
            raise ValueError(f"invalid run configuration {config_path}: {exc}") from exc
        if (not isinstance(config, dict) or not isinstance(config.get("repo"), str)
                or not isinstance(config.get("project"), str)
                or not isinstance(config.get("remote", False), bool)):
            raise ValueError(f"invalid run configuration {config_path}")
        if ns.radar_remote:
            config["remote"] = True
        if ns.repo is not None:
            config["repo"] = ns.repo
        if ns.project is not None:
            config["project"] = ns.project
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

    # Only successful transitions persist configuration. The driver lock covers
    # read/transition/write so concurrent invocations cannot lose an update.
    write_json(config_path, config)
    q_line, _slug = queue_line(config.get("project"))
    status = line.split(" ", 1)[0]
    decide = "stopped" if status in TERMINAL else "continue or stop"
    print("%s | %s | %s | decide: %s" % (
        line, radar_line(config.get("repo"), config.get("remote", False), run_dir),
        q_line, decide,
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
