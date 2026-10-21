---
name: artifact-gate
description: "Gate an HTML artifact before publishing - tag balance, dead anchors, duplicate ids, non-absolute links, self-claims that drifted, and code links that still resolve while no longer saying what the page claims. Use before publishing or updating a shared HTML page, when asked whether its links and counts are still true, or for an on-demand design review that avoids machine-generated-looking design."
---

# Gate an HTML artifact before it is published

Every failure in this class returns something **valid**. A resolvable link to
code that moved. A real dashboard that is the wrong rail. A field that exists
but is date-granular. A hook that is silent because it is rate-limited, not
because it is healthy. A sum that adds up and was typed wrong. Nothing errors.

The corollary governs how you use everything below:

> **A check that has never failed has not been shown to work.** Force every
> gate red before trusting a green.

## Three gates

`check_html.py` reads the document. `verify_links.py` reads the repositories
the document points at, which is where the interesting failures live.
`check_evidence.py` asks whether each emphasised numeric claim still has
evidence a reader can reach from the section it sits in.

```bash
python3 scripts/check_html.py page.html --count-claim qnum:questions
python3 scripts/verify_links.py page.html --repo name=/path/to/clone \
  --forge-host git.example.com --forge-namespace example-org
python3 scripts/check_evidence.py page.html --evidence-host metrics.example.com
```

All exit 0 clean, 1 on findings, 2 on a usage or environment error. None reads
a working tree: every lookup goes through an explicit ref, because a shared
checkout has a colleague's HEAD, not the reader's.

The evidence gate is scoped to `strong`, a proxy for "the author marked this as
carrying weight". It will miss an unemphasised figure — the trade that keeps
its flag rate low enough that the output gets read.

Run both before publishing, and again before telling anyone the page is still
accurate. Read [references/gates.md](references/gates.md) before changing
either script or adding a gate — each rule there was earned by a real failure,
and the negative tests in `tests/` are the way any new gate is validated.

## Before you link to code at all

Ask whether the reference belongs on that page. A line number is the most
fragile fact in a document, and a page written for a product audience is
usually better with none. Code references belong where the reader is an
engineer and staleness is cheap. **Choosing the register often does the work
the URL choice is trying to do.**

Then, if it stays:

- A link **with** a line anchor asserts "line N says X" — true at exactly one
  commit. Pin it to a sha. On a branch it keeps resolving while silently
  ceasing to be true.
- A link **without** one only says "this lives here". Leave it on the branch;
  the reader wants today's file.

Name the symbol in the link text, not just the line, so drift is visible to
the reader rather than only to a script.

## When a pin moves

Re-read the code and record **whether the claim survived**, not just that the
link was updated. That is what stops the next reader re-deriving it.

## Design review: impeccable, on demand

The gates above check that a page is correct. Whether it is well designed is a
separate review, run when the page is new or its layout changed, and only when
asked for: impeccable is installed as a plain skill with no hooks
(`bin/install-impeccable.sh`), and it must stay that way.

```bash
~/.claude/skills/impeccable/scripts/impeccable detect --no-advisory page.html
```

Or `/impeccable critique` for a scored review, and `/impeccable audit` for
accessibility and responsive checks. `detect` exits 2 on findings. It is a
static scan, so check each finding against the rendered page before acting:
on a dark-themed page it has reported contrast against colours the page never
shows.

Never enable the plugin or run `/impeccable hooks on` to get the review
automatically. Its hooks run a downloaded program after every edit in every
session, with that session's credentials in its environment.

Then read [references/deslop.md](references/deslop.md): the patterns that make
a page read as machine-generated, which ones the scan catches, and which only a
reader does.
