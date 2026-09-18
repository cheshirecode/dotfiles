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

## Initialise: declare the surfaces

The skill assumes no particular tracker, document store or publishing tool.
Before the first run, the operator declares what exists here and how to
interrogate each one. Everything below refers to these declarations.

For each surface: **what it is**, **how to search it**, **how to read one item**,
and **how to write to it**. For a tracker, additionally: **how to tell a closed
item's reason for closing from its state** — see step 3 for why that is separate.

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
