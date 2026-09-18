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

4. **Fail closed.** A missing clone means the links were **not** verified —
   that is a finding, not a reason to print OK. Same for a link form the
   script does not recognise: count and report it rather than passing over it.
   Silence is the dangerous shape.

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

## The one gate none of this builds

The failure that keeps landing is a claim that was **true when written** and
quietly became false. No internal-consistency check can see it.

The proposed proxy: flag any number in the prose that does not also appear in
a query, table or computation shown in the document, so an unsourced figure
must be justified or dropped. Concrete misses it would have caught: `711.88`
printed for a `710.88` sum, and "two-thirds are partials" carried over from a
6-sample when the figure at n=19 was 37%.

This is not implemented. It is written down because the next person to reach
for it should know it is wanted and why, and should expect the hard part to be
the false-positive rate on years, versions and identifiers.

## Validating a gate

Force it red before trusting a green. `tests/test_artifact_gate.py` is built
that way: every gate has a case that constructs input which must trip it, and
a clean case proving it does not fire on good input. A gate with only a clean
case certifies nothing.

When adding one, add both halves, and check that the red arrives through the
assertion you meant rather than through a broken fixture — a `SyntaxError` and
a caught defect look identical in a pass/fail column.
