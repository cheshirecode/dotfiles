#!/usr/bin/env python3
"""Refuse to publish an emphasised numeric claim whose evidence is unreachable.

Scoped to <strong>, which is a proxy for "the author marked this as carrying
weight". It will miss an unemphasised figure; that is the trade that keeps the
flag rate low enough to read. Measured on one document: 3% of emphasised
numeric claims, against 43% for the same idea applied to every number.

What it catches is structural, not textual: a claim whose evidence stopped
being REACHABLE. Adding a table of contents turns every section into an entry
point, so evidence a reader used to meet on the way down is no longer on the
path. Nothing else in this skill looks at that.

    check_evidence.py page.html [--evidence-class evidence] [--evidence-host HOST]

Exit 0 clean, 1 findings, 2 usage. See ../references/gates.md.
"""
import argparse
import pathlib
import re
import sys

SECTION = re.compile(r'<section\b[^>]*>.*?</section>', re.S | re.I)
SECTION_ID = re.compile(r'<section\b[^>]*\bid="([^"]+)"', re.I)
STRONG = re.compile(r"<strong\b[^>]*>(.*?)</strong>", re.S | re.I)
# A STANDALONE number, not any digit. `\d` also matches a date, a ticket id, a
# version and a unit -- 2026-09-17, SPLUS-19835, v3_3_0, 5xx, 3s -- none of
# which is a measurement, and all of which are ordinary in these documents.
# That is the years-and-identifiers false-positive class that sank the broad
# form of this check, reappearing inside the narrow one. It also matters that
# the 3% rate in gates.md was measured with THIS matcher: on `\d` the same page
# yields 71 emphasised spans instead of 56, and all 15 extra ones are false.
NUMERIC = re.compile(r"(?<![\w.#-])\d[\d,]*(?:\.\d+)?(?![\w%-]*[\w])")
ANCHOR = re.compile(r'href="#([^"]+)"')
DEFAULT_EVIDENCE_CLASSES = ("evidence",)
DEFAULT_EVIDENCE_TAGS = (r"<details\b[^>]*\bclass=\"[^\"]*\bsql\b", r"/-/blob/", r"/blob/")


def _sections(html):
    """id -> section html. Order preserved; unnamed sections get a synthetic id."""
    out, n = {}, 0
    for m in SECTION.finditer(html):
        block = m.group(0)
        sid = SECTION_ID.search(block)
        n += 1
        out[sid.group(1) if sid else f"__unnamed_{n}"] = block
    return out


def _has_direct_evidence(block, classes, hosts):
    for cls in classes:
        if re.search(r'class="[^"]*\b%s\b[^"]*"' % re.escape(cls), block):
            return True
    for pat in DEFAULT_EVIDENCE_TAGS:
        if re.search(pat, block, re.I):
            return True
    return any(host in block for host in hosts)


def check(html, classes=DEFAULT_EVIDENCE_CLASSES, hosts=()):
    problems = []
    sections = _sections(html)
    if not sections:
        # Fail closed. With no sections there is no scope to judge reachability
        # in, and a gate that passes everything because it found nothing to look
        # at is the silent failure this skill is about.
        return ["no <section> elements: evidence scope cannot be established"]

    direct = {sid: _has_direct_evidence(b, classes, hosts) for sid, b in sections.items()}

    def reachable(sid, seen):
        # A same-page anchor to a section that carries evidence counts: that is
        # what makes a cross-reference a fix rather than a dodge. Cycles are
        # guarded, so a pair of sections pointing at each other cannot invent
        # evidence neither of them has.
        if sid in seen:
            return False
        seen.add(sid)
        if direct.get(sid):
            return True
        return any(reachable(t, seen) for t in ANCHOR.findall(sections.get(sid, ""))
                   if t in sections)

    for sid, block in sections.items():
        claims = [re.sub(r"<[^>]+>", "", s).strip()
                  for s in STRONG.findall(block) if NUMERIC.search(s)]
        if claims and not reachable(sid, set()):
            shown = "; ".join(c[:60] for c in claims[:3])
            problems.append(
                f"section {sid!r}: emphasised numeric claim with no evidence "
                f"reachable from this section ({shown})"
            )
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("path", type=pathlib.Path)
    ap.add_argument("--evidence-class", action="append", default=[], metavar="CLASS",
                    help="class marking an evidence block (default: evidence)")
    ap.add_argument("--evidence-host", action="append", default=[], metavar="HOST",
                    help="repeatable; a dashboard or warehouse host that counts as evidence")
    args = ap.parse_args(argv)
    try:
        html = args.path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"check_evidence: cannot read {args.path}: {exc}", file=sys.stderr)
        return 2
    problems = check(html, tuple(args.evidence_class) or DEFAULT_EVIDENCE_CLASSES,
                     tuple(args.evidence_host))
    if problems:
        print(f"check_evidence: {args.path} must not be published:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"check_evidence: OK ({args.path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
