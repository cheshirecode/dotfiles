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

## Sourcing a claim: one rejected gate and one built

The failure that keeps landing is a claim that was **true when written** and
quietly became false. No internal-consistency check can see it.

**Rejected.** The first proposal was to flag any number in the prose that does
not also appear in a query or computation shown in the document. Measured on
one document of 123 numeric tokens which was unusually well sourced, the naive
rule flagged 67% and a fair refinement excluding identifiers and tables still
flagged 43%. The survivors were mostly not errors: a line range from a
`file.py:49,56` citation, a merge-request number, a documented `5.00` minimum,
a `1.7` that is "1.7 days".

The reason is this file's own subject. "Appears in a shown query" is a proxy for
"is sourced", and real documents source figures by a *link* to a dashboard or
warehouse, or by a table — not by an inline query. The check answers a nearby
question. A gate that fires on 43% of a good page gets ignored, and an ignored
gate is worse than none.

**Built: `check_evidence.py`.** Narrowing the same idea to numbers inside
`strong` — the emphasised claims, not every digit — measured **3%** on the same
document (2 of 56 emphasised claims). That is a different kind of number: low
enough that a person reads the output.

The flag rate is not the best argument for it. On its first run it caught two
real defects, and their cause is the point: both claims had been fine while the
document was read top to bottom, because the reader met the SQL panel and the
dashboard breakdown *before* the claims. Then a table of contents was added and
**every section became an entry point**, so the evidence was no longer on the
path. The claim did not change and the evidence did not move; the navigation
changed underneath them. Nothing else in this skill looks at reachability, and
a table of contents is a normal thing to add.

Both rates are one document measured by one session, not general rates.

Two definitions the gate needs, and one limitation worth stating rather than
discovering:

- **"Evidence in this section"** means an evidence block, a SQL panel, a forge
  blob link, or a configured dashboard or warehouse host.
- **A same-page anchor to a section that itself has evidence counts.** That
  clause is what makes a cross-reference a fix rather than a dodge. Cycles are
  guarded, so two sections pointing at each other cannot invent evidence
  neither of them has.
- **Scoped to `strong`**, a proxy for author-marked weight. It will miss an
  unemphasised figure. That is the trade which buys the 3%.
- **A standalone number, not any digit.** `\d` also matches a date, a ticket
  id, a version and a unit — `2026-09-17`, `SPLUS-19835`, `v3_3_0`, `5xx`,
  `3s` — none of which is a measurement and all of which are ordinary here.
  The matcher is
  `(?<![\w.#-])\d[\d,]*(?:\.\d+)?(?![\w%-]*[\w])`.
  **The 3% belongs to this matcher**: on the same page, any-digit matching
  yields 71 emphasised spans instead of 56, and all 15 extra ones are false
  positives. The first implementation shipped with `\d` and therefore measured
  a different rule than the one that was costed — the rate did not transfer.
  That is this file's own subject turned on the file itself: quantify the rule
  you are actually going to run.

With no `section` elements the gate fails closed rather than passing a document
it had no scope to judge, and says what to do about it.

## A second measurement, and the hole it exposed

A second session measured the gate on four published artifacts it had never
seen, importing the gate's own section, emphasis and number matchers so the
counting was like for like.

**It is not corroboration of the 3%, and was briefly recorded here as though it
were.** The first figure reported, 4%, put the tuning document in the
denominator: that one page contributed 56 of the 72 emphasised spans and none
of the fires, so it diluted the rate rather than testing it. On the four pages
the gate had never seen the figure is **3 of 16, or 19%** — same numerator,
honest denominator.

The two rates measure different populations and must not be reported as
agreeing: 56 spans on a page the rule was tuned against, versus 16 untuned ones.
Sixteen spans cannot settle a 3% claim in either direction, and only one of the
three fires was adjudicated, so 19% is an upper bound on a small sample rather
than a measurement. Both published rates are single-corpus.

The finding was not the rate. They also measured **coverage**, and unmodified
the gate inspected **1 of 72** emphasised numeric claims across those pages and
reported clean. Two of the four mark weight with `b` rather than `strong` —
hand-written HTML rather than Markdown output — so the gate saw nothing and
passed. That is the failure named at the top of this file, produced by the
gate's own scope: a page with sections and zero matched spans was
indistinguishable from a well-sourced one, and both printed OK.

Three consequences, all now implemented:

- **`b` counts as emphasis.** The stated scope is author-marked weight, and a
  hand-authored `b` meets it. The split was authoring provenance, not intent.
- **Coverage is reported on every run**, as a note and never a refusal. Zero
  emphasised spans is a legitimate state for a prose page, or one whose numbers
  live in tables; refusing there produces a finding the author cannot act on,
  which is how a gate teaches people to bypass it and then gates nothing. The
  report degrades quietly on a prose page and is unmissable on a page where it
  inspected one claim in seventy-two. It also survives the next scope change
  without anyone predicting where the gap will be.
- **A finding locates the section.** A missing id used to surface as
  `__unnamed_2`, which points at nothing; it now gives the position and names
  the remedy, because on a page with no ids the cross-reference fix is
  unavailable and the only alternative is duplicating evidence — the outcome
  the anchor rule exists to prevent.

If a blocking form is ever wanted, the defensible predicate is not "zero spans"
but **zero emphasised spans AND standalone numbers present outside emphasis** —
the state where the page plainly makes numeric claims and the gate saw none of
them. That predicate is unmeasured; it is recorded as a suggestion, not a
result.

## Conditions the rates depend on

- **`--evidence-host` is load-bearing.** On that corpus, unconfigured hosts
  gave 4 fires and configured gave 3; the one that disappeared cited a
  dashboard. A run without hosts configured over-reports on any page citing
  dashboards rather than code. **The measured rate assumes hosts configured for
  the corpus.**
- **19% is an upper bound on a small sample, not a measurement.** Of the three
  fires, one was adjudicated and is genuine — a figure derived in one section
  and restated bare in another with no anchor, the carry-over shape in a new
  document. The other two were not adjudicated.
- **Check what is in the denominator before quoting a rate.** The 4% that first
  appeared here was arithmetically correct and still wrong, because it counted
  the document the rule was tuned on as part of the corpus that was supposed to
  test it. It was found by re-running, not by re-reading the report that
  produced it.

## What the coverage line did on first contact

Re-run after the fix, the four pages gave:

| page | sections | inspected | not inspected | result |
| --- | ---: | ---: | ---: | --- |
| Plaid Limits | 4 | 14 | 27 | 1 finding |
| Async DDA Monitor Readiness | 6 | 0 | 10 | OK |
| Decline Reason Boundary | 6 | 1 | 18 | 1 finding |
| Super+ ACH Precheck | 4 | 1 | 15 | 1 finding |

Row one is the scope fix: 0 inspected became 14. Row two is the case the
report-versus-refuse argument was about — it returns OK having inspected
nothing, and now says so on the same line. Not blocked, because there is
genuinely nothing to judge; no longer indistinguishable from a page that
passed. Zero inspected against ten standalone numbers present is the ratio that
makes it legible, and it required no prediction about which convention was
missing.

## Validating a gate

Force it red before trusting a green. `tests/test_artifact_gate.py` is built
that way: every gate has a case that constructs input which must trip it, and
a clean case proving it does not fire on good input. A gate with only a clean
case certifies nothing.

When adding one, add both halves, and check that the red arrives through the
assertion you meant rather than through a broken fixture — a `SyntaxError` and
a caught defect look identical in a pass/fail column.

**Read the gate's exit code, not a pipeline's.** `check_evidence.py page.html |
head -12; echo $?` prints `head`'s status, which is 0 on a run that exited 1.
Anyone verifying a fix the obvious way will conclude the gate still fails open.
Redirect to a file and check `$?`, or capture with `$(...)` and test that. This
is the single most repeated mistake in this skill's own history: it has produced
a "suite passed" claim from a failing suite, a "test passed" from an exit-2
test, and a "still broken" from a working gate.

**Exit 0 does not mean the page was checked.** It cannot distinguish "inspected
the claims and they are fine" from "inspected nothing". That is what the
coverage line is for, and it is why the coverage line is read first and the exit
code second.

## State the rule separately from the code that implements it

Passing tests do not show that a gate implements the rule. They show that the
code matches **the implementer's reading** of the rule, because the same person
usually writes both — so a misreading is inherited by the tests that were
supposed to catch it, and green means agreement with the misreading.

Two gates in this skill shipped wrong while every test passed. One collapsed
"unverifiable here" into "unrecognised", so a legitimate merge-request citation
became a hard failure. The other matched any digit rather than a standalone
number, so dates and ticket ids counted as measurements — and because the flag
rate that justified it had been measured with a different matcher, the
documentation quoted a cost for a check nobody had run.

The antidote is a rule stated **independently of the implementation**, as
input-and-expected-output rather than prose: the list of tokens that must count
and the list that must not, written down before or apart from the code, and
best supplied by someone who did not write it. When a number is quoted as
justification, publish the instrument that produced it — a rate without its
matcher does not transfer, and the next person will implement a different rule
and inherit the old number.

The cheap check that closes it: run the rule on a known input and see whether
the count matches the claim. Here the span count went 56 before the gate was
built, 71 with the wrong matcher, and 56 again once it was fixed. That equality
is what finally showed the two rules were the same rule.
