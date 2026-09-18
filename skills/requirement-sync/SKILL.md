---
name: requirement-sync
description: Propagate a changed requirement across every place it is written down, and find where the old version still reads as current. Use when a decision changes in chat, a review, or a meeting and the written record now disagrees with itself; or when asked to sync, reconcile, or update records after a requirement change.
---

# requirement-sync

A requirement changes in one place and stays true in three others. The cost is
not the edit, it is the search: finding which records still assert the old
version, when none of them look wrong on their face.

This skill does the finding. It does not decide what is true.

## When to use

- A decision lands and some written record now contradicts it.
- A tracked item closes and its premise was carried into other documents.
- Before a sign-off, to check the evidence under it has not moved.

Do not use it to make the decision. It surfaces disagreement; a human resolves it.

## Initialise: scan, ask, declare

The skill assumes no particular tracker, document store or publishing tool.
Before the first run, work out what exists here — in that order, because a scan
sees structure and cannot see intent.

**Scan.** `scripts/discover_surfaces.py [root ...]` walks read-only, writes
nothing and makes no network call. It reports each kind of surface in one of
four states, never collapsed: `found` with the evidence named, `absent`,
`unknown`, or `n/a`. `--json` emits the same as a declarations skeleton.

**Pass every root, not just the repository.** A project's notes, ledger and
memory store routinely live in another checkout or off-disk entirely, and the
tracker always does. `absent` means *not under the roots you scanned* — it is
never evidence that a surface does not exist, which is why every absent row
still prints the question asking where else to look.

Three things it deliberately will not do:

- **It will not claim `absent` from a partial look.** If inspection stops early
  the state degrades to `unknown`. An absence claim from a sample is not a
  measurement: an earlier version read 4,000 of 109,475 files on a real tree,
  3.7%, and reported two surfaces absent off that.

- **It never reports a tracker as `found`.** A forge is where the code lives,
  not evidence of where work is tracked — plenty of projects keep code in one
  place and issues in another. It names the host and asks.
- **It separates test data and templates from live surfaces without hiding
  them.** A fixture looks exactly like the surface it stands in for; running
  this against the repository that ships it reported its own worklog fixtures
  as live working notes. Those matches are counted and named, not filtered,
  because a filter would also hide a real surface that happens to sit under one
  of those directory names.

**Ask.** Every `unknown` prints the question to put to the operator. Answer
those before declaring anything; a guess here is the one error the rest of the
procedure cannot detect, because every later step trusts the declarations.

**What the scan is and is not.** Discovery is one of six steps and the only
scripted one; the rest is procedure followed by hand. So it gives a surface
inventory and a checklist — it does not detect drift on its own, and `found` is
not a completed inventory. A page published straight from a scratch directory,
or a store that sits outside every plausible root, is visible only if someone
names it. That is what the declarations are for.

**Run it when a fact changes** — a tracked item closes, a change merges, a
decision reverses — and not on a schedule. On a schedule it becomes another
clean-looking pass that measures nothing, and a pass that always looks the same
is one nobody reads.

**Declare.** For each surface: **what it is**, **how to search it**, **how to
read one item**, and **how to write to it**. For a tracker, two more:

- **How to tell a closed item's reason for closing from its state** — see step 3
  for why that is separate.
- **What this credential can actually see.** The tracker and your visibility
  into it are two different facts, and a scan sees neither. One real setup files
  the same incidents across two projects where the account can read one and not
  the other. Declare the scope you can search, because a search that returns
  nothing for lack of permission looks exactly like a search that returns
  nothing because there is nothing there.

Keep the declarations in one file the procedure can read. If a surface cannot
answer one of those questions, record that; a missing capability changes the
procedure rather than invalidating it.

## How records go stale

Not configuration. This is the part worth knowing, and it transfers across
tools. A surface's *kind* predicts how it rots:

| kind of surface | how it goes stale |
|---|---|
| tracked item | closed on a premise that later changed |
| working note | its next-action field carries a superseded plan |
| published page | a card states what was true at publish time |
| durable memory | a rule rests on a fact that has since moved |
| code comment | it defends a property that nothing tests |

The last one is the least obvious and the most expensive: a comment asserting an
invariant is evidence that someone knew it mattered and did not encode it.

## Procedure

1. **State the change in one sentence**, with its source. "Service B will now
   emit under a second account identifier, per the decision recorded in <link>."
   If it cannot be said in one sentence it is more than one change.

2. **Find the old version before writing the new one.** Search each declared
   surface for the claim the change falsifies, not for the topic. Topic search
   finds everything; claim search finds what is now wrong.

3. **Check whether the work is already tracked, including in closed items.**
   This is the step most often skipped and the one that most often makes the rest
   unnecessary. Search titles and bodies, and read the closed results.

   A closed item is not a finished one. **Why it closed is a different fact from
   that it closed**, held in a different field on every tracker and on some not
   held at all. An item closed as a duplicate points at a live sibling that
   carries the requirement; an item closed as not-planned does not. If the
   declared surface cannot report a reason, step 3 degrades to reading every
   closed match, which is slower and still cheaper than filing a duplicate.

   The same applies to reach. A clean result from a scope you cannot see is not
   a clean result — it is no result, wearing the same face. If the declared
   visibility does not cover where this kind of work is filed, say so in the
   finding rather than reporting nothing found.

4. **Classify each hit before editing**: FALSIFIED (rewrite), NARROWED (qualify),
   UNAFFECTED (leave). Most hits are the third. Editing them is how a sync turns
   into a rewrite.

5. **Write the new version once, in the surface that owns it**, and point the
   others at it. A fact restated in four places drifts in four directions.

6. **Verify the destination.** A record is written when the destination shows it.
   Read it back; a success code from the write is not evidence. This is the same
   rule as "existing is not reachable" in the artifact-gate skill's gates.md:
   `git cat-file` answers for an object no branch contains, and a 200 answers for
   a comment that is not there. Both read the near end of the operation and infer
   the far end, which is what was actually claimed.

## Anti-goals

- Do not create a tracked item before step 3. Two of the last three "untracked"
  gaps already had items, one of them closed-as-duplicate pointing at the live
  one, and one done and assigned to the person reporting the gap.
- Do not narrate the change history in the records. They state what is true now;
  how it got there belongs in the commit message.
- Do not sweep unaffected surfaces for consistency of style.

## Verification

Put volatile facts in a machine-checkable file with a verifier that prints only
mismatches, so a lookup costs one command instead of re-reading prose.

The rules that verifier has to satisfy are not restated here. They are in the
artifact-gate skill's `references/gates.md`, which already encodes them: never
read the working tree; force the check red before trusting a green, because one
with only a clean case certifies nothing; read the checker's own exit code and
not a pipeline's; and treat a success code as saying nothing about whether
anything was inspected. Read that, then build to it.

Restating them here would put the same doctrine in two files, which step 5
forbids.
