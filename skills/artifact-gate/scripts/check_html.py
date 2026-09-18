#!/usr/bin/env python3
"""Refuse to publish malformed artifact HTML.

Reads the document only; verify_links.py reads the repositories it points at.

    check_html.py page.html [--count-claim MARKER:NOUN ...] [--allow-wrapper]

Exit 0 clean, 1 findings, 2 usage. See ../references/gates.md for why each
gate exists; every one of them is here because it failed in production.
"""
import argparse
import pathlib
import re
import sys

PAIRED = [
    "p", "div", "section", "article", "table", "tr", "td", "th", "thead",
    "tbody", "caption", "dl", "dd", "dt", "ol", "ul", "li", "svg", "details",
    "summary", "pre", "a", "span", "header", "footer", "nav",
]

# one..thirty, so a page can state its count in words. Extending this list is
# NOT what keeps the check alive -- an absent claim is a failure (see below),
# so a count past the end of the list cannot silently retire the gate.
_ONES = ["one", "two", "three", "four", "five", "six", "seven", "eight",
         "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
         "sixteen", "seventeen", "eighteen", "nineteen"]
NUMBER_WORDS = {w: i + 1 for i, w in enumerate(_ONES)}
NUMBER_WORDS["twenty"] = 20
NUMBER_WORDS["thirty"] = 30
for _i, _w in enumerate(_ONES[:9]):
    NUMBER_WORDS[f"twenty-{_w}"] = 21 + _i


def check(html, count_claims=(), allow_wrapper=False):
    problems = []

    # Tag NAMES, not prefixes: "<p" also matches "<pre", "<li" also matches
    # "<link". A probe that is wrong in this way looks exactly like a broken
    # page, and refused two valid ones before it was noticed.
    for tag in PAIRED:
        opened = len(re.findall(r"<%s(?=[\s>/])" % tag, html))
        closed = len(re.findall(r"</%s\s*>" % tag, html))
        if opened != closed:
            problems.append(f"unbalanced <{tag}>: {opened} open, {closed} close")

    if not allow_wrapper:
        for stray in ("<html", "<body", "<!doctype"):
            if stray in html.lower():
                problems.append(
                    f"{stray!r} present - the publish step adds the wrapper, "
                    "do not ship one (pass --allow-wrapper for a standalone file)"
                )

    # A relative href in a published artifact is a dead link. Same-page
    # fragments are how the document navigates itself, so they are allowed --
    # without that carve-out this gate fires on the page's own contents list.
    for href in sorted(set(re.findall(r'href="([^"]+)"', html))):
        if not href.startswith(("https://", "#")):
            problems.append(f"non-absolute href: {href!r}")

    ids = re.findall(r'id="([^"]+)"', html)
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        problems.append(f"duplicate id(s): {dupes}")
    for frag in sorted(set(re.findall(r'href="#([^"]+)"', html))):
        if frag not in ids:
            problems.append(f"dead anchor: #{frag} matches no id")

    # Claims the page makes about itself, which drift whenever content is added
    # and nothing else notices. An ABSENT claim is a failure: a gate that fires
    # only when it finds a sentence retires itself the moment someone deletes
    # the sentence, and goes quiet exactly when the document is largest.
    for marker, noun in count_claims:
        actual = len(re.findall(r'class="[^"]*\b%s\b[^"]*"' % re.escape(marker), html))
        claimed = {n for w, n in NUMBER_WORDS.items()
                   if re.search(r"\b%s %s\b" % (w, re.escape(noun)), html, re.I)}
        claimed |= {int(d) for d in
                    re.findall(r"\b(\d+) %s\b" % re.escape(noun), html, re.I)}
        if not claimed:
            problems.append(
                f"page contains {actual} {noun} but never states the count - "
                "nothing is holding the two in agreement any more"
            )
        elif actual not in claimed:
            problems.append(
                f"self-claim mismatch: page says {sorted(claimed)} {noun}, "
                f"contains {actual}"
            )
    return problems


def _claim(value):
    if value.count(":") != 1 or not all(p.strip() for p in value.split(":")):
        raise argparse.ArgumentTypeError("expected MARKER:NOUN, e.g. qnum:questions")
    marker, noun = value.split(":")
    return marker.strip(), noun.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("path", type=pathlib.Path)
    ap.add_argument("--count-claim", type=_claim, action="append", default=[],
                    metavar="MARKER:NOUN",
                    help="elements with class MARKER must match the page's stated count of NOUN")
    ap.add_argument("--allow-wrapper", action="store_true",
                    help="the file is standalone, so html/body/doctype are expected")
    args = ap.parse_args(argv)

    try:
        html = args.path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"check_html: cannot read {args.path}: {exc}", file=sys.stderr)
        return 2

    problems = check(html, args.count_claim, args.allow_wrapper)
    if problems:
        print(f"check_html: {args.path} must not be published:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print(f"check_html: OK ({args.path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
