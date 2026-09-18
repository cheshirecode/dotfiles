# Why each gate exists

Distilled from four sessions whose worst bugs shared one shape: the target
resolved and the claim about it was wrong. Each rule below is here because it
failed in production, not because it seemed prudent.

## The rules the scripts encode

1. **Never read the working tree.** A shared checkout moves under you, so
   `git show HEAD:path` returns whatever a colleague has checked out, not what
   the reader will see. Everything goes through an explicit ref.

2. **Existing is not reachable.** `git cat-file -t` answers `commit` for an
   object no branch contains, so a pin to a rebased-away commit passes an
   existence check and is still a dead citation. `merge-base --is-ancestor` is
   the check that measures the claim.

3. **Line-exists is not line-says.** A file that still has 140 lines passes a
   bounds check while line 140 says something else entirely. `data-expect` on
   an anchor declares what the cited range must contain, turning "name the
   symbol" from authoring discipline into a gate.

4. **Fail closed, in three states.** A missing clone means the links were
   **not** verified — a finding, not a reason to print OK. But a link is not
   either verified or broken; there are three states: **verified**,
   **recognised but unverifiable here** (a merge request or issue, which needs
   API access this script deliberately does not have), and **unrecognised**.
   Only the last is a failure. Collapsing the middle state into failure was a
   real bug: the first version refused a merge-request citation, which meant
   the only way to publish a page carrying one was to bypass the gate — and a
   gate that must be bypassed stops being run. Collapsing it into success is
   the opposite error. Count and name all three, so "unverified" can never
   read as "verified".

5. **Match tag names, not prefixes.** `count("<p")` also matches `<pre`, and
   `count("<li")` also matches `<link`. One page checker refused valid pages
   twice for this. Use a name boundary: `<p(?=[\s>])`. A broken probe looks
   exactly like a broken page, so this costs more than it appears to.

6. **Allow same-page fragments** in the absolute-href check, or the page's own
   section ids trip a gate aimed at relative paths.

7. **Dead anchors and duplicate ids.** A `#fragment` naming no id is a link
   that silently does nothing; a duplicated id sends two contents entries to
   the same place. Neither is visible by reading the page.

8. **An absent self-claim is a failure.** A count check that only fires when
   it finds a claim retires itself the moment someone deletes the sentence —
   going quiet exactly when the document is largest. One earlier version used
   a word list that stopped at "twenty" and silently stopped checking at 21
   items. Read digits and words, and treat "no claim at all" as a finding.

## A gate that was proposed, measured, and rejected

The failure that keeps landing is a claim that was **true when written** and
quietly became false. No internal-consistency check can see it.

The proposal: flag any number in the prose that does not also appear in a query
or computation shown in the document, so an unsourced figure must be justified
or dropped. It was motivated by two real misses — `711.88` printed for a
`710.88` sum, and "two-thirds are partials" carried over from a 6-sample when
the figure at n=19 was 37%.

**Do not implement it as specified.** Measured on one document (123 distinct
numeric tokens in visible prose), which was unusually well sourced — it carried
SQL panels and per-section evidence rows:

| rule | flagged | rate |
| --- | ---: | ---: |
| naive: number absent from any shown query or computation | 83 | 67% |
| ignoring identifiers (no thousands separator) | 57 | 46% |
| also accepting numbers in a table or evidence row | 53 | 43% |

The survivors are mostly not errors: a line range from a `file.py:49,56`
citation, a merge-request number, a documented `5.00` minimum, a `1.7` that is
"1.7 days". This is one document measured by one session, not a general rate —
but a floor of 43% on a well-sourced page is enough to decide against it.

The reason is this skill's own subject. "Does this number appear in a shown
query" is a proxy for "is this number sourced", and in a real document most
sourced numbers are sourced by a *link* to a dashboard or warehouse, or by a
table — not by an inline query. The check answers a nearby question, which is
exactly the failure named at the top of this file. A gate that fires on 43% of
a good page gets ignored, and an ignored gate is worse than none.

A narrower version that might survive, unbuilt and unmeasured: require every
number inside `<strong>` — the emphasised claims, not every digit on the page —
to carry an evidence link in the same section. That targets the figures which
carry weight and ignores the incidental ones.

## Validating a gate

Force it red before trusting a green. `tests/test_artifact_gate.py` is built
that way: every gate has a case that constructs input which must trip it, and
a clean case proving it does not fire on good input. A gate with only a clean
case certifies nothing.

When adding one, add both halves, and check that the red arrives through the
assertion you meant rather than through a broken fixture — a `SyntaxError` and
a caught defect look identical in a pass/fail column.
