# Shared PR title/body procedure

Used by review and closeout after [preflight.md](preflight.md). Reuse current
scan evidence if the head, title, and body are unchanged; rerun affected checks
after a correction. Fetch the body directly through the forge CLI;
`pr-query.sh view` has no body field.

## Title accuracy and authorization

Derive the title from the current PR diff and verified target/head from preflight.
Use `git log --format='%s' "$merge_base..$head_sha"` as supporting context.
The title must describe the final change, not merely the most common commit prefix.

For PRs older than seven days, change the title only with explicit user
authorization for that change. Existing authorization in this conversation
counts; do not ask again. Otherwise prepare the exact proposed title before
requesting confirmation. Other-review stays report-only unless the user has
explicitly authorized a particular write.

## Internal-ref leak scan

Scan both the title/body and added diff lines: process notes can leak through
PR descriptions or code comments independently.

- Title + body: `<skill-dir>/bin/leak-scan.sh --label body`.
- Added diff lines: `<skill-dir>/bin/leak-scan.sh --label diff`.

The scanner owns the token list. Its exits are 0 clean, 1 leaks found, and
2 usage/refusal. Capture fetch and scanner statuses separately; empty input
or a failed fetch is not a clean result. When the actual diff has no added
lines, record that scan as not applicable with the verified diff as evidence.

If the PR changes `skills/**` or skill docs: allow relevant skill command names
when inspecting results; still purge worklog paths, `next_action`, and process
narration. This exception requires judgment of the actual diff, not a second
regex or an assumption that all scanner hits are harmless.

## Body coherence and corrections

For self-check, fix authorized title/body issues in place. In other-review,
report findings. Remove leaked process notes from code comments only when
appropriate; preserve durable explanations of why the code works that way.

The opening paragraph must cover the complete final change and its purpose.
Keep technical framing for engineering work. After amendments, recheck scope
claims, test counts, timings, and absolutes against current evidence; correct
the body rather than appending a contradictory trailing comment.

For a PR with multiple streams, organize the description around the delivered
result and reviewer importance. Remove chronological `Also:` sections. If the
streams cannot be explained together and were not requested together, propose
splitting the PR rather than obscuring the scope.
