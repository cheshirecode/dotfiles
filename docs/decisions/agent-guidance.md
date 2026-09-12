# Agent guidance and documentation

Status: accepted.

## Context

The repository supports several agent hosts. Shared engineering guidance must
remain reusable while setup details and tool capabilities vary by host. Large
instruction files and duplicated procedures increase context cost and can drift.

## Decision

Keep shared engineering guidance at the repository root, host-specific setup in
its setup guide, and workflow/tool references in supporting documentation. Mark
framework examples as examples rather than universal requirements. Preserve
existing host configuration ownership.

Keep skill entry points short and their activation boundaries precise. Move detail
to references when only some invocations need it; avoid splitting a linear workflow
into files that every invocation must load. Each shared rule has one owner, with
callers linking to it. Source word counts measure document size, not runtime token
savings.

Use repository documents for maintained designs, architectural decisions, usage
guidance, and executable/manual test specifications. Store dated audit results,
completed migration checklists, research snapshots, and handovers in Worklog.
Git history retains removed reports; do not keep stale operational evidence as
current instructions. When a historical report contains a still-relevant decision,
retain that decision and its rationale without the execution log.

## Consequences

Instruction changes require realistic routing and ownership checks, not tests
that pin exact prose. Runtime changes retain behavioral fixtures. Installation
checks use isolated destinations when existing symlinks belong to another
worktree; a dry-run refusal is not permission to replace them.

General guides remain available to users and agents; historical task narratives
do not accumulate alongside them.
