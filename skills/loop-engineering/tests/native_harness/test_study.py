import copy
from pathlib import Path
import sys
import tempfile
import unittest

STUDY = Path(__file__).resolve().parents[2] / "scripts/native_harness/study"
sys.path.insert(0, str(STUDY))
from corpus import TASKS  # noqa: E402
from evaluate import calibrate  # noqa: E402
from run import acceptance, schedule  # noqa: E402
from analyze import arm_summary, bootstrap, mcnemar, wilson  # noqa: E402


class StudyControls(unittest.TestCase):
    def test_every_reference_passes_and_every_original_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = calibrate(Path(temporary) / "calibration.json")
        self.assertEqual(len(rows), 24)
        self.assertEqual(len({r["task"] for r in rows}), 24)
        for row in rows:
            with self.subTest(task=row["task"]):
                self.assertFalse(row["broken"]["success"])
                self.assertTrue(row["reference"]["success"], row["reference"])
                self.assertEqual(row["reference"]["total"], 6)

    def test_schedule_is_complete_paired_balanced_and_reproducible(self):
        rows = schedule()
        self.assertEqual(rows, schedule())
        self.assertEqual(len(rows), 144)
        self.assertEqual(len({r["id"] for r in rows}), 144)
        for harness in {r["harness"] for r in rows}:
            lane = [r for r in rows if r["harness"] == harness]
            self.assertEqual(len(lane), 48)
            self.assertEqual(
                sum(r["position"] == 0 and r["arm"] == "candidate" for r in lane), 12
            )
            for left, right in zip(lane[::2], lane[1::2]):
                self.assertEqual(left["task"], right["task"])
                self.assertEqual({left["arm"], right["arm"]}, {"baseline", "candidate"})

    def test_acceptance_never_substitutes_work_for_protocol_evidence(self):
        task = TASKS[0]
        turn = {
            "status": "completed",
            "usage_complete": True,
            "native_usage": {"model_valid": True},
            "timing": {"timing_valid": True, "within_ceiling": True},
        }
        final = {
            "success": True,
            "checks": [
                {"name": task.name + ":case-" + str(i), "pass": True}
                for i in range(1, 7)
            ],
        }
        self.assertTrue(
            acceptance(task, turn, final, {"valid": True}, [{"success": True}], 12)
        )
        for fault in (
            "empty",
            "duplicate",
            "failed",
            "usage",
            "model",
            "scope",
            "verifier",
            "timing",
            "watchdog",
        ):
            with self.subTest(fault=fault):
                t, f = copy.deepcopy(turn), copy.deepcopy(final)
                receipt, calls, seconds = {"valid": True}, [{"success": True}], 12
                if fault == "empty":
                    f["checks"] = []
                elif fault == "duplicate":
                    f["checks"][-1] = f["checks"][0]
                elif fault == "failed":
                    f["checks"][0]["pass"] = False
                elif fault == "usage":
                    t["usage_complete"] = False
                elif fault == "model":
                    t["native_usage"]["model_valid"] = False
                elif fault == "scope":
                    receipt["valid"] = False
                elif fault == "verifier":
                    calls = []
                elif fault == "timing":
                    t["timing"]["within_ceiling"] = False
                else:
                    seconds = 241
                self.assertFalse(acceptance(task, t, f, receipt, calls, seconds))

    def test_incomplete_usage_and_failed_trials_are_not_free(self):
        good = {
            "accepted": True,
            "turn": {"usage_complete": True, "native_usage": {"reported_tokens": 100}},
            "seconds_including_setup": 2,
        }
        failed = {
            "accepted": False,
            "turn": {"usage_complete": True, "native_usage": {"reported_tokens": 80}},
            "seconds_including_setup": 3,
        }
        summary = arm_summary([good, failed])
        self.assertEqual(summary["tokens_per_accepted"], 180)
        self.assertEqual(summary["seconds_per_accepted"], 5)
        failed["turn"]["usage_complete"] = False
        self.assertIsNone(arm_summary([good, failed])["tokens_per_accepted"])

    def test_intervals_do_not_turn_small_perfect_samples_into_certainty(self):
        self.assertLess(wilson(24, 24)[0], 0.9)
        self.assertEqual(mcnemar(0, 0), 1)
        self.assertAlmostEqual(mcnemar(6, 0), 0.03125)
        pairs = []
        for language in ("python", "shell"):
            pairs.append(
                {
                    arm: {
                        "language": language,
                        "accepted": True,
                        "turn": {"native_usage": {"reported_tokens": tokens}},
                    }
                    for arm, tokens in (("baseline", 100), ("candidate", 80))
                }
            )
        self.assertEqual(bootstrap(pairs, draws=100), [0.8, 0.8])


if __name__ == "__main__":
    unittest.main()
