#!/usr/bin/env python3
"""Tests for the pr-cost doctor's classification.

The doctor's value is entirely in telling four situations apart:
a lane that works, a lane that is broken, a lane that returned a confident
zero, and a lane this machine simply cannot exercise. Any two of those
collapsing into one status makes the tool worse than not running it, so
every test here is about a boundary rather than a happy path.

Readers are faked as small scripts on disk. Faking the subprocess boundary
rather than the function keeps the exit-code and stdout contract under test,
which is where a real reader would break.
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SKILL_SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"

SPEC = importlib.util.spec_from_file_location(
    "pr_cost_doctor",
    pathlib.Path(__file__).resolve().parents[1] / "scripts" / "pr_cost_doctor.py",
)
doctor = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(doctor)

GOOD = {
    "session_id": "s",
    "model": "m",
    "tokens_in": 173,
    "tokens_out": 31,
    "window_start": "2026-01-01T00:00:00Z",
    "window_end": "2026-01-01T00:01:00Z",
    "path": "/x",
    "usd_estimated": 1.5,
}


def fake_reader(tmp: pathlib.Path, name: str, body: str) -> pathlib.Path:
    """Write a reader that ignores its arguments and does what body says."""
    script = tmp / f"{name}.py"
    script.write_text(
        "import sys, json\n"
        "sys.argv = sys.argv[:1]\n" + body,
        encoding="utf-8",
    )
    return script


def emit(payload: dict) -> str:
    return f"print(json.dumps({payload!r}))\n"


class RunReaderTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self._tmp.name)
        self.target = self.tmp / "t.jsonl"
        self.target.write_text("{}\n", encoding="utf-8")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def check(self, body: str) -> dict:
        return doctor.run_reader(
            fake_reader(self.tmp, "r", body), "--jsonl", self.target
        )

    def test_contract_satisfied_is_ok(self) -> None:
        self.assertEqual(self.check(emit(GOOD))["status"], "ok")

    def test_zero_tokens_is_no_signal_not_ok(self) -> None:
        """The defect that motivated this file: $0.0000 reported as success."""
        zeroed = {**GOOD, "tokens_in": 0, "tokens_out": 0, "usd_estimated": 0.0}
        result = self.check(emit(zeroed))
        self.assertEqual(result["status"], "no-signal")
        self.assertIn("zero", result["detail"])

    def test_zero_usd_on_a_rate_table_lane_is_no_signal(self) -> None:
        """Counting tokens while pricing them at zero is a lost rate table.

        The token guard cannot see this: tokens are correct, so it passes,
        and the number the skill exists to produce is silently zero. Found by
        planting `return 0.0` in claude_session_usage.estimate_usd — the
        lane graded `ok` with rc=0.
        """
        result = self.check(emit({**GOOD, "usd_estimated": 0.0}))
        self.assertEqual(result["status"], "no-signal")
        self.assertIn("rate table", result["detail"])

    def test_zero_usd_is_allowed_on_a_provider_reported_lane(self) -> None:
        """A billed cost of zero is a fact, not a missing rate table.

        opencode passes through what the provider charged, and a free
        request legitimately costs nothing. Applying the rate-table guard
        there would fail a correct reading.
        """
        payload = {**GOOD, "usd_estimated": 0.0, "usd_basis": "provider-reported"}
        self.assertEqual(self.check(emit(payload))["status"], "ok")

    def test_output_only_still_counts_as_signal(self) -> None:
        """Only both sides at zero is no-signal; one side may legitimately be 0."""
        self.assertEqual(
            self.check(emit({**GOOD, "tokens_in": 0}))["status"], "ok"
        )

    def test_missing_shared_key_is_broken(self) -> None:
        for key in doctor.SHARED_KEYS:
            payload = {k: v for k, v in GOOD.items() if k != key}
            result = self.check(emit(payload))
            self.assertEqual(result["status"], "broken", key)
            self.assertIn(key, result["detail"])

    def test_nonzero_exit_is_broken(self) -> None:
        result = self.check("sys.stderr.write('boom\\n'); sys.exit(3)\n")
        self.assertEqual(result["status"], "broken")
        self.assertIn("exited 3", result["detail"])

    def test_non_json_stdout_is_broken(self) -> None:
        self.assertEqual(self.check("print('not json')\n")["status"], "broken")

    def test_json_scalar_stdout_is_broken(self) -> None:
        """A bare number parses as JSON but is not a report."""
        self.assertEqual(self.check("print('42')\n")["status"], "broken")

    def test_negative_or_non_integer_tokens_is_broken(self) -> None:
        for bad in (-1, "173", 173.5, True):
            result = self.check(emit({**GOOD, "tokens_in": bad}))
            self.assertEqual(result["status"], "broken", repr(bad))

    def test_reversed_window_is_broken(self) -> None:
        reversed_window = {
            **GOOD,
            "window_start": "2026-01-01T00:05:00Z",
            "window_end": "2026-01-01T00:01:00Z",
        }
        self.assertEqual(self.check(emit(reversed_window))["status"], "broken")


class LaneClassificationTest(unittest.TestCase):
    """A lane's status must never overstate what actually ran."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def diagnose_with(self, lanes: list[dict]) -> dict:
        original = doctor.lanes
        doctor.lanes = lambda: lanes
        try:
            return doctor.diagnose(self_check=True, live=True)
        finally:
            doctor.lanes = original

    def claude_lane(self, body: str, live_root: pathlib.Path) -> dict:
        return {
            "harness": "claude",
            "reader": fake_reader(self.tmp, "reader", body),
            "flag": "--jsonl",
            "live_root": live_root,
            "live_glob": "*.jsonl",
        }

    def test_absent_live_root_is_unavailable_not_ok(self) -> None:
        """A harness that is not installed is not a harness that works."""
        lane = self.claude_lane(emit(GOOD), self.tmp / "nope")
        report = self.diagnose_with([lane])
        entry = report["lanes"][0]
        self.assertEqual(entry["live"]["status"], "unavailable")
        self.assertEqual(entry["self_check"]["status"], "ok")
        self.assertEqual(report["failed"], [])

    def test_empty_live_root_is_unavailable(self) -> None:
        empty = self.tmp / "empty"
        empty.mkdir()
        report = self.diagnose_with([self.claude_lane(emit(GOOD), empty)])
        self.assertEqual(report["lanes"][0]["live"]["status"], "unavailable")

    def test_broken_lane_is_reported_as_failed(self) -> None:
        lane = self.claude_lane("sys.exit(1)\n", self.tmp / "nope")
        report = self.diagnose_with([lane])
        self.assertEqual(report["failed"], ["claude"])
        self.assertEqual(report["lanes"][0]["status"], "broken")

    def test_no_signal_lane_is_reported_as_failed(self) -> None:
        zeroed = {**GOOD, "tokens_in": 0, "tokens_out": 0}
        lane = self.claude_lane(emit(zeroed), self.tmp / "nope")
        report = self.diagnose_with([lane])
        self.assertEqual(report["failed"], ["claude"])

    def test_missing_declared_reader_is_broken(self) -> None:
        lane = self.claude_lane(emit(GOOD), self.tmp / "nope")
        lane["reader"] = self.tmp / "was-deleted.py"
        report = self.diagnose_with([lane])
        self.assertEqual(report["lanes"][0]["status"], "broken")
        self.assertIn("missing", report["lanes"][0]["detail"])

    def test_adapter_only_and_unsupported_are_distinct(self) -> None:
        adapter = self.tmp / "hooks.json"
        adapter.write_text("{}", encoding="utf-8")
        report = self.diagnose_with(
            [
                {"harness": "cursor", "reader": None, "adapter": adapter},
                # Deliberately not a real harness name: `unsupported` is
                # unreachable from the declared lane set today, so naming a
                # live lane here would read as a claim about that lane.
                {"harness": "hypothetical", "reader": None, "adapter": None},
            ]
        )
        statuses = {lane["harness"]: lane["status"] for lane in report["lanes"]}
        self.assertEqual(statuses["cursor"], "adapter-only")
        self.assertEqual(statuses["hypothetical"], "unsupported")
        self.assertEqual(report["failed"], [])


class RealLaneTest(unittest.TestCase):
    """The declared lanes must satisfy the contract on synthetic input.

    This is the portable half: it needs no harness installed, so it proves
    the readers on any machine and in CI.
    """

    def test_self_check_passes_for_every_declared_reader(self) -> None:
        report = doctor.diagnose(self_check=True, live=False)
        for lane in report["lanes"]:
            if "self_check" not in lane:
                continue
            self.assertEqual(
                lane["self_check"]["status"],
                "ok",
                f"{lane['harness']}: {lane['self_check'].get('detail')}",
            )
        self.assertEqual(report["failed"], [])

    def test_every_synthetic_transcript_has_a_declared_lane(self) -> None:
        """A fixture with no lane, or a lane with no fixture, is dead weight."""
        readers = {
            lane["harness"] for lane in doctor.lanes() if lane["reader"] is not None
        }
        self.assertEqual(set(doctor.SYNTHETIC), readers)

    def test_the_docstring_names_every_basis_the_doctor_can_emit(self) -> None:
        """Catch the prose going stale when a lane prices differently.

        This drifted once already: adding the opencode lane introduced a
        second basis while the docstring still said "Both readers carry fixed
        default rates ... reports usd_basis as default-rates". The status-block
        pin passed throughout, because it pins names and exit codes, not the
        paragraph above them. Pinning the basis *values* closes the specific
        gap without pretending to check English.
        """
        report = doctor.diagnose(self_check=True, live=False)
        docstring = doctor.__doc__ or ""
        for basis in sorted(set(report["usd_basis"].values())):
            self.assertIn(
                basis,
                docstring,
                f"the doctor can report usd_basis {basis!r}, but its own "
                f"docstring never mentions it",
            )

    def test_no_lane_claims_its_usd_is_measured(self) -> None:
        """Each lane declares its own basis; none may claim a measured figure.

        `provider-reported` is not the same claim as `measured`: it is the
        number the provider billed, which is still not a rate this repo
        verified. The two rate-table lanes must say so explicitly rather
        than inheriting a basis from a lane that prices differently.
        """
        report = doctor.diagnose(self_check=True, live=False)
        basis = report["usd_basis"]
        self.assertIn("estimated, not", report["usd_basis_note"])
        self.assertNotIn("measured", basis.values())
        self.assertEqual(basis["claude"], "default-rates")
        self.assertEqual(basis["codex"], "default-rates")
        self.assertEqual(basis["opencode"], "provider-reported")

    def test_every_reader_lane_is_a_harness_the_collector_accepts(self) -> None:
        """A lane you can diagnose but cannot record is only half a lane.

        This gap shipped: the opencode reader produced a full eight-key
        payload with the best basis of any lane, the doctor reported it `ok`,
        and `pr_cost_collect.py` then rejected `--harness opencode` with exit
        2. Nothing connected the two sides, so both were individually green.
        """
        collector = SKILL_SCRIPTS / "pr_cost_collect.py"
        for lane in doctor.lanes():
            if lane["reader"] is None:
                continue
            proc = subprocess.run(
                [
                    sys.executable, str(collector), "emit",
                    "--harness", lane["harness"], "--confidence", "unavailable",
                ],
                capture_output=True, text=True,
            )
            self.assertEqual(
                proc.returncode, 0,
                f"doctor declares a {lane['harness']} lane, but the collector "
                f"rejects --harness {lane['harness']}: {proc.stderr.strip()}",
            )

    def test_every_reader_lane_reports_a_basis(self) -> None:
        """A lane with no declared basis would silently read as a rate guess."""
        report = doctor.diagnose(self_check=True, live=False)
        readers = {
            lane["harness"] for lane in doctor.lanes() if lane["reader"] is not None
        }
        self.assertEqual(set(report["usd_basis"]), readers)


if __name__ == "__main__":
    unittest.main()
