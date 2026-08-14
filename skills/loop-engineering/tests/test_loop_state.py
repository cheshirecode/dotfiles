#!/usr/bin/env python3
"""Fixtures for the loop-engineering state CLI."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "loop_state.py"
SKILL = SCRIPT.parents[1] / "SKILL.md"
SPEC = importlib.util.spec_from_file_location("loop_state_under_test", SCRIPT)
assert SPEC and SPEC.loader
LOOP_STATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LOOP_STATE)


class LoopStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.state = pathlib.Path(self.temporary_directory.name) / "loop.json"
        self.successor = pathlib.Path(self.temporary_directory.name) / "successor.json"

    def run_cli(
        self,
        *arguments: str,
        expected_returncode: int = 0,
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result

    def initialize(self, limit: int = 2) -> dict[str, object]:
        result = self.run_cli(
            "init",
            "--state",
            str(self.state),
            "--goal",
            "targeted test passes",
            "--evidence",
            "failure reproduced",
            "--budget-unit",
            "hypotheses",
            "--budget-limit",
            str(limit),
            "--next-action",
            "test timing hypothesis",
            "--allowed-effect",
            "edit worktree",
        )
        return json.loads(result.stdout)

    def fingerprint(self) -> str:
        return self.run_cli(
            "fingerprint",
            "--state",
            str(self.state),
        ).stdout.strip()

    def test_init_and_validate(self) -> None:
        state = self.initialize()
        self.assertEqual(state["terminal_status"], "running")
        self.assertEqual(state["budget"]["used"], 0)
        self.run_cli("validate", "--state", str(self.state))

    def test_skill_routes_transient_artifacts_to_system_temp(self) -> None:
        skill_text = SKILL.read_text()
        initialization = skill_text.split(
            "## Initialize through the script", 1
        )[1].split("### Optional model routing", 1)[0]
        self.assertIn("Keep transient loop state", initialization)
        self.assertIn("`/tmp`", initialization)
        self.assertIn("`$TMPDIR`", initialization)
        self.assertIn("evidence-gate JSON", initialization)
        self.assertIn("do\nnot leave ad hoc run artifacts behind", initialization)

    def test_orchestrator_terminal_example_supplies_required_verification(self) -> None:
        skill_text = SKILL.read_text()
        terminal_example = skill_text.split(
            "When budget is consumed or the project queue is empty", 1
        )[1].split("If the queue still has tasks", 1)[0]
        self.assertIn("project verify <slug>", terminal_example)
        self.assertIn("project next reported all tasks archived", terminal_example)
        self.assertIn("project queue empty: typed command output", terminal_example)
        self.assertIn("if ! $WORKLOG_BIN/project.sh verify <program-slug>", terminal_example)

    def test_orchestrator_does_not_treat_any_next_exit_one_as_success(self) -> None:
        skill_text = SKILL.read_text()
        terminal = skill_text.split("When budget is consumed or the project queue is empty", 1)[1]
        self.assertIn("Exit 1 alone is\nnot proof of an empty queue", terminal)
        self.assertIn("blocked or missing", terminal)

    def test_orchestrator_preserves_explicit_budget_and_minimum(self) -> None:
        skill_text = SKILL.read_text()
        budgeting = skill_text.split("### 1. Decompose & budget", 1)[1].split(
            "### Mid-run council escalation", 1
        )[0]
        self.assertIn("If the user gives a budget, use that exact limit", budgeting)
        self.assertIn("never\nsilently replace it with 999", budgeting)
        self.assertIn("do not finish before that minimum", budgeting)

    def test_root_route_matrix_selects_minimum_context(self) -> None:
        skill_text = SKILL.read_text()
        route = skill_text.split("## Route", 1)[1].split(
            "## Initialize through the script", 1
        )[0]
        for signal in (
            "one action + one check",
            "repeated, resumable, or delegated work",
            "recurrence or installation drift",
            "exact transition, effect, worklog, or handoff question",
        ):
            self.assertIn(signal, route)
        self.assertIn("load only the needed rules", route)

    def test_protocol_requires_discriminating_cycle_record(self) -> None:
        protocol = (SKILL.parent / "references" / "protocol.md").read_text()
        for field in ("hypothesis", "falsifier", "replay"):
            self.assertIn(f"`{field}`", protocol)
        self.assertIn("neither a confirmation nor a falsifier", protocol)

    def test_protocol_preserves_verifier_exit_status_when_summarizing(self) -> None:
        protocol = (SKILL.parent / "references" / "protocol.md").read_text()
        self.assertIn("set -o pipefail", protocol)
        self.assertIn("capture the producer status", protocol)
        self.assertIn("not evidence that the producer passed", protocol)

    def test_protocol_requires_effect_preflight_before_mutation(self) -> None:
        protocol = (SKILL.parent / "references" / "protocol.md").read_text()
        preflight = protocol.split("Before every mutation", 1)[1]
        for question in (
            "What exact path, provider, or person",
            "Is that target listed in `allowed_effects`",
            "Does the action cross `approval_boundary`",
            "What read-only check will prove",
        ):
            self.assertIn(question, preflight)
        self.assertIn("needs_human", preflight)
        self.assertIn("missing authority", preflight)

    def test_root_cycle_requires_effect_preflight_before_writing(self) -> None:
        skill_text = SKILL.read_text()
        cycle = skill_text.split("## Run one bounded cycle", 1)[1].split(
            "## Preserve durable context", 1
        )[0]
        self.assertIn("effect preflight for every mutation", cycle)
        self.assertIn("stop before writing", cycle)
        self.assertIn("Serialize writes", cycle)

    def test_evidence_contract_is_typed_and_compact(self) -> None:
        skill_text = SKILL.read_text()
        protocol = (SKILL.parent / "references" / "protocol.md").read_text()
        for kind in ("command", "artifact", "git", "github", "url"):
            self.assertIn(f"`{kind}`", skill_text)
            self.assertIn(f"`{kind}`", protocol)
        self.assertIn("one typed line", skill_text)
        self.assertIn("index, not a log", skill_text)

    def test_protocol_bounds_cold_delegation_context_and_return(self) -> None:
        protocol = (SKILL.parent / "references" / "protocol.md").read_text()
        for heading in (
            "`objective`",
            "`known evidence`",
            "`constraints`",
            "`budget`",
            "`requested return`",
        ):
            self.assertIn(heading, protocol)
        self.assertIn("Do not pass the parent transcript", protocol)
        self.assertIn("`evidence`, `uncertainty`, and `next action`", protocol)

    def test_model_routing_is_optional_and_policy_gated(self) -> None:
        skill_text = SKILL.read_text()
        routing = skill_text.split("### Optional model routing", 1)[1].split(
            "## Run one bounded cycle", 1
        )[0]
        self.assertIn("$which-model", routing)
        self.assertIn("current harness exposes it", routing)
        self.assertIn("data-policy gate", routing)
        self.assertIn("model lane, not an unverified exact", routing)
        self.assertIn("If there is no dispatch", routing)
        self.assertIn("required supporting tool is unavailable", routing)
        self.assertIn("model-routing: skipped", routing)
        self.assertIn("do not spend a cycle", routing)

    def test_protocol_checkpoint_has_replayable_handoff_fields(self) -> None:
        protocol = (SKILL.parent / "references" / "protocol.md").read_text()
        checkpoint = protocol.split("At compaction", 1)[1].split(
            "## Delegation", 1
        )[0]
        for field in (
            "`state path`",
            "`state fingerprint`",
            "`terminal\nstatus`",
            "`next action`",
            "`typed evidence reference`",
            "`approval boundary`",
        ):
            self.assertIn(field, checkpoint)
        self.assertIn("replay the recorded next action", checkpoint)

    def test_skill_makes_worklog_resume_and_local_fallback_executable(self) -> None:
        skill_text = SKILL.read_text()
        durable = skill_text.split("## Preserve durable context", 1)[1].split(
            "## Orchestrator mode", 1
        )[0]
        self.assertIn("context.sh <slug> --for=resume", durable)
        self.assertIn("target clone's direnv", durable)
        self.assertIn("context <slug> --for=compact", durable)
        self.assertIn("worklog-checkpoint: unavailable", durable)

    def test_orchestrator_gates_optional_decomposition_and_delegate_output(self) -> None:
        skill_text = SKILL.read_text()
        orchestrator = skill_text.split("## Orchestrator mode", 1)[1]
        self.assertIn("regular loop", orchestrator)
        self.assertIn("one or two tasks", orchestrator)
        self.assertIn("only when the task graph is not already explicit", orchestrator)
        self.assertIn("archived <child-slug> <worklog-commit>", orchestrator)
        self.assertIn("discards any", orchestrator)
        self.assertIn("prose", orchestrator)

    def test_orchestrator_checks_delegate_capability_before_dispatch(self) -> None:
        skill_text = SKILL.read_text()
        orchestrator = skill_text.split("## Orchestrator mode", 1)[1]
        self.assertIn("current harness exposes the", orchestrator)
        self.assertIn("do not fabricate a delegate result", orchestrator)
        self.assertIn("finish `needs_human`", orchestrator)
        self.assertIn("model-routing: skipped — no delegate surface", orchestrator)

    def test_orchestrator_can_escalate_council_mid_run_without_archiving(self) -> None:
        skill_text = SKILL.read_text()
        orchestrator = skill_text.split("## Orchestrator mode", 1)[1]
        self.assertIn("without a new user turn", orchestrator)
        self.assertIn("material uncertainty trigger", orchestrator)
        self.assertIn("replay check", orchestrator)
        self.assertIn("never\narchive or finish `complete`", orchestrator)

    def test_council_escalation_pack_is_minimal_and_replay_bound(self) -> None:
        skill_text = SKILL.read_text()
        escalation = skill_text.split("### Mid-run council escalation", 1)[1].split(
            "### 2. Create project", 1
        )[0]
        for field in (
            "`trigger`",
            "`affected mutation`",
            "`one decision\nquestion`",
            "`evidence`",
            "`replay check`",
        ):
            self.assertIn(field, escalation)
        self.assertIn("Accept only `verified` or", escalation)
        self.assertIn("before the task resumes", escalation)

    def test_init_refuses_to_overwrite_existing_state(self) -> None:
        self.initialize()
        result = self.run_cli(
            "init",
            "--state",
            str(self.state),
            "--goal",
            "different goal",
            "--evidence",
            "none",
            "--budget-unit",
            "turns",
            "--budget-limit",
            "1",
            "--next-action",
            "stop",
            expected_returncode=3,
        )
        self.assertIn("refusing to overwrite", result.stderr)

    def test_init_force_overwrites_existing_state(self) -> None:
        self.initialize()
        before = self.state.read_text()
        self.run_cli(
            "init",
            "--state",
            str(self.state),
            "--goal",
            "replacement goal",
            "--evidence",
            "forced overwrite",
            "--budget-unit",
            "cycles",
            "--budget-limit",
            "5",
            "--next-action",
            "replaced",
            "--force",
        )
        after = json.loads(self.state.read_text())
        self.assertEqual(after["goal"], "replacement goal")
        self.assertNotEqual(self.state.read_text(), before)

    def test_advance_exhausts_budget_without_claiming_complete(self) -> None:
        self.initialize(limit=1)
        result = self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "timing hypothesis falsified",
            "--next-action",
            "handoff with evidence",
        )
        state = json.loads(result.stdout)
        self.assertEqual(state["terminal_status"], "budget_exhausted")
        self.assertNotEqual(state["terminal_status"], "complete")

    def test_advance_waits_for_state_lock(self) -> None:
        self.initialize()
        command = [
            sys.executable,
            str(SCRIPT),
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "serialized transition",
            "--next-action",
            "verify lock",
        ]
        with LOOP_STATE.state_lock(self.state):
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            with self.assertRaises(subprocess.TimeoutExpired):
                process.communicate(timeout=0.2)

        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, msg=f"stdout:\n{stdout}\nstderr:\n{stderr}")
        state = json.loads(self.state.read_text())
        self.assertIn("serialized transition", state["progress_evidence"])

    def test_concurrent_advances_preserve_every_transition(self) -> None:
        self.initialize(limit=8)
        processes = [
            subprocess.Popen(
                [
                    sys.executable,
                    str(SCRIPT),
                    "advance",
                    "--state",
                    str(self.state),
                    "--evidence",
                    f"writer-{index}",
                    "--next-action",
                    "continue",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for index in range(8)
        ]
        results = [process.communicate(timeout=10) for process in processes]
        for process, (stdout, stderr) in zip(processes, results):
            self.assertEqual(
                process.returncode,
                0,
                msg=f"stdout:\n{stdout}\nstderr:\n{stderr}",
            )

        state = json.loads(self.state.read_text())
        self.assertEqual(state["budget"]["used"], 8)
        for index in range(8):
            self.assertIn(f"writer-{index}", state["progress_evidence"])

    def test_resume_creates_bound_successor_without_reopening_blocker(self) -> None:
        self.initialize()
        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "needs_human",
            "--evidence",
            "deployment credential requires intervention",
            "--next-action",
            "ask operator to refresh the credential",
            "--consume",
            "1",
        )
        predecessor_text = self.state.read_text()
        result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "operator refreshed the credential",
            "--next-action",
            "replay the deployment verification",
            "--allowed-effect",
            "run deployment verification",
            "--approval-boundary",
            "use only the refreshed credential",
        )
        successor = json.loads(result.stdout)

        self.assertEqual(self.state.read_text(), predecessor_text)
        self.assertEqual(successor["terminal_status"], "running")
        self.assertEqual(successor["goal"], "targeted test passes")
        self.assertEqual(
            successor["budget"],
            {"unit": "hypotheses", "limit": 2, "used": 1},
        )
        self.assertEqual(
            successor["predecessor"]["terminal_status"],
            "needs_human",
        )
        self.assertEqual(
            json.loads(predecessor_text)["next_action"],
            "ask operator to refresh the credential",
        )
        self.assertEqual(
            successor["predecessor"]["sha256"],
            hashlib.sha256(predecessor_text.encode()).hexdigest(),
        )
        self.assertEqual(successor["history"][-1]["event"], "resumed:needs_human")
        self.assertIn("edit worktree", successor["allowed_effects"])
        self.assertIn("run deployment verification", successor["allowed_effects"])

    def test_resume_rejects_running_and_complete_predecessors(self) -> None:
        self.initialize()
        running_result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "no intervention occurred",
            "--next-action",
            "continue current run",
            expected_returncode=3,
        )
        self.assertIn("cannot resume state with status: running", running_result.stderr)
        self.assertFalse(self.successor.exists())

        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "targeted test passed",
            "--verification",
            "test log",
        )
        complete_result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "request to reopen completed work",
            "--next-action",
            "do not reopen",
            expected_returncode=3,
        )
        self.assertIn(
            "cannot resume state with status: complete", complete_result.stderr
        )
        self.assertFalse(self.successor.exists())

    def test_exhausted_resume_requires_explicit_budget_extension(self) -> None:
        self.initialize(limit=1)
        self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "initial hypothesis falsified",
            "--next-action",
            "request authority for another hypothesis",
        )
        rejected = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "no additional budget authorized",
            "--next-action",
            "remain exhausted",
            expected_returncode=3,
        )
        self.assertIn("requires --extend-budget", rejected.stderr)
        self.assertFalse(self.successor.exists())

        resumed = json.loads(
            self.run_cli(
                "resume",
                "--state",
                str(self.state),
                "--new-state",
                str(self.successor),
                "--evidence",
                "operator authorized two more hypotheses",
                "--extend-budget",
                "2",
                "--next-action",
                "test the next hypothesis",
            ).stdout
        )
        self.assertEqual(
            resumed["budget"],
            {"unit": "hypotheses", "limit": 3, "used": 1},
        )

    def test_complete_requires_verification_and_failed_transition_is_atomic(
        self,
    ) -> None:
        self.initialize()
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "agent says fixed",
            expected_returncode=3,
        )
        self.assertIn("requires --verification", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_complete_records_external_verification(self) -> None:
        self.initialize()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "three consecutive passes",
            "--verification",
            "pytest log artifact: /tmp/targeted-test.log",
            "--consume",
            "1",
        )
        state = json.loads(result.stdout)
        self.assertEqual(state["terminal_status"], "complete")
        self.assertIn("pytest log", state["verification"])
        self.assertEqual(state["budget"]["used"], 1)
        self.assertEqual(state["next_action"], "")
        self.assertEqual(state["history"][-1]["next_action"], "")

    def test_non_resumable_finish_rejects_explicit_next_action_atomically(
        self,
    ) -> None:
        self.initialize()
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "targeted test passed",
            "--verification",
            "pytest log",
            "--next-action",
            "stale follow-up",
            expected_returncode=3,
        )
        self.assertIn("complete does not accept --next-action", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_resumable_finish_requires_actionable_next_step(self) -> None:
        self.initialize()
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "blocked",
            "--evidence",
            "credential unavailable",
            expected_returncode=3,
        )
        self.assertIn("blocked requires --next-action", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_cancelled_finish_clears_running_next_action(self) -> None:
        self.initialize()
        state = json.loads(
            self.run_cli(
                "finish",
                "--state",
                str(self.state),
                "--status",
                "cancelled",
                "--evidence",
                "operator cancelled the run",
            ).stdout
        )
        self.assertEqual(state["terminal_status"], "cancelled")
        self.assertEqual(state["next_action"], "")

    def test_annotate_rejects_next_action_for_non_resumable_terminal(self) -> None:
        self.initialize()
        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "cancelled",
            "--evidence",
            "operator cancelled the run",
        )
        expected_sha256 = self.fingerprint()
        before = self.state.read_text()
        result = self.run_cli(
            "annotate",
            "--state",
            str(self.state),
            "--expect-sha256",
            expected_sha256,
            "--evidence",
            "correction: cancellation was explicit",
            "--next-action",
            "reopen the cancelled run",
            expected_returncode=3,
        )
        self.assertIn("cancelled does not accept --next-action", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_runtime_rejection_and_cli_misuse_are_distinct_and_atomic(self) -> None:
        self.initialize(limit=1)
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "blocked",
            "--evidence",
            "two retries attempted",
            "--next-action",
            "request another retry",
            "--consume",
            "2",
            expected_returncode=3,
        )
        self.assertIn("only 1 remain", result.stderr)
        self.assertEqual(self.state.read_text(), before)

        misuse = self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "invalid zero-unit transition",
            "--next-action",
            "fix invocation",
            "--consume",
            "0",
            expected_returncode=2,
        )
        self.assertIn("usage:", misuse.stderr)
        self.assertNotIn("loop-state:", misuse.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_annotate_corrects_terminal_evidence_without_reopening(self) -> None:
        self.initialize(limit=1)
        exhausted = json.loads(
            self.run_cli(
                "advance",
                "--state",
                str(self.state),
                "--evidence",
                "no Git metadata",
                "--next-action",
                "obtain target repository",
            ).stdout
        )
        expected_sha256 = self.fingerprint()
        corrected = json.loads(
            self.run_cli(
                "annotate",
                "--state",
                str(self.state),
                "--expect-sha256",
                expected_sha256,
                "--evidence",
                "correction: cwd has .git but is not the target repository",
            ).stdout
        )
        self.assertEqual(corrected["terminal_status"], "budget_exhausted")
        self.assertEqual(corrected["budget"], exhausted["budget"])
        self.assertEqual(corrected["history"][-1]["event"], "annotated")

    def test_fingerprint_matches_exact_state_bytes(self) -> None:
        self.initialize()

        self.assertEqual(
            self.fingerprint(),
            hashlib.sha256(self.state.read_bytes()).hexdigest(),
        )

    def test_annotate_rejects_stale_fingerprint_atomically(self) -> None:
        self.initialize()
        stale_sha256 = self.fingerprint()
        self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "another session advanced the run",
            "--next-action",
            "continue from the newer snapshot",
        )
        before = self.state.read_text()

        result = self.run_cli(
            "annotate",
            "--state",
            str(self.state),
            "--expect-sha256",
            stale_sha256,
            "--evidence",
            "stale session correction",
            expected_returncode=3,
        )

        self.assertIn("state fingerprint changed", result.stderr)
        self.assertEqual(self.state.read_text(), before)


if __name__ == "__main__":
    unittest.main()
