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
# <b> as well as <strong>. The scope is "the author marked this as carrying
# weight", and a hand-authored <b> meets that test exactly as much; the split is
# authoring provenance, not intent, since Markdown-to-HTML emits <strong> while
# hand-written HTML tends to emit <b>. Measured on a four-page corpus, matching
# <strong> alone inspected 1 of 72 emphasised numeric claims and printed OK.
# `<b\b` does not match <br> or <body>, because b-r and b-o are both word pairs.
EMPHASIS = re.compile(r"<(?:strong|b)\b[^>]*>(.*?)</(?:strong|b)>", re.S | re.I)
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
    """[(index, real_id_or_None, block)] in document order.

    A synthetic id used to stand in for a missing one and then surfaced in
    findings as `__unnamed_2`, which locates nothing for the person fixing it.
    Only a REAL id can be an anchor target, so the two are kept apart.
    """
    out = []
    for i, m in enumerate(SECTION.finditer(html), 1):
        block = m.group(0)
        sid = SECTION_ID.search(block)
        out.append((i, sid.group(1) if sid else None, block))
    return out


def coverage(html):
    """What the gate actually looked at: (sections, inspected, unemphasised).

    A flag rate means nothing without this. Reporting what was NOT inspected is
    what makes the next scope gap visible without anyone having to predict it.
    Deliberately a report and not a refusal: a prose page, or one whose numbers
    all sit in tables, legitimately has nothing to inspect and is not thereby
    unsafe, and a refusal the author cannot act on just teaches people to
    bypass the gate.
    """
    sections = _sections(html)
    inspected = unemphasised = 0
    for _idx, _rid, block in sections:
        inspected += sum(1 for s in EMPHASIS.findall(block) if NUMERIC.search(s))
        outside = re.sub(r"<[^>]+>", " ", EMPHASIS.sub(" ", block))
        unemphasised += len(NUMERIC.findall(outside))
    return len(sections), inspected, unemphasised


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
        return ['no <section> elements: evidence scope cannot be established — '
                'wrap each part in <section id="..."> so a claim has a scope and '
                'a cross-reference has something to point at']

    total = len(sections)
    by_id = {rid: idx for idx, rid, _ in sections if rid}
    blocks = {idx: block for idx, _rid, block in sections}
    direct = {idx: _has_direct_evidence(b, classes, hosts) for idx, b in blocks.items()}

    def reachable(idx, seen):
        # A same-page anchor to a section that carries evidence counts: that is
        # what makes a cross-reference a fix rather than a dodge. Cycles are
        # guarded, so a pair of sections pointing at each other cannot invent
        # evidence neither of them has.
        if idx in seen:
            return False
        seen.add(idx)
        if direct.get(idx):
            return True
        return any(reachable(by_id[t], seen)
                   for t in ANCHOR.findall(blocks.get(idx, "")) if t in by_id)

    for idx, rid, block in sections:
        claims = [re.sub(r"<[^>]+>", "", s).strip()
                  for s in EMPHASIS.findall(block) if NUMERIC.search(s)]
        if claims and not reachable(idx, set()):
            shown = "; ".join(c[:60] for c in claims[:3])
            where = (f"section {rid!r}" if rid else
                     f"section {idx} of {total} (no id — add one so a "
                     f"cross-reference can point at the evidence)")
            problems.append(
                f"{where}: emphasised numeric claim with no evidence "
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
    secs, inspected, outside = coverage(html)
    print(f"  coverage: {secs} section(s); {inspected} emphasised numeric claim(s) "
          f"inspected; {outside} standalone number(s) outside emphasis not inspected")
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
