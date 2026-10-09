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

List what GitHub lacks, then scan each commit on its own:

```sh
git fetch origin && git fetch github
for c in $(git rev-list --reverse github/main..origin/main); do
  bin/leak-guard.sh --range "$c^..$c" >/dev/null 2>&1 && s=clean || s=PRIVATE
  echo "$s $(git log -1 --format='%h %s' "$c")"
done
```

- **All clean:** `git push github main`. The hook scans the range again.
- **The clean commits form a prefix:** publish up to the last clean one with
  `git push github <sha>:refs/heads/main`.
- **A private commit sits between clean ones:** from here the two histories
  diverge. Keep a `public` branch on top of `github/main`, cherry-pick the
  clean commits onto it, and push `public:main`. `git cherry -v public main`
  matches commits by patch-id, so it keeps listing exactly the commits not
  yet published even after their hashes differ.

A commit that mixes public and private hunks cannot be published as it
stands, and `main` on GitLab is never rewritten to split it. Keep the private
part in its own commit when you make it: one concern per commit is what keeps
a commit publishable.
