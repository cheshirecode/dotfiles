---
slug: projects-root
status: in-progress
kind: project
repos: [example/projects-ui]
project: none
last_updated: 2026-06-08
next_action: "Finish projects child."
related:
  - slug: projects-child
    note: fixture edge
  - slug: projects-archive
    note: archived fixture edge
tasks:
  - slug: projects-root
    kind: project
  - slug: projects-child
    depends_on: [projects-root]
    kind: impl
---

## Context

Projects fixture root.

## Next

- [ ] Finish projects child.
