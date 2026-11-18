#!/usr/bin/env python3
"""lessonscan: mechanical scanners for the lessons-to-guards method.

Detects the machine-detectable shapes of recurring failure classes:
  drift-count      literal counts in tests (toHaveCount(N), toEqual(N) on length)
  drift-coord      file:line coordinates baked into prose or tests
  machine-path     absolute machine paths in tracked files
  date-stamp       date-keyed filenames inside source strings
  flatten-replacer JSON.stringify with a replacer array/identifier (collapses nested data)
  swallow          except/catch blocks that pass, continue, or return silently
  string-cast      str(a) != str(b) comparisons (semantic diff by string cast)
  exit-laundering  swallowed errors in a file that also prints success words
  symlink-residue  *.bak files sitting in tracked roots

Exit codes: 0 = clean, 1 = strict findings, 2 = usage error.
Advisory findings print but do not fail unless --strict promotes them.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # python < 3.11
    tomllib = None

SKIP_DIRS = {".git", "node_modules", "dist", "build", ".venv", "venv", "__pycache__", "target", ".next"}
SKIP_FILES = re.compile(r"(package-lock\.json|pnpm-lock\.yaml|Cargo\.lock|\.svg$|\.png$|\.jpg$|\.woff2?$)")

SWALLOW_MULTILINE = re.compile(r"except[^:]*:\s*\n\s*(pass|continue)\b", re.MULTILINE)

RULES: dict[str, dict] = {
    "drift-count": {
        "strict": True,
        "res": [
            re.compile(r"toHaveCount\((\d+)\)"),
            re.compile(r"toHaveLength\((\d+)\)"),
            re.compile(r"assert(?:Strict)?\.equal\([^,]*\.length\s*,\s*(\d+)\)"),
        ],
        "exempt": lambda m, line: int(m.group(1)) <= 1,
        "hint": "count literal in a test — derive it from the registry/loader instead (counts 0/1 are absence assertions and exempt)",
    },
    "drift-coord": {
        "strict": False,
        "res": [re.compile(r"[A-Za-z0-9_./-]+\.(py|ts|tsx|js|sh|md):\d+")],
        "hint": "file:line coordinate in prose or tests — it drifts on the first edit",
    },
    "machine-path": {
        "strict": True,
        "res": [re.compile(r"/mnt/[a-zA-Z]|C:\\\\|/home/[a-z0-9]+/|/Users/[a-zA-Z]+/")],
        "hint": "machine-local absolute path in tracked content",
    },
    "date-stamp": {
        "strict": False,
        "res": [re.compile(r"['\"]/[^'\"]*20\d{2}-\d{2}-\d{2}[^'\"]*['\"]")],
        "hint": "date-keyed path inside a string literal",
    },
    "flatten-replacer": {
        "strict": True,
        "res": [re.compile(r"JSON\.stringify\([^,)]+,\s*(?!null\b|undefined\b|\d)(\[[^\]]*\]|[A-Za-z_$][\w$]*)\s*[),]")],
        "hint": "JSON.stringify replacer array/identifier — the key list applies recursively and collapses nested objects to {}",
    },
    "swallow": {
        "strict": False,
        "res": [
            re.compile(r"except[^:]*:\s*$\n\s*(pass|continue)\b", re.MULTILINE),
            re.compile(r"except\s*:\s*pass"),
            re.compile(r"catch\s*(?:\([^)]*\))?\s*\{\s*\}"),
        ],
        "hint": "swallowed error — justify each one or record and rethrow",
    },
    "string-cast": {
        "strict": False,
        "res": [
            re.compile(r"str\([^)]*\)\s*(!=|==)\s*str\("),
            re.compile(r"String\([^)]*\)\s*(!==?|===?)\s*String\("),
        ],
        "hint": "string-cast comparison — 80.0 vs '80' is equal as number, different as string",
    },
    "exit-laundering": {
        "strict": False,
        "res": [
            re.compile(r"print\(['\"][^'\"]*(complete|success|done|finished)", re.IGNORECASE),
        ],
        "hint": "success print in a file that also swallows errors — assert the exit code reflects failures",
    },
    "symlink-residue": {
        "strict": True,
        "res": [],
        "hint": "*.bak file in a tracked root — leftover from a backup step that followed a symlink",
    },
}


def iter_text_files(root: Path) -> list[Path]:
    out: list[Path] = []
    for path in sorted(root.rglob("*")):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if SKIP_FILES.search(path.name):
            continue
        if not path.is_file():
            continue
        try:
            path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        out.append(path)
    return out


def scan(root: Path, config: dict) -> tuple[list[str], list[str]]:
    strict_findings: list[str] = []
    advisory: list[str] = []
    allowlist: dict[str, str] = {a["rule"]: a["pattern"] for a in config.get("allowlist", [])}
    seen_files: list[Path] = iter_text_files(root)

    for path in seen_files:
        rel = str(path.relative_to(root))
        if path.name.endswith(".bak"):
            strict_findings.append(f"symlink-residue {rel}: *.bak file in tracked tree")
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, PermissionError):
            continue
        text = "\n".join(lines)
        file_has_swallow = bool(SWALLOW_MULTILINE.search(text))
        for lineno, line in enumerate(lines, start=1):
            for rule, spec in RULES.items():
                if rule == "exit-laundering":
                    continue
                for rx in spec["res"]:
                    m = rx.search(line)
                    if not m:
                        continue
                    exempt = spec.get("exempt")
                    if exempt and exempt(m, line):
                        continue
                    allow = allowlist.get(rule)
                    if allow and (re.search(allow, line, re.IGNORECASE) or re.search(allow, rel, re.IGNORECASE)):
                        continue
                    entry = f"{rule} {rel}:{lineno}: {line.strip()[:120]}\n    -> {spec['hint']}"
                    if spec["strict"]:
                        strict_findings.append(entry)
                    else:
                        advisory.append(entry)
                    break
        if file_has_swallow:
            for lineno, line in enumerate(lines, start=1):
                for rx in RULES["exit-laundering"]["res"]:
                    if rx.search(line):
                        advisory.append(
                            f"exit-laundering {rel}:{lineno}: {line.strip()[:120]}\n    -> {RULES['exit-laundering']['hint']}"
                        )
                        break

    # config-driven cross-corpus near-duplicate check
    for pair in config.get("duplication", []):
        try:
            left = extract_corpus(root, pair["left"])
            right = extract_corpus(root, pair["right"])
        except KeyError as exc:
            advisory.append(f"duplication config error: missing key {exc} in {pair.get('name', '?')}")
            continue
        threshold = float(pair.get("threshold", 0.8))
        for la, la_text in left:
            for lb, lb_text in right:
                ov = token_overlap(la_text, lb_text)
                if ov >= threshold:
                    advisory.append(
                        f"duplication {pair.get('name', '?')}: {la} vs {lb} overlap {ov:.2f}\n"
                        f"    -> '{la_text[:80]}' | '{lb_text[:80]}'"
                    )

    # config-driven set-equality checks
    for pair in config.get("set-equality", []):
        try:
            left = extract_set(root, pair["left"])
            right = extract_set(root, pair["right"])
        except (KeyError, FileNotFoundError) as exc:
            advisory.append(f"set-equality config error in {pair.get('name', '?')}: {exc}")
            continue
        only_left = sorted(left - right)
        only_right = sorted(right - left)
        if only_left or only_right:
            advisory.append(
                f"set-equality {pair.get('name', '?')}: only-left={only_left} only-right={only_right}\n"
                f"    -> registries diverged; derive one side from the other"
            )

    return strict_findings, advisory


def extract_corpus(root: Path, spec: dict) -> list[tuple[str, str]]:
    glob = spec["glob"]
    rx = re.compile(spec["line_regex"])
    min_len = int(spec.get("min_length", 12))
    out: list[tuple[str, str]] = []
    for path in sorted(root.glob(glob)):
        if not path.is_file():
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for m in rx.finditer(line):
                text = m.group(1)
                if len(text) >= min_len:
                    out.append((f"{path.relative_to(root)}:{lineno}", text))
    return out


def extract_set(root: Path, spec: dict) -> set[str]:
    if "dir_glob" in spec:
        name_rx = re.compile(spec["name_regex"]) if "name_regex" in spec else None
        results = set()
        for path in root.glob(spec["dir_glob"]):
            name = path.name
            if name_rx:
                m = name_rx.search(name)
                if not m:
                    continue
                name = m.group(1)
            if path.is_dir() or not spec.get("is_dir", False):
                results.add(name)
        return results
    if "file" in spec:
        rx = re.compile(spec["line_regex"])
        out = set()
        for line in (root / spec["file"]).read_text(encoding="utf-8").splitlines():
            m = rx.search(line)
            if m:
                out.add(m.group(1).strip())
        return out
    raise KeyError("set spec needs dir_glob or file")


def token_overlap(a: str, b: str) -> float:
    toks = lambda s: {w for w in re.sub(r"[^a-z ]", " ", s.lower()).split() if len(w) > 2}
    ta, tb = toks(a), toks(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / max(len(ta), len(tb))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("root", help="repo root to scan")
    ap.add_argument("--config", help="TOML config with [[duplication]] / [[set-equality]] blocks")
    ap.add_argument("--strict", action="store_true", help="fail on advisory findings too")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"lessonscan: not a directory: {root}", file=sys.stderr)
        return 2
    config: dict = {}
    if args.config:
        if tomllib is None:
            print("lessonscan: tomllib unavailable for python < 3.11", file=sys.stderr)
            return 2
        config = tomllib.loads(Path(args.config).read_text(encoding="utf-8"))

    strict, advisory = scan(root, config)
    for line in strict:
        print(f"STRICT  {line}")
    for line in advisory:
        print(f"ADVISORY {line}")
    print(f"lessonscan: {len(strict)} strict, {len(advisory)} advisory findings")
    if strict or (args.strict and advisory):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
