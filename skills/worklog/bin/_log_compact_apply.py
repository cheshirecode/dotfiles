#!/usr/bin/env python3
"""Generate a `git rebase -i` todo + per-anchor message files from the sidecar.

Reads the sidecar TSV (old_sha → first_sha → new_subject) emitted by
bin/_log_compact.py and the chronological commit list from `git rev-list`,
and writes:

  - A rebase todo file with `pick` / `fixup` / `reword` lines.
  - A directory of per-anchor message files (`msg-NNN.txt`), one per `reword`
    entry, in the order rebase will encounter them.
  - A counter file initialized to 0, used by the GIT_EDITOR shim during the
    rebase to pick the next message file.

This is the apply-side companion to _log_compact.py (which does burst detection
and emits the dry-run plan + sidecar). Kept as separate scripts because dry-run
must work without any modification to the repo state.
"""

import pathlib
import subprocess
import sys


def main() -> int:
  if len(sys.argv) != 4:
    print("usage: _log_compact_apply.py <sidecar.tsv> <todo-out> <msgs-dir>", file=sys.stderr)
    return 2
  sidecar = pathlib.Path(sys.argv[1])
  todo_path = pathlib.Path(sys.argv[2])
  msgs_dir = pathlib.Path(sys.argv[3])

  if not sidecar.exists() or sidecar.stat().st_size == 0:
    print("apply: sidecar empty; nothing to compact", file=sys.stderr)
    return 1

  # Parse sidecar: old_sha -> (first_sha, new_subject)
  mapping: dict[str, str] = {}        # old_sha -> first_sha (anchor)
  new_subjects: dict[str, str] = {}   # first_sha -> new_subject
  members: dict[str, list[str]] = {}  # first_sha -> [member_old_shas in chronological order]

  for line in sidecar.read_text().splitlines():
    parts = line.split("\t")
    if len(parts) != 3:
      continue
    old_sha, first_sha, new_subj = parts
    mapping[old_sha] = first_sha
    new_subjects[first_sha] = new_subj
    members.setdefault(first_sha, []).append(old_sha)

  # Walk every commit on main in chronological order; build the todo.
  rev_list = subprocess.check_output(
    ["git", "rev-list", "--reverse", "HEAD"], text=True
  ).splitlines()

  todo_lines: list[str] = []
  anchor_order: list[str] = []  # anchors in the order rebase encounters them
  for sha in rev_list:
    if sha in mapping:
      first = mapping[sha]
      if sha == first:
        # Anchor: rebase will pause to reword. Track ordering for the editor shim.
        todo_lines.append(f"reword {sha}")
        anchor_order.append(first)
      else:
        # Non-anchor burst member: fixup silently merges into the previous pick/reword.
        todo_lines.append(f"fixup  {sha}")
    else:
      todo_lines.append(f"pick   {sha}")

  todo_path.write_text("\n".join(todo_lines) + "\n")

  # Per-anchor message files, in the exact order rebase will reword them.
  msgs_dir.mkdir(parents=True, exist_ok=True)
  # Clean any stale files from prior runs in the same dir.
  for old in msgs_dir.glob("msg-*.txt"):
    old.unlink()
  for idx, first_sha in enumerate(anchor_order):
    member_shas = members[first_sha]
    new_subj = new_subjects[first_sha]
    body_lines = [
      new_subj,
      "",
      f"Compacted {len(member_shas)} original checkpoints into one. Iteration",
      "history below is the chronological list of original SHAs that were squashed.",
      "",
    ]
    # Pull the original `next: ...` line from each member's body, if any.
    for m in member_shas:
      try:
        body = subprocess.check_output(
          ["git", "log", "-1", "--format=%b", m], text=True
        ).strip()
      except subprocess.CalledProcessError:
        body = ""
      next_line = ""
      for ln in body.splitlines():
        if ln.startswith("next: "):
          next_line = ln[len("next: "):].strip()
          break
      iso = subprocess.check_output(
        ["git", "log", "-1", "--format=%aI", m], text=True
      ).strip()[:16].replace("T", " ")
      if next_line:
        body_lines.append(f"- {m[:12]}  {iso}  {next_line[:100]}")
      else:
        body_lines.append(f"- {m[:12]}  {iso}")
    body_lines.append("")
    body_lines.append(
      "Compaction performed by bin/log-compact.sh on the date in the commit timestamp."
    )
    msg_file = msgs_dir / f"msg-{idx:04d}.txt"
    msg_file.write_text("\n".join(body_lines) + "\n")

  # Reset the counter file used by the editor shim.
  (msgs_dir / "counter").write_text("0\n")

  print(f"apply: todo={todo_path} ({len(todo_lines)} lines)")
  print(f"apply: msgs={msgs_dir} ({len(anchor_order)} reword entries)")
  return 0


if __name__ == "__main__":
  sys.exit(main())
