#!/usr/bin/env python3
"""Compare explicit skill route payloads; optional tokens require tiktoken.

File sets describe expected reads, not observed agent behavior. Counts exclude
tool wrappers, messages, caching, and billing. Each resolved file is read once.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def payload(root: Path, files: list[str]) -> str:
    paths = dict.fromkeys((root / name).resolve() for name in files)
    return "\n\n".join(path.read_text(encoding="utf-8") for path in paths)


def counts(text: str, encoder=None) -> dict:
    return {
        "bytes": len(text.encode("utf-8")),
        "words": len(text.split()),
        "tokens": len(encoder.encode(text, disallowed_special=())) if encoder else None,
    }


def compare(routes: dict, before: Path, after: Path, encoder=None) -> list[dict]:
    result = []
    for name, route in routes.items():
        old = counts(payload(before, route["before"]), encoder)
        new = counts(payload(after, route["after"]), encoder)
        result.append({
            "route": name,
            "before": old,
            "after": new,
            "reduction_percent": {
                key: round(100 * (old[key] - new[key]) / old[key], 2)
                if old[key] else None
                for key in old
            },
        })
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True, help="baseline source directory")
    parser.add_argument("--after", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--routes", type=Path, required=True, help="JSON name -> before/after file lists")
    parser.add_argument("--encoding", help="explicit tiktoken encoding, e.g. o200k_base")
    args = parser.parse_args()
    encoder = None
    if args.encoding:
        try:
            import tiktoken
        except ImportError:
            parser.error("--encoding requires tiktoken; omit it for bytes/words only")
        try:
            encoder = tiktoken.get_encoding(args.encoding)
        except ValueError as exc:
            parser.error(str(exc))
    try:
        routes = json.loads(args.routes.read_text(encoding="utf-8"))
        rows = compare(routes, args.before, args.after, encoder)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        parser.error(str(exc))
    print(json.dumps({"encoding": args.encoding, "routes": rows}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
