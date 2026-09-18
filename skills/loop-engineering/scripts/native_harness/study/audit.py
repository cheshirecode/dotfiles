"""Replay retained repairs and reconcile receipts after all planned processes finish.

This post-processing audit uses the frozen controller, not the current checkout.
It makes no model calls and never changes original attempt artifacts.
"""

import hashlib
import json
from pathlib import Path
import sys
import tempfile


def audit(root):
    root = Path(root).resolve()
    sys.path.insert(0, str(root / "controller" / "study"))
    sys.path.insert(0, str(root / "controller"))
    from corpus import BY_NAME
    from evaluate import grade, prepare
    from harness_usage import normalize_claude, normalize_codex
    from opencode_usage import normalize_opencode
    from run import acceptance

    manifest = json.loads((root / "manifest.json").read_text())
    pending = [
        plan["id"]
        for plan in manifest["schedule"]
        if not (root / (plan["id"] + ".process.json")).exists()
    ]
    if pending:
        raise ValueError("Processes not terminal: " + ", ".join(pending))
    for name, digest in manifest["source_sha256"].items():
        if (
            hashlib.sha256((root / "controller" / name).read_bytes()).hexdigest()
            != digest
        ):
            raise ValueError("Frozen source changed: " + name)
    rows = []
    for plan in manifest["schedule"]:
        process = root / (plan["id"] + ".process.json")
        if not process.exists():
            raise ValueError("Process not terminal: " + plan["id"])
        output = root / "attempts" / plan["id"]
        result_path = output / "result.json"
        row = {"id": plan["id"], "issues": []}
        if not result_path.exists():
            row["issues"].append("terminal process without final receipt")
            rows.append(row)
            continue
        result = json.loads(result_path.read_text())
        task = BY_NAME[plan["task"]]
        for key in ("id", "harness", "model", "arm", "task", "position"):
            if result[key] != plan[key]:
                row["issues"].append("identity mismatch: " + key)
        if result["source_sha256"] != manifest["source_sha256"]:
            row["issues"].append("source provenance mismatch")
        expected_version = manifest["versions"][plan["harness"]]["version"]
        if result.get("observed_cli_version") != expected_version:
            row["issues"].append("observed CLI version differs from freeze")
        exit_code = json.loads(process.read_text())["returncode"]
        if (exit_code == 0) != result["accepted"]:
            row["issues"].append("process exit differs from acceptance")
        source = output / "repaired-source.txt"
        if source.exists():
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            if digest != result.get("source_receipt", {}).get("source", {}).get(
                "sha256"
            ):
                row["issues"].append("retained repair hash mismatch")
            with tempfile.TemporaryDirectory(prefix="study-replay-") as temporary:
                prepare(task, temporary)
                (Path(temporary) / task.filename).write_bytes(source.read_bytes())
                replay = grade(task, temporary)
            row["replayed_checks"] = replay
            if replay != result.get("final"):
                row["issues"].append("retained repair grade differs on replay")
        elif result.get("final"):
            row["issues"].append("graded repair missing from retained evidence")
        turn = result.get("turn", {})
        if turn:
            agent = output / "agent"
            if plan["harness"] == "codex":
                normalized = normalize_codex(
                    turn, json.loads((agent / "thread.json").read_text()), plan["model"]
                )
            else:
                events = [
                    json.loads(line)
                    for line in (agent / "events.jsonl").read_text().splitlines()
                ]
                if plan["harness"] == "claude":
                    normalized = normalize_claude(events, turn["exit"], plan["model"])
                else:
                    normalized = normalize_opencode(
                        events,
                        json.loads((agent / "resolved-model.json").read_text()),
                        turn["exit"],
                        plan["model"],
                    )
            row["reconciled_usage_matches"] = normalized == turn.get("native_usage")
            if not row["reconciled_usage_matches"]:
                row["issues"].append("native usage differs on reconciliation")
        accepted = (
            not result.get("error_type")
            and not result.get("cleanup_error_type")
            and acceptance(
                task,
                turn,
                result.get("final", {}),
                result.get("source_receipt", {}),
                result.get("public_calls", []),
                result["seconds_including_setup"],
            )
        )
        if bool(accepted) != result["accepted"]:
            row["issues"].append("acceptance differs on replay")
        rows.append(row)
    report = {
        "scheduled": len(manifest["schedule"]),
        "audited": len(rows),
        "issues": sum(bool(row["issues"]) for row in rows),
        "rows": rows,
    }
    (root / "audit.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    result = audit(sys.argv[1])
    print(json.dumps({key: result[key] for key in ("scheduled", "audited", "issues")}))
    raise SystemExit(bool(result["issues"]))
