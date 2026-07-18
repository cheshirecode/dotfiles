#!/usr/bin/env python3
"""Validate compact cross-skill opt-ins."""

from __future__ import annotations

import argparse
import pathlib
import sys

SKILL_NAME = "example-led-instructions"
CANONICAL_PREAMBLE = (
    "For brittle outputs, invoke $example-led-instructions: "
    "0/1/few-shot gate, max 1-3 examples, skip if obvious."
)
CONSUMER_PREAMBLE = (
    "For brittle outputs, invoke `$example-led-instructions`: "
    "0/1/few-shot gate, max 1-3 examples, skip if obvious."
)
OUTPUT_FIELDS = (
    "shot_count:",
    "format:",
    "examples_or_skip_reason:",
    "risk_check:",
    "acceptance_test:",
)
WORKLOG_RUNTIME_GUARD = "Do not invoke it for normal `/worklog` runtime."
FENCE_MARKER = "```"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=pathlib.Path(__file__).resolve().parents[1],
        type=pathlib.Path,
        help="repository root to validate",
    )
    return parser.parse_args()


def skill_files(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted((root / "skills").glob("*/SKILL.md"))


def relative(path: pathlib.Path, root: pathlib.Path) -> str:
    return str(path.relative_to(root))


def validate_home_skill(root: pathlib.Path, problems: list[str]) -> None:
    skill_md = root / "skills" / SKILL_NAME / "SKILL.md"
    if not skill_md.is_file():
        problems.append(f"skills/{SKILL_NAME}/SKILL.md: missing")
        return

    text = skill_md.read_text()
    for term in (CANONICAL_PREAMBLE, *OUTPUT_FIELDS):
        if term not in text:
            problems.append(f"{relative(skill_md, root)}: missing {term!r}")


def strip_bullet(line: str) -> str:
    stripped = line.strip()
    return stripped[2:].strip() if stripped.startswith("- ") else stripped


def find_mentions(lines: list[str], term: str) -> list[tuple[int, str, bool]]:
    mentions = []
    in_fence = False
    for index, line in enumerate(lines, start=1):
        stripped = line.strip()
        line_in_fence = in_fence or stripped.startswith(FENCE_MARKER)
        if term in line:
            mentions.append((index, line, line_in_fence))
        if stripped.startswith(FENCE_MARKER):
            in_fence = not in_fence
    return mentions


def validate_reference_line(
    root: pathlib.Path,
    path: pathlib.Path,
    line_number: int,
    line: str,
    in_fence: bool,
    problems: list[str],
) -> None:
    rel = relative(path, root)
    stripped = line.strip()
    reference = strip_bullet(line)

    if in_fence:
        problems.append(f"{rel}:{line_number}: $example-led-instructions opt-in is inside a code fence")
    if reference != CONSUMER_PREAMBLE:
        problems.append(
            f"{rel}:{line_number}: $example-led-instructions must use the exact compact opt-in preamble"
        )

    limit = 180 if rel == "skills/worklog/SKILL.md" else 140
    if len(stripped) > limit:
        problems.append(
            f"{rel}:{line_number}: example-led opt-in is {len(stripped)} chars; limit {limit}"
        )


def validate_consumers(root: pathlib.Path, problems: list[str]) -> None:
    home_skill = root / "skills" / SKILL_NAME / "SKILL.md"
    for path in skill_files(root):
        if path == home_skill:
            continue

        lines = path.read_text().splitlines()
        references = find_mentions(lines, SKILL_NAME)

        if len(references) > 1:
            problems.append(
                f"{relative(path, root)}: duplicate $example-led-instructions opt-in; expected at most one"
            )
        for line_number, line, line_in_fence in references:
            validate_reference_line(root, path, line_number, line, line_in_fence, problems)

        if path == root / "skills" / "worklog" / "SKILL.md" and references:
            runtime_guards = find_mentions(lines, WORKLOG_RUNTIME_GUARD)
            has_unfenced_runtime_guard = any(
                not in_fence and line.strip() == WORKLOG_RUNTIME_GUARD
                for _, line, in_fence in runtime_guards
            )
            if not has_unfenced_runtime_guard:
                problems.append(
                    f"{relative(path, root)}: example-led opt-in needs unfenced runtime guard: "
                    f"{WORKLOG_RUNTIME_GUARD}"
                )


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    problems: list[str] = []

    validate_home_skill(root, problems)
    validate_consumers(root, problems)

    if problems:
        print("check-skill-opt-ins: FAIL")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("check-skill-opt-ins: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
