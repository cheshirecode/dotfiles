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

## A generated status summary

The headline of a status page, meaning the verdict, the state of each step and
what needs attention, is the part most often typed in by hand and the part
that goes stale fastest. Generate it like every other field.

- **Split the spec from the output.** The data file holds two keys. The spec
  holds only stable wording: step names, attention items and their phrasing,
  the time windows to measure. The summary holds everything a source can
  answer: counts, tracker statuses, review states, alert states. A script
  writes the summary, and nobody edits it. That is the field-ownership rule
  applied inside one file. Change the spec to change what is measured.
- **Fail closed, per line.** A source that errors renders **Unknown** in the
  stop tone, and the run exits non-zero. It never keeps the previous value: an
  old number under a fresh timestamp is the most convincing wrong answer the
  page can show. An API that caps its result, such as an aggregate with a
  bucket limit, goes Unknown at the cap rather than reporting the capped count.
- **Break the credential the source actually checks.** A red test that swaps
  in a bad key can pass for the wrong reason. Measured on one metrics API: with
  a valid application key, a bad API key was accepted, so only a bad
  application key proved the failure path. Likewise, a secrets-file line that is
  a shell reference (`${VAR:-}`) expands to empty in a tool shell. Test every
  credential for non-empty, and name the fallback when one is used.
- **Commit on change, not on run.** Print a signature, a hash over states,
  tones and statuses but not counts or the timestamp, and whether it
  `changed`. A frequent republish refreshes the numbers, and the data file is
  committed only when a state moved, so history records transitions instead
  of one commit per hour.
- **Shrink what cannot be automated rather than typing it.** A fact with no
  readable source in this environment leaves the summary. An item with no
  tracker shows `No tracker` as its status, never an invented one. The page
  says the summary is generated, and when.

Rendering it:

- **Opt in.** Render the block only when the data carries a summary, so other
  pages built by the same renderer stay byte-identical. Check that with `cmp`,
  not by eye.
- **Namespace new styles.** A shared stylesheet already owns generic class
  names, such as a node or a state. Prefix the new ones, or they silently
  restyle the existing page.
- **Show state three ways:** text, colour and shape together, for example
  filled for ok, a ring for waiting, a square for a gap. Colour alone fails
  some readers and every greyscale print.
- **Use an ordered list only when the order is real**, such as the sequence a
  transaction actually passes through.

## Scheduling

Run a sync when its source changes — an item closes, a run completes, a flag
flips. A timed sync becomes another clean-looking pass that measures nothing,
which is the same argument **Initialise** makes for discovery.

The exception is a source that changes continuously and emits no event, such
as live metrics. There, a schedule is the only possible trigger. It is safe
only with the two rules above: a failed read cannot pass for a quiet one,
because it fails closed, and a run that changed nothing commits nothing.

## Keeping the worked example out of here

A real view is specific: it names a tracker, a document store, a flag service.
That belongs with the view, not in this skill.

Keep the example next to the view's own data — the manifest, the sync scripts,
the verifier, and a README giving the reason for each rule in terms of what went
wrong. The skill carries the shape; the example carries the evidence. A path
into one machine's checkout is a dead link for everyone else, and a reader who
cannot open it cannot check the claim it supports.
