# Derived views

The rest of this skill runs one direction: a fact changes, and you find the
records still asserting the old one. A derived view runs the other way. Many
sources change on their own schedules and one page has to follow all of them.

Same problem — a record disagreeing with the world — approached from the end
that has more inputs than editors.

## What makes it different

A surface is written by people. A derived view is written by a script and read
by people, and that inverts which mistakes are cheap.

| | surface | derived view |
|---|---|---|
| goes stale when | someone forgets to edit it | a source moves and nothing re-reads it |
| the risk | the old version still reads as current | a sync overwrites something no source owns |
| detection | search for the superseded claim | recompute the claim and compare |

The second row is the one that costs work. A surface edit that loses a sentence
is visible in review. A sync that imports a tracker's status over a human's
judgement looks like a successful run.

## Declare the view

Everything in **Initialise: declare** applies per source: what it is, how to
search it, how to read one item, and what your credential can actually see. A
view adds three questions the single-surface case never asks.

**Which fields does this source own?** Ownership is exclusive and written down
before the first sync. One source owns a field; every other source and every
sync script treats it as read-only. A field no source owns is hand-written and
no sync may touch it.

**Where does its snapshot live, and when was it read?** A view assembled from
live reads cannot be reproduced or reviewed. Each source lands in a file under
version control carrying the timestamp of the read that produced it. The view is
built from those files, never from the network.

**What is the freshness bound?** A snapshot has an age, and the view should say
it. "Read four days ago" is a fact a reader can weigh; silence is not.

Keep this in a manifest beside the declarations — one entry per source, listing
kind, read command, snapshot path, owned fields, and read timestamp.

## The manifest is the extension point

Adding a source means adding a manifest entry and one script. It must not mean
editing a script that already works.

- **One sync script per source.** It writes only the fields its source owns, and
  asserts every other field is byte-identical afterwards. That assertion is what
  makes the ownership rule enforceable rather than aspirational.
- **Scripts do not know about each other.** Two sources feeding related fields
  still get two scripts. A combined script has to be edited whenever either
  source changes, which is the closed-for-extension shape this avoids.
- **The renderer reads the data, not the sources.** It takes the assembled data
  file and emits the page. A renderer that reaches back to a source is a second
  sync with no manifest entry.

A new source therefore touches: one manifest entry, one new script, zero
existing scripts. If adding one forces an edit elsewhere, the boundary is in the
wrong place.

## Order: sync, verify, publish, commit

**Sync** each source in turn. A sync script reports drift on fields it does not
own and never resolves it. Importing a workflow status over editorial state once
traded eight facts for one, and the run reported success.

**Verify** with a separate program that recomputes every headline number from
the raw sources using its own logic. It must not import the sync code: a
verifier sharing the sync's parser inherits the sync's blind spot and confirms
it. Print only mismatches, exit non-zero on any.

**Force it red before trusting green.** Tamper one input, confirm the verifier
fails, and read the verifier's own exit code — not a pipeline's, because `cmd |
tee` reports the status of `tee`.

**Publish**, then **commit the source data in the same turn.** A published page
whose data is not committed cannot be reproduced, and the next sync starts from
a baseline nobody can see.

## How a derived view goes stale

The kind of failure follows the shape of the read, the same way a surface's kind
predicts how it rots.

| shape of the read | how it fails |
|---|---|
| reads one region of a document | a fact below the region stays stale while the check reports clean |
| filters on a key's format | a key that appears twice in one row, or is wrapped in a link, is skipped |
| assumes a field exists | the result lives in prose or a child page, so the count is zero and looks real |
| resolves conflicts by recency | a later, weaker observation overwrites an earlier stronger one |
| counts what it matched | an item outside the declared scope is counted in the scope's total |
| trusts a read-only flag | the flag is accepted and ignored, and the run advances a baseline |
| reads "unset" from a store | absence is indistinguishable from no permission to look |
| states a count in prose | the prose ages while the data moves |

Two of these deserve the rule rather than the example:

**Recency is not strength.** "Later wins" needs "unless it carries less
evidence". A partial observation that merely resembles the case is never a pass,
however recent.

**Absence needs a positive control.** Before recording "not set", read a key you
know is set, through the same command and credential. Without that, a
permissions failure and a genuine absence are the same output — which is the
four-state rule from **Initialise** applied to a data source.

## Rendering

`artifact-gate` owns the published-page checks: tag balance, dead anchors,
duplicate ids, and self-claims that have drifted from the data. Run it before
publishing and do not restate its rules here.

Two things belong to the view rather than the gate:

- **Generate the page from the data; never hand-edit it.** The page is output.
  The data file under version control is the source of truth, and an edit made
  in the page is lost at the next render without ever being wrong on its face.
- **Refuse to write on unbalanced tags, matching the tag NAME.** `<p` also
  matches `<pre`, `<li` also matches `<link`. A prefix match reports balance
  that is not there.

## Scheduling

Run a sync when its source changes — an item closes, a run completes, a flag
flips. Not on a timer. A timed sync becomes another clean-looking pass that
measures nothing, which is the same argument **Initialise** makes for discovery.

## Keeping the worked example out of here

A real view is specific: it names a tracker, a document store, a flag service.
That belongs with the view, not in this skill.

Keep the example next to the view's own data — the manifest, the sync scripts,
the verifier, and a README giving the reason for each rule in terms of what went
wrong. The skill carries the shape; the example carries the evidence. A path
into one machine's checkout is a dead link for everyone else, and a reader who
cannot open it cannot check the claim it supports.
