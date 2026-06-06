---
slug: round-trip-fixture
status: in-progress
kind: impl
repos: [_worklog, ui, website]
project: worklog-automation
linear: ENG-9999
created: 2026-04-25
last_updated: 2026-04-25
next_action: "Single-line scalar with embedded \"quotes\" and a colon: should round-trip."
parent_slug: parent-fixture-slug
supersedes: old-fixture-slug
related:
  - slug: peer-fixture-slug-a
    note: continuation field — list-of-mappings shape that broke parsers historically
  - slug: peer-fixture-slug-b
    note: second item to verify multi-entry list integrity
external_refs:
  - url: https://example.invalid/doc
    note: external pointer with note continuation
pr: [42, 43]
---

## Context

Round-trip body content. Should not change between read and write.
