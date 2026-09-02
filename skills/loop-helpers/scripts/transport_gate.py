#!/usr/bin/env python3
"""Choose an optional recoverable transport without performing the transport."""

from __future__ import annotations

import argparse
import os
import shutil


DEFAULT_PIXEL_MODELS = {"claude-fable-5", "gpt-5.6"}


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
    result.add_argument("--caveman-command", default="caveman")
    return result


def emit(decision: str, mode: str, reason: str, hint: str = "") -> int:
    remedy = f" hint={hint}" if hint else ""
    fallback = " original-bytes" if decision == "skip" else ""
    print(f"decision={decision} mode={mode} reason={reason}{remedy}{fallback}")
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
        if not args.dense:
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
