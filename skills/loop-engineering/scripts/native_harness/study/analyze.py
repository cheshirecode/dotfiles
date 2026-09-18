"""Predeclared paired analysis. Missing receipts never become free attempts."""

import json
import math
from pathlib import Path
import random
from statistics import NormalDist
import sys


def wilson(successes, total, confidence=0.95):
    if not total:
        return [0.0, 1.0]
    z = NormalDist().inv_cdf((1 + confidence) / 2)
    p = successes / total
    denom = 1 + z * z / total
    center = (p + z * z / (2 * total)) / denom
    half = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / denom
    return [max(0.0, center - half), min(1.0, center + half)]


def mcnemar(baseline_only, candidate_only):
    n = baseline_only + candidate_only
    if not n:
        return 1.0
    k = min(baseline_only, candidate_only)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / (2**n))


def arm_summary(rows):
    accepted = sum(r.get("accepted") is True for r in rows)
    usage = [r.get("turn", {}).get("native_usage", {}) for r in rows]
    complete = [
        r.get("turn", {}).get("usage_complete") is True
        and type(u.get("reported_tokens")) is int
        for r, u in zip(rows, usage)
    ]
    known_tokens = sum(
        u["reported_tokens"] for u in usage if type(u.get("reported_tokens")) is int
    )
    costs = [u.get("reported_cost_usd") for u in usage]
    cost_complete = all(complete) and all(type(c) in (float, int) for c in costs)
    seconds = [r.get("seconds_including_setup") for r in rows]
    return {
        "scheduled": len(rows),
        "accepted": accepted,
        "behavior_passed": sum(r.get("behavior_success") is True for r in rows),
        "acceptance_rate": accepted / len(rows),
        "wilson_95": wilson(accepted, len(rows)),
        "usage_complete_attempts": sum(complete),
        "usage_complete": all(complete),
        "known_reported_tokens_lower_bound": known_tokens,
        "tokens_per_accepted": known_tokens / accepted
        if all(complete) and accepted
        else None,
        "estimated_usd_total": sum(costs) if cost_complete else None,
        "estimated_usd_per_accepted": sum(costs) / accepted
        if cost_complete and accepted
        else None,
        "seconds_total": sum(seconds)
        if all(type(s) in (float, int) for s in seconds)
        else None,
        "seconds_per_accepted": sum(seconds) / accepted
        if accepted and all(type(s) in (float, int) for s in seconds)
        else None,
    }


def cost_ratio(pairs, endpoint="reported_tokens"):
    accepted = [
        sum(p[arm].get("accepted") is True for p in pairs)
        for arm in ("baseline", "candidate")
    ]
    if not all(accepted):
        return math.inf
    totals = [
        sum(p[arm]["turn"]["native_usage"][endpoint] for p in pairs)
        for arm in ("baseline", "candidate")
    ]
    if totals[0] <= 0:
        return math.inf
    return (totals[1] / accepted[1]) / (totals[0] / accepted[0])


def bootstrap(pairs, draws=10000):
    groups = {}
    for pair in pairs:
        groups.setdefault(pair["baseline"]["language"], []).append(pair)
    rng = random.Random(20260918)
    samples = []
    for _ in range(draws):
        chosen = [rng.choice(group) for group in groups.values() for _ in group]
        samples.append(cost_ratio(chosen))
    samples.sort()
    return [samples[int(draws * 0.025)], samples[min(draws - 1, int(draws * 0.975))]]


def analyze(root):
    root = Path(root)
    manifest = json.loads((root / "manifest.json").read_text())
    by_lane = {}
    ledger = []
    for planned in manifest["schedule"]:
        path = root / "attempts" / planned["id"] / "result.json"
        if path.exists():
            row = json.loads(path.read_text())
            for key in ("id", "harness", "model", "task", "arm", "position"):
                if row.get(key) != planned[key]:
                    raise ValueError(
                        "Result identity differs from schedule: " + planned["id"]
                    )
            if row.get("source_sha256") != manifest["source_sha256"]:
                raise ValueError("Result controller differs from frozen source")
            row["receipt_present"] = True
        else:
            row = {
                **planned,
                "accepted": False,
                "behavior_success": False,
                "receipt_present": False,
                "error_type": "MissingResult",
            }
        by_lane.setdefault(row["harness"], {}).setdefault(row["task"], {})[
            row["arm"]
        ] = row
        native = row.get("turn", {}).get("native_usage", {})
        ledger.append(
            {
                **planned,
                "accepted": row["accepted"],
                "behavior_passed": row.get("behavior_success"),
                "receipt_present": row["receipt_present"],
                "error_type": row.get("error_type"),
                "tokens": native.get("reported_tokens"),
                "usage_complete": row.get("turn", {}).get("usage_complete", False),
                "estimated_usd": native.get("reported_cost_usd"),
                "token_categories_by_model": native.get("models", {}),
                "usage_errors": row.get("turn", {}).get("usage_errors", []),
                "seconds_including_setup": row.get("seconds_including_setup"),
                "timing": row.get("turn", {}).get("timing"),
                "checks": [
                    {"name": c["name"], "pass": c["pass"]}
                    for c in row.get("final", {}).get("checks", [])
                ],
                "public_verifier_calls": len(row.get("public_calls", [])),
                "scope_ok": row.get("source_receipt", {}).get("scope_ok"),
                "git_unchanged": row.get("source_receipt", {}).get("git_unchanged"),
            }
        )
    lanes = {}
    for lane, tasks in by_lane.items():
        pairs = list(tasks.values())
        arms = {
            arm: arm_summary([p[arm] for p in pairs])
            for arm in ("baseline", "candidate")
        }
        b, c = arms["baseline"], arms["candidate"]
        b_only = sum(
            p["baseline"]["accepted"] and not p["candidate"]["accepted"] for p in pairs
        )
        c_only = sum(
            p["candidate"]["accepted"] and not p["baseline"]["accepted"] for p in pairs
        )
        bi = wilson(b["accepted"], len(pairs), 0.975)
        ci = wilson(c["accepted"], len(pairs), 0.975)
        diff = [ci[0] - bi[1], ci[1] - bi[0]]
        complete = b["usage_complete"] and c["usage_complete"]
        ratio = cost_ratio(pairs) if complete else None
        interval = bootstrap(pairs) if complete else None
        language = {}
        for name in sorted({p["baseline"]["language"] for p in pairs}):
            language[name] = {
                arm: arm_summary([p[arm] for p in pairs if p[arm]["language"] == name])
                for arm in ("baseline", "candidate")
            }
        order = {}
        for position in (0, 1):
            subset = [p for p in pairs if p["candidate"]["position"] == position]
            order[str(position)] = {
                "pairs": len(subset),
                "cost_ratio": cost_ratio(subset) if complete else None,
            }
        lanes[lane] = {
            "arms": arms,
            "baseline_only": b_only,
            "candidate_only": c_only,
            "mcnemar_two_sided_p": mcnemar(b_only, c_only),
            "acceptance_difference": c["acceptance_rate"] - b["acceptance_rate"],
            "conservative_difference_95": diff,
            "noninferior_5pp": diff[0] > -0.05,
            "token_cost_ratio": ratio,
            "token_cost_ratio_bootstrap_95": interval,
            "language": language,
            "candidate_order": order,
        }
    summary = {
        "scheduled": len(ledger),
        "receipts": sum(r["receipt_present"] for r in ledger),
        "git_revision": manifest["git_revision"],
        "source_sha256": manifest["source_sha256"],
        "versions": manifest["versions"],
        "lanes": lanes,
        "portable_winner": all(
            v["noninferior_5pp"]
            and v["token_cost_ratio_bootstrap_95"]
            and v["token_cost_ratio_bootstrap_95"][1] < 1
            for v in lanes.values()
        ),
    }

    # JSON has no infinities; retain them explicitly, never recode them as a cheap trial.
    def safe(value):
        if isinstance(value, float) and not math.isfinite(value):
            return "unbounded"
        if isinstance(value, dict):
            return {k: safe(v) for k, v in value.items()}
        if isinstance(value, list):
            return [safe(v) for v in value]
        return value

    for name, value in (("summary.json", summary), ("ledger.json", ledger)):
        (root / name).write_text(
            json.dumps(safe(value), indent=2, allow_nan=False) + "\n"
        )
    return safe(summary)


if __name__ == "__main__":
    result = analyze(sys.argv[1])
    print(
        json.dumps(
            {
                "scheduled": result["scheduled"],
                "receipts": result["receipts"],
                "lanes": {
                    k: {
                        "baseline": v["arms"]["baseline"]["accepted"],
                        "candidate": v["arms"]["candidate"]["accepted"],
                        "cost_ratio": v["token_cost_ratio"],
                        "interval": v["token_cost_ratio_bootstrap_95"],
                    }
                    for k, v in result["lanes"].items()
                },
                "portable_winner": result["portable_winner"],
            },
            indent=2,
        )
    )
