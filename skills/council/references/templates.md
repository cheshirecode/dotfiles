# Council: prompt templates

Read this before spawning any Stage 1, 3, 4, or 5 sub-agent. Use the stage's template verbatim.
Every sub-agent is a `task` call with `subagent_type: general-purpose`.

## Stage 1 research

```
You are research angle <angle_i> of <angle_count>. Do not Read, Grep, or Monitor outputs of other angles. Do not coordinate.

Original request: <verbatim user request>
Angle scope: <one narrow, non-overlapping angle>

Read only what is needed for this angle. Return:
1. Top findings with file/line references or source citations when possible.
2. Candidate items proposed by this angle:
   - A<angle_i>-i1: <concrete, testable item>
     - Falsifier or strongest counterexample: <observation that would defeat or materially qualify it>
     - Verification recipe: <cheapest safe check and expected discriminating result>
     - Verification evidence: <PLANNED|EXECUTED-PASS|EXECUTED-FAIL|UNAVAILABLE> — <artifact pointer or reason>
   - A<angle_i>-i2: <concrete, testable item>
     - Falsifier or strongest counterexample: <observation that would defeat or materially qualify it>
     - Verification recipe: <cheapest safe check and expected discriminating result>
     - Verification evidence: <PLANNED|EXECUTED-PASS|EXECUTED-FAIL|UNAVAILABLE> — <artifact pointer or reason>
No file edits.
```

## Stage 3 discussion

```
You are the Stage 3 discussion agent. Read all Stage 2 findings below.
Flag agreements, disagreements, gaps, and contradictions.
You may propose additional candidate items only when they are surfaced by cross-angle gaps.
For every candidate, assess its strongest counterexample from the supplied evidence. Run a cheap, safe, in-scope verification recipe only when needed; otherwise leave it unresolved rather than guessing. Never present a planned check as an executed result; preserve its evidence state and artifact pointer.
Assign a counterexample survival status to EVERY candidate, including the D-iN candidates you propose yourself. Stage 4 drops any item without one, so an unstatused D-iN item never reaches the ballot.

Output:
## Stage 3 discussion
Agreements:
Disagreements:
Gaps:
Counterexample survival status:
- A1-i1: <SURVIVES|REFUTED|UNRESOLVED MATERIAL|UNRESOLVED MINOR> — <evidence or missing check>
Additional candidate items surfaced by cross-angle gaps:
- D-i1: <concrete, testable item>
  - Falsifier or strongest counterexample: <observation>
  - Verification recipe: <check and expected result>
  - Verification evidence: <state and artifact pointer or reason>
  - Counterexample survival status: <SURVIVES|REFUTED|UNRESOLVED MATERIAL|UNRESOLVED MINOR> — <evidence or missing check>
```

## Stage 4 candidate collation

```
You are the Stage 4 collator. Gather the union of candidate items from Stage 1 angles and Stage 3 discussion.
Deduplicate near-identical items while keeping the strongest phrasing.
You may not add new items.

Output:
## Stage 4 candidate list
1. <item> [proposed-by: A1-i2, D-i1]
   - Falsifier or strongest counterexample: <preserved from upstream>
   - Verification recipe: <preserved from upstream>
   - Verification evidence: <preserved state and artifact pointer>
   - Counterexample survival status: <Stage 3 status>
2. <item> [proposed-by: A2-i3]
   - Falsifier or strongest counterexample: <preserved from upstream>
   - Verification recipe: <preserved from upstream>
   - Verification evidence: <preserved state and artifact pointer>
   - Counterexample survival status: <Stage 3 status>

Collator: 0 items invented; X items deduped.
Items without exact upstream proposer IDs, a falsifier/counterexample, a verification recipe, verification evidence state, or a Stage 3 survival status will be dropped before voting.
```

The numbers `1.`, `2.`, ... in this list are the **item positions** used everywhere downstream:
Stage 5 ballots say `item 1:`, and `validate-ballot.py --items/--unresolved` take these positions,
never the upstream `A1-i2` / `D-i1` IDs.

## Stage 5 voting

```
You are an independent Stage 5 voter. You may not see other voters' ballots.
Use only the Stage 4 candidate list, Stage 2 findings, Stage 3 discussion, the council voting criteria, and the original request.
You must not cast `APPROVE` for a candidate marked `UNRESOLVED MATERIAL`; cast `QUALIFY` with the resolving check or `REJECT` with a named criterion. `UNRESOLVED MINOR` remains eligible for normal voting.

For each item, cast exactly one ballot:
- APPROVE
- REJECT: <TRACES|SOLVES-EXTANT-PAIN|N-THRESHOLD-MET|COST-PROPORTIONATE|NON-INFRA-PADDING>[, ...], <one-sentence justification>
- QUALIFY: <condition>

Output only the heading `## Stage 5 ballots`, one `Voter <n>:` line, and one lowercase `item <k>: ...` line per item — no bullets, no preamble, no trailing prose. Any other line fails validation and burns your one retry.

Output:
## Stage 5 ballots
Voter <n>:
  item 1: APPROVE
  item 2: REJECT: SOLVES-EXTANT-PAIN, <reason>
  item 3: QUALIFY: <condition>
```

Rejected shapes, for contrast — each of these fails `validate-ballot.py`:

```
Item 1: APPROVE          # capital I
- item 1: APPROVE        # bullet
Here are my votes:       # preamble
Voter 1 (of 3):          # only `Voter <n>:` is allowed
```
