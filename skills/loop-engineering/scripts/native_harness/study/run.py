"""Run the fixed 144-invocation study; never replace failed or interrupted attempts."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import signal
import subprocess
import sys
import tempfile
import time

STUDY = Path(__file__).resolve().parent
NATIVE = STUDY.parent
sys.path.insert(0, str(NATIVE))
from app_server import AppServer  # noqa: E402
from claude_server import ClaudeServer  # noqa: E402
from harness_usage import normalize_codex  # noqa: E402
from integrity import git_snapshot, source_snapshot, source_receipt  # noqa: E402
from opencode_server import OpenCodeServer  # noqa: E402
from corpus import TASKS, BY_NAME  # noqa: E402
from evaluate import grade, prepare  # noqa: E402

MODELS = {
    "claude": "claude-haiku-4-5-20251001",
    "codex": "gpt-5.6-sol",
    "opencode": "openrouter/anthropic/claude-haiku-4.5",
}
CANDIDATE = (
    "Work economically: inspect the declared source and only the supporting files "
    "needed for this repair. Batch independent reads when useful. Make the smallest "
    "correct change. After editing, use the public verifier; repeat it only if a "
    "failure or a further edit makes another check useful. Avoid rereading unchanged "
    "files and repeating successful checks. Give a concise final result."
)


def dump(path, value):
    path = Path(path)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2) + "\n")
    temp.replace(path)


def hashes():
    paths = (
        list(NATIVE.glob("*.py")) + list(STUDY.glob("*.py")) + [STUDY / "PROTOCOL.md"]
    )
    return {
        str(p.relative_to(NATIVE)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(paths)
    }


def schedule():
    rows = []
    for lane, harness in enumerate(MODELS):
        rng = random.Random(20260918 + lane)
        tasks = list(TASKS)
        rng.shuffle(tasks)
        orders = [False] * 12 + [True] * 12
        rng.shuffle(orders)
        for index, (task, reverse) in enumerate(zip(tasks, orders)):
            arms = ["candidate", "baseline"] if reverse else ["baseline", "candidate"]
            for position, arm in enumerate(arms):
                rows.append(
                    {
                        "id": f"{harness}-{index:02d}-{position}-{task.name}-{arm}",
                        "harness": harness,
                        "model": MODELS[harness],
                        "task": task.name,
                        "language": task.language,
                        "arm": arm,
                        "position": position,
                        "pair": index,
                        "seconds": 120,
                        "watchdog": 240,
                    }
                )
    return rows


def initialize(root):
    root = Path(root)
    if (root / "manifest.json").exists():
        raise ValueError("Study already frozen")
    calibration = json.loads((root / "calibration.json").read_text())
    if len(calibration) != 24 or any(
        r["broken"]["success"] or not r["reference"]["success"] for r in calibration
    ):
        raise ValueError(
            "Calibration must reject all originals and accept all references"
        )
    versions = {}
    for cli in MODELS:
        r = subprocess.run(
            [cli, "--version"], capture_output=True, text=True, timeout=15, check=True
        )
        versions[cli] = {"path": shutil.which(cli), "version": r.stdout.strip()}
    dump(
        root / "manifest.json",
        {
            "schema": 1,
            "seed": 20260918,
            "source_sha256": hashes(),
            "versions": versions,
            "schedule": schedule(),
            "candidate": CANDIDATE,
            "calibration_sha256": hashlib.sha256(
                (root / "calibration.json").read_bytes()
            ).hexdigest(),
            "git_revision": subprocess.check_output(
                ["git", "rev-parse", "HEAD"], text=True
            ).strip(),
        },
    )
    (root / "attempts").mkdir(mode=0o700)
    print(json.dumps({"frozen": str(root / "manifest.json"), "invocations": 144}))


def acceptance(task, turn, final, receipt, calls, elapsed):
    checks = final.get("checks", [])
    names = {task.name + ":case-" + str(i) for i in range(1, len(task.cases) + 1)}
    return (
        len(checks) == len(names)
        and {c.get("name") for c in checks} == names
        and all(c.get("pass") is True for c in checks)
        and final.get("success") is True
        and receipt.get("valid") is True
        and any(c.get("success") is True for c in calls)
        and turn.get("status") == "completed"
        and turn.get("usage_complete") is True
        and turn.get("native_usage", {}).get("model_valid") is True
        and turn.get("timing", {}).get("timing_valid") is True
        and turn.get("timing", {}).get("within_ceiling") is True
        and elapsed <= 240
    )


def single(root, ident):
    manifest = json.loads((root / "manifest.json").read_text())
    if hashes() != manifest["source_sha256"]:
        raise ValueError("Frozen controller has changed")
    row = next(r for r in manifest["schedule"] if r["id"] == ident)
    output = root / "attempts" / ident
    # A dispatch may be resumed for observation but is never executed twice.
    output.mkdir(mode=0o700, exist_ok=False)
    dump(
        output / "dispatch.json", {**row, "pid": os.getpid(), "started_at": time.time()}
    )
    task = BY_NAME[row["task"]]
    start = time.monotonic()
    result = {
        **row,
        "accepted": False,
        "behavior_success": False,
        "source_sha256": manifest["source_sha256"],
        "cli": manifest["versions"][row["harness"]],
    }
    server = None
    calls = []

    def expired(_sig, _frame):
        raise TimeoutError("Study watchdog")

    signal.signal(signal.SIGTERM, expired)
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(row["watchdog"])
    try:
        version = subprocess.run(
            [row["harness"], "--version"],
            capture_output=True,
            text=True,
            timeout=15,
            check=True,
        ).stdout.strip()
        result["observed_cli_version"] = version
        if version != manifest["versions"][row["harness"]]["version"]:
            raise ValueError("CLI version changed after study freeze")
        with tempfile.TemporaryDirectory(prefix="native-study-work-") as temporary:
            workspace = Path(temporary)
            prepare(task, workspace)

            def git(*args):
                subprocess.run(
                    ["git", *args], cwd=workspace, check=True, capture_output=True
                )

            git("init", "-q")
            git("add", "--", ".")
            git(
                "-c",
                "user.name=study",
                "-c",
                "user.email=study@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "-c",
                "core.hooksPath=/dev/null",
                "commit",
                "-qm",
                "fixture",
            )
            before, before_git = source_snapshot(workspace), git_snapshot(workspace)
            dump(
                output / "input.json",
                {
                    "source": before,
                    "git": before_git,
                    "contract": task.contract,
                    "filename": task.filename,
                },
            )

            def verify():
                value = grade(task, workspace, public=True)
                value["source_receipt"] = source_receipt(
                    workspace, task.filename, before, before_git
                )
                calls.append(value)
                dump(output / "public-calls.json", calls)
                return value

            instructions = (
                "Repair this synthetic software task. Read only files inside the assigned workspace. "
                "Edit only "
                + task.filename
                + ". Do not delegate, use the network, read credentials or "
                "configuration outside this workspace, or change Git. You must call the provided "
                "verify_work_order tool with empty arguments after your repair. It runs public "
                "examples; final acceptance also runs additional cases from the same contract. "
            )
            if row["arm"] == "candidate":
                instructions += CANDIDATE
            prompt = (
                task.contract
                + "\nRepair "
                + task.filename
                + ". Public examples are in README.md."
            )
            dump(output / "prompt.json", {"developer": instructions, "prompt": prompt})
            server = {
                "claude": ClaudeServer,
                "codex": AppServer,
                "opencode": OpenCodeServer,
            }[row["harness"]](output / "agent", model=row["model"])
            server.start(
                workspace, developer_instructions=instructions, public_verifier=verify
            )
            turn = server.turn(prompt, seconds=row["seconds"])
            if row["harness"] == "codex":
                native = normalize_codex(
                    turn,
                    json.loads((output / "agent/thread.json").read_text()),
                    row["model"],
                )
                turn["native_usage"] = native
                turn["usage_complete"] = native["usage_complete"]
            final = grade(task, workspace)
            receipt = source_receipt(workspace, task.filename, before, before_git)
            result.update(
                turn=turn,
                final=final,
                source_receipt=receipt,
                behavior_success=final["success"],
            )
            (output / "repaired-source.txt").write_text(
                (workspace / task.filename).read_text()
            )
    except Exception as error:
        result["error_type"] = type(error).__name__
    finally:
        # Cancel the watchdog before bounded adapter cleanup; cleanup time still counts.
        signal.alarm(0)
        if server is not None:
            try:
                server.close()
            except Exception as error:
                result["cleanup_error_type"] = type(error).__name__
        result["public_calls"] = calls
        result["seconds_including_setup"] = round(time.monotonic() - start, 3)
        result["accepted"] = (
            not result.get("error_type")
            and not result.get("cleanup_error_type")
            and acceptance(
                task,
                result.get("turn", {}),
                result.get("final", {}),
                result.get("source_receipt", {}),
                calls,
                result["seconds_including_setup"],
            )
        )
        dump(output / "result.json", result)
    print(
        json.dumps(
            {
                "id": ident,
                "accepted": result["accepted"],
                "error_type": result.get("error_type"),
            }
        )
    )
    return 0 if result["accepted"] else 1


def lane(root, harness):
    manifest = json.loads((root / "manifest.json").read_text())
    lock = root / (harness + ".lock")
    # Atomic exclusive ownership; a stale lock requires inspection, never blind rerun.
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(str(os.getpid()))
    try:
        for row in manifest["schedule"]:
            if row["harness"] != harness:
                continue
            output = root / "attempts" / row["id"]
            if output.exists():
                # Existing attempts are immutable even if their process died mid-receipt.
                continue
            with (root / (row["id"] + ".log")).open("w") as log:
                process = subprocess.Popen(
                    [
                        sys.executable,
                        str(Path(__file__).resolve()),
                        "single",
                        str(root),
                        "--id",
                        row["id"],
                    ],
                    stdout=log,
                    stderr=log,
                    start_new_session=True,
                )
                try:
                    code = process.wait(timeout=275)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try:
                        code = process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        code = process.wait(timeout=10)
                dump(
                    root / (row["id"] + ".process.json"),
                    {"returncode": code, "pid": process.pid},
                )
            print(json.dumps({"id": row["id"], "exit": code}), flush=True)
    finally:
        lock.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("init", "single", "lane"))
    parser.add_argument("root", type=Path)
    parser.add_argument("--id")
    parser.add_argument("--harness", choices=MODELS)
    args = parser.parse_args()
    if args.mode == "init":
        initialize(args.root)
    elif args.mode == "single":
        raise SystemExit(single(args.root, args.id))
    else:
        lane(args.root, args.harness)
