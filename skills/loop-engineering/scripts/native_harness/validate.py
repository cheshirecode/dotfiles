"""Run one paid native-harness smoke test in a disposable synthetic repository."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from app_server import AppServer, validate_model
from claude_server import ClaudeServer
from opencode_server import OpenCodeServer
from integrity import git_snapshot, source_snapshot, source_receipt
from harness_usage import normalize_codex


CHECK_NAMES = ("status-ready", "schema-preserved", "label-preserved", "only-declared-fields")


def grade(workspace):
    path = Path(workspace) / "fixture.json"
    try:
        if path.is_symlink() or path.stat().st_size > 4096:
            raise ValueError("Not a bounded regular fixture")
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            raise ValueError("Not an object")
    except (OSError, ValueError):
        data = {}
    values = (data.get("status") == "ready", type(data.get("schema")) is int and data["schema"] == 1,
              data.get("label") == "native harness fixture", set(data) == {"status", "schema", "label"})
    return {"checks": [{"name": name, "pass": passed} for name, passed in zip(CHECK_NAMES, values)],
            "passed": sum(values), "total": len(CHECK_NAMES), "success": all(values)}


def accepted(turn, final, receipt, public_calls):
    checks = final.get("checks", [])
    return (len(checks) == len(CHECK_NAMES)
            and {row.get("name") for row in checks} == set(CHECK_NAMES)
            and all(row.get("pass") is True for row in checks)
            and final.get("passed") == len(CHECK_NAMES) and final.get("total") == len(CHECK_NAMES)
            and final.get("success") is True and receipt.get("valid") is True
            and bool(public_calls) and public_calls[-1].get("success") is True
            and turn.get("status") == "completed" and turn.get("usage_complete") is True
            and turn.get("timing", {}).get("timing_valid") is True
            and turn.get("timing", {}).get("within_ceiling") is True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", required=True, choices=("codex", "claude", "opencode"))
    parser.add_argument("--model", required=True, help="Exact available model ID; Astra is excluded")
    parser.add_argument("--seconds", type=int, default=180)
    parser.add_argument("--output", type=Path, help="New private output directory; default: system temp")
    args = parser.parse_args()
    validate_model(args.model)
    if not 1 <= args.seconds <= 600:
        parser.error("--seconds must be between 1 and 600")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="native-harness-"))
    if args.output:
        output.mkdir(mode=0o700, parents=True, exist_ok=False)
    start = time.monotonic()
    result = {"harness": args.harness, "requested_model": args.model, "accepted": False,
              "scope": "Synthetic protocol smoke test; no reliability or savings claim",
              "host": {"platform": platform.system(), "python": platform.python_version()},
              "controller_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in Path(__file__).parent.glob("*.py")}}
    server = None
    public_calls = []
    try:
        version = subprocess.run([args.harness, "--version"], capture_output=True, text=True, timeout=15)
        if version.returncode:
            raise RuntimeError("Version probe failed")
        result["cli_version"] = version.stdout.strip()[:200]
        with tempfile.TemporaryDirectory(prefix="native-harness-work-") as temporary:
            workspace = Path(temporary)
            def git(*argv):
                subprocess.run(["git", *argv], cwd=workspace, check=True, capture_output=True)
            git("init", "-q")
            (workspace / "fixture.json").write_text(json.dumps(
                {"status": "pending", "schema": 1, "label": "native harness fixture"}, indent=2) + "\n")
            git("add", "--", "fixture.json")
            git("-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
                "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture")
            before_source, before_git = source_snapshot(workspace), git_snapshot(workspace)
            result["before"] = grade(workspace)
            def verify():
                value = grade(workspace)
                value["source_receipt"] = source_receipt(workspace, "fixture.json", before_source, before_git)
                public_calls.append(value)
                return value
            server = {"codex": AppServer, "claude": ClaudeServer, "opencode": OpenCodeServer}[args.harness](
                output / "agent", model=args.model)
            server.start(workspace, developer_instructions=(
                "This is a synthetic validation. Read and edit only fixture.json in this workspace. "
                "Do not delegate, use the network, change Git, or read credentials/configuration. "
                "Use the provided verify_work_order tool after the edit."), public_verifier=verify)
            turn = server.turn("Change only status in fixture.json from pending to ready. Preserve the other "
                               "fields. Call verify_work_order with empty arguments, then report the result.",
                               seconds=args.seconds)
            if args.harness == "codex":
                native = normalize_codex(turn, json.loads((output / "agent/thread.json").read_text()), args.model)
                turn["native_usage"] = native
                turn["usage_complete"] = native["usage_complete"]
            final = grade(workspace)
            receipt = source_receipt(workspace, "fixture.json", before_source, before_git)
            result.update(turn=turn, final=final, source_receipt=receipt,
                          accepted=accepted(turn, final, receipt, public_calls))
    except Exception as error:
        # Child-process errors may contain environment or response data.
        # Native adapters own sanitized diagnostic artifacts.
        result["error_type"] = type(error).__name__
    finally:
        if server is not None:
            server.close()
        result["public_calls"] = public_calls
        result["seconds_including_setup"] = round(time.monotonic() - start, 3)
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"accepted": result["accepted"], "artifact": str(output / "result.json"),
                      "harness": args.harness, "error_type": result.get("error_type")}))
    return 0 if result["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
