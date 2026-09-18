"""Reconcile truncated OpenCode exports without rerunning a model or rewriting trials."""

import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from opencode_server import export_metadata  # noqa: E402
from opencode_usage import normalize_opencode  # noqa: E402
from analyze import arm_summary, bootstrap, cost_ratio  # noqa: E402


def recover(root):
    root = Path(root)
    manifest = json.loads((root / "manifest.json").read_text())
    planned = [p for p in manifest["schedule"] if p["harness"] == "opencode"]
    if any(not (root / (p["id"] + ".process.json")).exists() for p in planned):
        raise ValueError("OpenCode lane is not terminal")
    recovery = root / "usage-recovery"
    recovery.mkdir(exist_ok=True)
    rows = {}
    recovered = []
    for plan in planned:
        source = root / "attempts" / plan["id"] / "result.json"
        original = source.read_bytes()
        result = json.loads(original)
        adjusted = copy.deepcopy(result)
        turn = result.get("turn", {})
        if turn and not turn.get("usage_complete"):
            output = recovery / plan["id"]
            sidecar = output / "recovery.json"
            if not sidecar.exists():
                output.mkdir(exist_ok=False)
                events = [
                    json.loads(line)
                    for line in (source.parent / "agent/events.jsonl")
                    .read_text()
                    .splitlines()
                ]
                sessions = {e["sessionID"] for e in events if e.get("sessionID")}
                receipt = {
                    "id": plan["id"],
                    "original_result_sha256": hashlib.sha256(original).hexdigest(),
                }
                start = time.monotonic()
                try:
                    if len(sessions) != 1:
                        raise ValueError("No unique retained session")
                    # Local export only: no credential loading and no inference turn.
                    metadata = export_metadata(
                        next(iter(sessions)),
                        root,
                        os.environ,
                        "unused-reconciliation-sentinel",
                        output,
                    )
                    usage = normalize_opencode(
                        events, metadata, turn["exit"], plan["model"]
                    )
                    receipt.update(native_usage=usage, exported_metadata=metadata)
                except Exception as error:
                    receipt["error_type"] = type(error).__name__
                receipt["reconciliation_seconds"] = round(time.monotonic() - start, 3)
                sidecar.write_text(json.dumps(receipt, indent=2) + "\n")
            receipt = json.loads(sidecar.read_text())
            if (
                receipt["original_result_sha256"]
                != hashlib.sha256(original).hexdigest()
            ):
                raise ValueError("Original result changed after reconciliation")
            usage = receipt.get("native_usage", {})
            recovered.append(
                {
                    "id": plan["id"],
                    "complete": usage.get("usage_complete", False),
                    "reported_tokens": usage.get("reported_tokens"),
                    "reconciliation_seconds": receipt["reconciliation_seconds"],
                }
            )
            if usage.get("usage_complete") is True:
                # This in-memory cost view keeps the original acceptance verdict.
                adjusted["turn"]["native_usage"] = usage
                adjusted["turn"]["usage_complete"] = True
            if source.read_bytes() != original:
                raise ValueError("Original result was modified")
        rows.setdefault(plan["task"], {})[plan["arm"]] = adjusted
    pairs = list(rows.values())
    arms = {
        arm: arm_summary([pair[arm] for pair in pairs])
        for arm in ("baseline", "candidate")
    }
    complete = all(arm["usage_complete"] for arm in arms.values())
    result = {
        "analysis": "supplementary recovered-cost view; original acceptance and primary analysis unchanged",
        "recovered": recovered,
        "arms": arms,
        "token_cost_ratio": cost_ratio(pairs) if complete else None,
        "token_cost_ratio_bootstrap_95": bootstrap(pairs) if complete else None,
    }
    (root / "recovered-costs.json").write_text(
        json.dumps(result, indent=2, allow_nan=False) + "\n"
    )
    return result


if __name__ == "__main__":
    result = recover(sys.argv[1])
    print(
        json.dumps(
            {
                "recovered": result["recovered"],
                "cost_ratio": result["token_cost_ratio"],
                "interval": result["token_cost_ratio_bootstrap_95"],
            }
        )
    )
