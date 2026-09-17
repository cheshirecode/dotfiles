#!/usr/bin/env python3
"""Choose an optional recoverable transport without performing the transport."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil


DEFAULT_PIXEL_MODELS = {"claude-fable-5", "gpt-5.6"}

# Monospace advance width and line height as a fraction of font size, measured
# against DejaVu Sans Mono; override for another face. An image costs
# width*height/750 tokens, so cost per character is (char_w*line_h)/750 divided
# by the fill ratio -- the share of the bounding box that is actually text,
# since one long line sets the width every short line then pays for.
DEFAULT_CHAR_WIDTH_RATIO = 0.602
DEFAULT_LINE_HEIGHT_RATIO = 1.35
DEFAULT_TEXT_TOKENS_PER_CHAR = 0.25
DEFAULT_MAX_IDENTIFIER_SHARE = 0.15
IMAGE_PIXELS_PER_TOKEN = 750

# Spans where one wrong glyph is unrecoverable and undetectable: hex runs,
# base64-ish blobs, flags, screaming-snake names, URLs and backticked code.
IDENTIFIER_PATTERNS = (
    r"`[^`]+`",
    r"https?://\S+",
    r"\b[0-9a-f]{6,}\b",
    r"\b[A-Z][A-Z0-9_]{3,}\b",
    r"--[A-Za-z][\w-]*",
    r"\b(?=[A-Za-z0-9]*[0-9])(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{8,}\b",
)


def fill_ratio(text: str) -> tuple[float, int, int]:
    """Share of the rendered bounding box that is actually characters."""
    lines = [line.rstrip() for line in text.splitlines()]
    if not lines:
        return 0.0, 0, 0
    columns = max((len(line) for line in lines), default=0)
    if columns == 0:
        return 0.0, 0, len(lines)
    return sum(len(line) for line in lines) / (columns * len(lines)), columns, len(lines)


def identifier_share(text: str) -> float:
    """Share of characters inside spans that cannot survive a misread."""
    if not text:
        return 0.0
    covered = set()
    for pattern in IDENTIFIER_PATTERNS:
        for match in re.finditer(pattern, text):
            covered.update(range(match.start(), match.end()))
    return len(covered) / len(text)


def structured_verdict(text: str) -> str:
    """Classify a payload that is re-parsed rather than read.

    Density and identifier share both look favourable for structured data whose
    fields happen to hold prose, but a document that is parsed again cannot
    tolerate a single misread glyph. Rendering for display strips the newlines
    that wrapping added, so try the joined form too.

    A truncated or streamed fragment does not parse, and a parse-only test waves
    it through. Both verdicts therefore skip: skipping costs nothing, because the
    payload is simply sent as text.
    """
    if text.lstrip()[:1] not in ("{", "["):
        return ""
    for candidate in (text, "".join(text.split("\n"))):
        try:
            json.loads(candidate)
            return "payload-machine-parsed"
        except ValueError:
            continue
    return "payload-structured-unparseable"


def required_fill(args: argparse.Namespace) -> float:
    char_width = args.char_width_ratio * args.font_size
    line_height = args.line_height_ratio * args.font_size
    per_char = char_width * line_height / IMAGE_PIXELS_PER_TOKEN
    return per_char / args.text_tokens_per_char


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Gate shrink, Pixel, or skill conversion and fail open."
    )
    result.add_argument("--mode", choices=("shrink", "pixel", "convert"), required=True)
    result.add_argument("--authorized", action="store_true")
    result.add_argument("--measured-win", action="store_true")
    result.add_argument("--recoverable", action="store_true")
    result.add_argument("--producer-status-preserved", action="store_true")
    result.add_argument("--dense", action="store_true")
    result.add_argument("--legible", action="store_true")
    result.add_argument("--installed-copy", action="store_true")
    result.add_argument("--model")
    result.add_argument(
        "--payload",
        help="file whose density and identifier share are MEASURED, superseding --dense",
    )
    result.add_argument("--font-size", type=int, default=10)
    result.add_argument("--char-width-ratio", type=float, default=DEFAULT_CHAR_WIDTH_RATIO)
    result.add_argument("--line-height-ratio", type=float, default=DEFAULT_LINE_HEIGHT_RATIO)
    result.add_argument(
        "--text-tokens-per-char", type=float, default=DEFAULT_TEXT_TOKENS_PER_CHAR
    )
    result.add_argument(
        "--max-identifier-share", type=float, default=DEFAULT_MAX_IDENTIFIER_SHARE
    )
    result.add_argument("--caveman-command", default="caveman")
    return result


def emit(decision: str, mode: str, reason: str, hint: str = "", detail: str = "") -> int:
    remedy = f" hint={hint}" if hint else ""
    measured = f" {detail}" if detail else ""
    fallback = " original-bytes" if decision == "skip" else ""
    print(f"decision={decision} mode={mode} reason={reason}{remedy}{measured}{fallback}")
    return 0


def main() -> int:
    args = parser().parse_args()
    if not shutil.which(args.caveman_command):
        return emit("skip", args.mode, "caveman-unavailable")
    if not args.authorized:
        return emit("skip", args.mode, "authorization-missing")
    if not args.measured_win:
        return emit("skip", args.mode, "measured-win-missing")
    if not args.recoverable:
        return emit("skip", args.mode, "recovery-missing")

    if args.mode == "shrink" and not args.producer_status_preserved:
        return emit("skip", args.mode, "producer-status-unpreserved")
    if args.mode == "convert" and not args.installed_copy:
        return emit("skip", args.mode, "installed-copy-required")
    if args.mode == "pixel":
        if args.payload:
            try:
                text = pathlib.Path(args.payload).read_text()
            except OSError as error:
                return emit("skip", args.mode, "payload-unreadable", str(error.strerror))
            structured = structured_verdict(text)
            if structured:
                return emit("skip", args.mode, structured)
            measured, columns, lines = fill_ratio(text)
            needed = required_fill(args)
            detail = (
                f"fill={measured:.2f} need={needed:.2f} "
                f"cols={columns} lines={lines} size={args.font_size}"
            )
            if measured < needed:
                return emit("skip", args.mode, "payload-not-dense", detail=detail)
            share = identifier_share(text)
            if share > args.max_identifier_share:
                return emit(
                    "skip",
                    args.mode,
                    "payload-identifier-dense",
                    detail=f"{detail} identifiers={share:.2f} max={args.max_identifier_share:.2f}",
                )
        elif not args.dense:
            return emit("skip", args.mode, "payload-not-dense")
        if not args.legible:
            return emit("skip", args.mode, "model-legibility-missing")
        configured = {
            value.strip()
            for value in os.environ.get(
                "CAVE_PIXEL_MODELS", ",".join(sorted(DEFAULT_PIXEL_MODELS))
            ).split(",")
            if value.strip()
        }
        if not args.model or args.model not in configured:
            return emit(
                "skip", args.mode, "model-not-configured", "set-CAVE_PIXEL_MODELS"
            )

    return emit("use", args.mode, "all-gates-passed")


if __name__ == "__main__":
    raise SystemExit(main())
