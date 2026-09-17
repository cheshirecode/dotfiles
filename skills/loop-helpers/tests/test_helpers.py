#!/usr/bin/env python3
"""Contract tests for the opt-in loop helpers and installer boundary."""

from __future__ import annotations

import json
import importlib.util
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest


SKILL_DIR = pathlib.Path(__file__).parents[1]
REPO_ROOT = SKILL_DIR.parents[1]
CONTEXT_PACK = SKILL_DIR / "scripts/context_pack.py"
TRANSPORT_GATE = SKILL_DIR / "scripts/transport_gate.py"
INSTALL_SKILLS = REPO_ROOT / "bin/install-skills.sh"


class LoopHelpersTest(unittest.TestCase):
    def run_script(
        self,
        script: pathlib.Path,
        *arguments: str,
        env: dict[str, str] | None = None,
        expected_returncode: int = 0,
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(script), *arguments],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result

    def test_context_pack_is_compact_and_transcript_free(self) -> None:
        result = self.run_script(
            CONTEXT_PACK,
            "--objective",
            "reduce context",
            "--known-evidence",
            "command: tests passed",
            "--constraints",
            "isolated worktree",
            "--budget",
            "2 cycles",
            "--requested-return",
            "evidence and next action",
            "--recovery-handle",
            "ccr_123",
        )
        pack = json.loads(result.stdout)
        self.assertEqual(pack["schema_version"], 1)
        self.assertEqual(pack["known_evidence"], ["command: tests passed"])
        self.assertEqual(pack["recovery_handles"], ["ccr_123"])
        self.assertNotIn("parent transcript", result.stdout)
        self.assertNotIn("history", pack)

    def test_context_pack_requires_explicit_handoff_fields(self) -> None:
        self.run_script(
            CONTEXT_PACK,
            "--objective",
            "goal",
            expected_returncode=2,
        )

    def test_transport_gate_fails_open_when_capability_is_missing(self) -> None:
        environment = os.environ.copy()
        environment["PATH"] = str(pathlib.Path(self.tmpdir.name) / "empty-bin")
        result = self.run_script(
            TRANSPORT_GATE,
            "--mode",
            "pixel",
            "--authorized",
            env=environment,
        )
        self.assertIn("decision=skip mode=pixel reason=caveman-unavailable original-bytes", result.stdout)

    def test_transport_gate_requires_all_pixel_facts(self) -> None:
        fake = pathlib.Path(self.tmpdir.name) / "caveman"
        fake.write_text("#!/bin/sh\n")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        result = self.run_script(
            TRANSPORT_GATE,
            "--mode",
            "pixel",
            "--caveman-command",
            str(fake),
            "--authorized",
            "--measured-win",
            "--recoverable",
            "--dense",
            "--legible",
            "--model",
            "claude-fable-5",
        )
        self.assertIn("decision=use mode=pixel reason=all-gates-passed", result.stdout)

        sparse = self.run_script(
            TRANSPORT_GATE,
            "--mode",
            "pixel",
            "--caveman-command",
            str(fake),
            "--authorized",
            "--measured-win",
            "--recoverable",
            "--legible",
            "--model",
            "claude-fable-5",
        )
        self.assertIn("reason=payload-not-dense original-bytes", sparse.stdout)

    def test_default_install_skips_optional_helper_but_explicit_install_includes_it(self) -> None:
        if importlib.util.find_spec("yaml") is None:
            self.skipTest("PyYAML unavailable; bin/install-skills.sh already requires it")
        environment = os.environ.copy()
        environment["HOME"] = self.tmpdir.name
        yaml_origin = importlib.util.find_spec("yaml").origin
        environment["PYTHONPATH"] = str(pathlib.Path(yaml_origin).parent.parent)
        default = subprocess.run(
            [str(INSTALL_SKILLS), "--dry-run"],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertIn("SKIP optional loop-helpers", default.stdout)

        included = subprocess.run(
            [str(INSTALL_SKILLS), "--dry-run", "--include-optional"],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        self.assertEqual(included.returncode, 0, included.stderr)
        self.assertIn("install loop-helpers:", included.stdout)

    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)



class TransportGatePayloadTest(unittest.TestCase):
    """A measured payload replaces the caller's --dense assertion."""

    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)
        self.fake = pathlib.Path(self.tmpdir.name) / "caveman"
        self.fake.write_text("#!/bin/sh\n")
        self.fake.chmod(self.fake.stat().st_mode | stat.S_IXUSR)

    def gate(self, payload: str, *extra: str) -> str:
        path = pathlib.Path(self.tmpdir.name) / "payload.txt"
        path.write_text(payload)
        result = subprocess.run(
            [sys.executable, str(TRANSPORT_GATE), "--mode", "pixel",
             "--caveman-command", str(self.fake), "--authorized", "--measured-win",
             "--recoverable", "--legible", "--model", "claude-fable-5",
             "--payload", str(path), *extra],
            capture_output=True, text=True, check=False,
        )
        return result.stdout

    def test_uniform_prose_payload_passes_on_measured_fill(self) -> None:
        dense = "\n".join("word " * 17 for _ in range(20))
        self.assertIn("decision=use mode=pixel", self.gate(dense))

    def test_ragged_payload_is_skipped_with_its_measured_fill(self) -> None:
        ragged = "x" * 160 + "\n" + "\n".join(["- short", "", "- also short"] * 12)
        out = self.gate(ragged)
        self.assertIn("decision=skip mode=pixel reason=payload-not-dense", out)
        self.assertIn("fill=", out)

    def test_machine_parsed_payload_is_skipped_even_when_it_reads_as_prose(self) -> None:
        # Dense, low identifier share -- it is mostly English inside the fields --
        # but it is re-parsed, so it must survive byte-exactly and cannot.
        blob = json.dumps(
            [{"note": "the refusals stopped on their own with no code change to explain it",
              "done": False} for _ in range(12)],
            separators=(",", ":"),
        )
        wrapped = "\n".join(blob[i:i + 120] for i in range(0, len(blob), 120))
        out = self.gate(wrapped)
        self.assertIn("decision=skip mode=pixel reason=payload-machine-parsed", out)

    def test_structured_fragment_is_skipped_rather_than_passed(self) -> None:
        # A truncated or streamed fragment of machine data does not parse, so a
        # parse-only check waves it through. Skipping costs nothing: the payload
        # is simply sent as text.
        blob = json.dumps([{"note": "prose inside a field"} for _ in range(30)],
                          separators=(",", ":"))[:900]
        wrapped = "\n".join(blob[i:i + 120] for i in range(0, len(blob), 120))
        self.assertIn("reason=payload-structured-unparseable", self.gate(wrapped))

    def test_identifier_dense_payload_is_skipped_despite_perfect_fill(self) -> None:
        blob = "\n".join("a1b2c3d4e5f60718" * 6 for _ in range(20))
        self.assertIn("decision=skip mode=pixel reason=payload-identifier-dense", self.gate(blob))


if __name__ == "__main__":
    unittest.main()


def default_models() -> set[str]:
    """The script's own DEFAULT_PIXEL_MODELS, read from source.

    Restating the set here would make a third copy of the thing this test
    exists to keep in sync.
    """
    spec = importlib.util.spec_from_file_location("transport_gate", TRANSPORT_GATE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    models = module.DEFAULT_PIXEL_MODELS
    assert models, "DEFAULT_PIXEL_MODELS is empty; nothing below would be checked"
    return models


class PixelModelContractTest(unittest.TestCase):
    """The default allowlist lives twice: in the script and in SKILL.md prose.

    SKILL.md used to state that the defaults matched "no current model id" and
    tell the reader to replace them. That was written with no instrument --
    caveman was not installed -- and it was wrong. Measured 2026-09-03 against
    @caveman-ai/cli 1.3.1 / binaries bin-v1.1.4, `caveman-engine pixel simulate
    --model` gives claude-fable-5 (596936 px) and gpt-5.6 (569660 px) their own
    geometry, while an unknown id, a bogus id and an empty id all collapse to
    one identical fallback (915712 px). Both defaults are recognised ids.

    These assertions are hermetic: they pin the two copies against each other
    so the prose and the set cannot drift apart again, and they do not require
    caveman to be installed. A test that skipped without it would be a check
    that cannot fail on any machine that lacks the tool -- which is every
    machine this was wrong on.
    """

    def setUp(self) -> None:
        self.skill = (SKILL_DIR / "references/transport-gate.md").read_text()

    def test_default_models_are_the_documented_ones(self) -> None:
        for model in default_models():
            self.assertIn(model, self.skill, "SKILL.md omits default %r" % model)

    def test_skill_does_not_claim_the_defaults_are_dead(self) -> None:
        # The specific false sentence, and the shape of it.
        self.assertNotIn("no current model id", self.skill)

    def test_skill_says_decision_use_is_not_sufficient(self) -> None:
        # caveman's own think.pixel.models defaults to [], so this gate
        # returning `use` does not mean caveman will pixel anything.
        self.assertIn("not sufficient on its own", self.skill)

    def test_env_override_name_matches_the_script(self) -> None:
        self.assertIn("CAVE_PIXEL_MODELS", self.skill)
        self.assertIn(
            "CAVE_PIXEL_MODELS",
            TRANSPORT_GATE.read_text(),
        )
