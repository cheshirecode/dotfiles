# Two upstreams: private canonical, public downstream

| Remote | Host | Visibility | Role |
|---|---|---|---|
| `origin` | GitLab | private | Canonical. `main` tracks `origin/main`; every commit lands here. |
| `github` | GitHub | public | Downstream copy. Receives only commits that pass the public gate. |

GitHub is downstream only: nothing is pulled from it. A contribution made
there is cherry-picked into `main` and reaches GitHub again on the next
publish.

## The gate

`bin/git-hooks/pre-push`, wired by `bin/install-hooks.sh --write`, decides by
destination:

- A remote with `git config remote.<name>.dotfiles-private true` takes
  anything. The setting is machine-local, so each clone marks its own private
  remote once: `git config remote.origin.dotfiles-private true`.
- Every other remote is public. Each commit it would gain must pass
  `bin/leak-guard.sh --range` (added lines and author/committer identities)
  and `gitleaks`. A missing scanner blocks the push.

A gate that is not wired blocks nothing, so `bin/doctor.sh` fails when a
public remote exists and `pre-push` is not the gate. Run it after cloning.

An unmarked remote counts as public, so a fresh clone that forgot the mark
gets a blocked GitLab push, never a leaked GitHub one.

The pre-commit hook still runs `leak-guard --staged`. A commit meant only for
GitLab passes it deliberately with `DOTFILES_NO_HOOK=1`, which also marks it,
at the moment it is made, as not publishable.

## Publishing

Push to GitLab first, then publish from `origin/main`:

```sh
bin/publish-public.sh            # dry run: classify each commit, print the plan
bin/publish-public.sh --apply    # publish
```

It lists the commits `github/main` lacks by patch-id (`git cherry`), so a
commit already published as a cherry-picked copy is not offered again. It
checks each one on its own with `leak-guard --range` and gitleaks, then:

- **While nothing private has landed:** it fast-forwards `github/main`
  through the leading run of clean commits. The hashes stay identical, so
  the histories do not diverge.
- **Once a private commit lands:** that commit stays on GitLab, and every
  later clean commit is cherry-picked onto `github/main` in a scratch
  worktree. From then on the two histories differ by design, and `main` is
  never pushed to `github` directly again.
- **A clean commit that builds on a private one** cannot apply. The run
  stops, names it, and pushes nothing.

The push goes through the pre-push gate, which scans every commit again.

A commit that mixes public and private hunks cannot be published as it
stands, and `main` on GitLab is never rewritten to split it. Keep the private
part in its own commit when you make it: one concern per commit is what keeps
a commit publishable.
