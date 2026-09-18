"""Disclosed sensitivity analysis for the recorded path-contract ambiguity.

Keep the primary 144-row ledger untouched. Exclude both arms of the named task
in each harness only in this separate output; retain its invocation costs here.
"""

import json
from pathlib import Path
import sys

from analyze import arm_summary, bootstrap, cost_ratio, mcnemar, wilson


def analyze_sensitivity(root):
    root = Path(root)
    manifest = json.loads((root / "manifest.json").read_text())
    lanes = {}
    excluded = []
    for plan in manifest["schedule"]:
        path = root / "attempts" / plan["id"] / "result.json"
        row = (
            json.loads(path.read_text())
            if path.exists()
            else {
                **plan,
                "accepted": False,
                "behavior_success": False,
                "error_type": "MissingResult",
            }
        )
        if plan["task"] == "path-containment":
            excluded.append(
                {
                    "id": plan["id"],
                    "accepted": row["accepted"],
                    "tokens": row.get("turn", {})
                    .get("native_usage", {})
                    .get("reported_tokens"),
                    "usage_complete": row.get("turn", {}).get("usage_complete", False),
                    "seconds": row.get("seconds_including_setup"),
                }
            )
            continue
        lanes.setdefault(plan["harness"], {}).setdefault(plan["task"], {})[
            plan["arm"]
        ] = row
    summaries = {}
    for lane, tasks in lanes.items():
        pairs = list(tasks.values())
        arms = {
            arm: arm_summary([p[arm] for p in pairs])
            for arm in ("baseline", "candidate")
        }
        b, c = arms["baseline"], arms["candidate"]
        complete = b["usage_complete"] and c["usage_complete"]
        bi, ci = (
            wilson(b["accepted"], len(pairs), 0.975),
            wilson(c["accepted"], len(pairs), 0.975),
        )
        b_only = sum(
            p["baseline"]["accepted"] and not p["candidate"]["accepted"] for p in pairs
        )
        c_only = sum(
            p["candidate"]["accepted"] and not p["baseline"]["accepted"] for p in pairs
        )
        summaries[lane] = {
            "arms": arms,
            "baseline_only": b_only,
            "candidate_only": c_only,
            "conservative_difference_95": [ci[0] - bi[1], ci[1] - bi[0]],
            "mcnemar_two_sided_p": mcnemar(b_only, c_only),
            "token_cost_ratio": cost_ratio(pairs) if complete else None,
            "token_cost_ratio_bootstrap_95": bootstrap(pairs) if complete else None,
        }
    result = {
        "analysis": "separately declared sensitivity; not the preregistered primary",
        "excluded_task": "path-containment",
        "excluded_attempts": excluded,
        "lanes": summaries,
    }
    (root / "sensitivity.json").write_text(
        json.dumps(result, indent=2, allow_nan=False) + "\n"
    )
    return result


if __name__ == "__main__":
    result = analyze_sensitivity(sys.argv[1])
    print(
        json.dumps(
            {
                k: {
                    "baseline": v["arms"]["baseline"]["accepted"],
                    "candidate": v["arms"]["candidate"]["accepted"],
                }
                for k, v in result["lanes"].items()
            }
        )
    )
