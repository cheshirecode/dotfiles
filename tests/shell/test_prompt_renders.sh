#!/usr/bin/env bash
# Every command substitution in a PS1 must render with no stderr and a
# non-empty result.
#
# Reported 2026-09-16: .zshrc and .bashrc built PS1 from /bin/sed and /bin/grep,
# which do not exist on macOS (they live in /usr/bin). Every prompt render
# emitted "no such file or directory" three times and the prompt's own fields
# came out empty - measured " files, b" instead of "14 files, 344b". It was
# latent rather than new: ~/.zshrc had been a dangling link, so no prompt was
# rendered at all until the link was repaired.
#
# The substitutions are EXTRACTED from the shell files rather than restated
# here. A fixture holding its own copy of the pipeline would pass while the
# committed one was broken, which is this repo's recurring defect shape.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prompt-render.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# A directory with known contents, so an empty result means a broken pipeline
# rather than an empty directory.
mkdir -p "$TMP/work"
printf 'a\n' > "$TMP/work/one.txt"
printf 'bb\n' > "$TMP/work/two.txt"

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

for rc in .zshrc .bashrc .bash_profile; do
  [ -f "$REPO/$rc" ] || continue
  # Pull each $( ... ) body out of the PS1 assignment line.
  mapfile -t subs < <(
    grep -h '^\s*\(export \)\?PS1=' "$REPO/$rc" |
      grep -oE '\$\([^()]*\)' | sed -E 's/^\$\(//; s/\)$//'
  )
  [ "${#subs[@]}" -gt 0 ] || continue
  for body in "${subs[@]}"; do
    # Skip a substitution that calls a function defined in the same rc file
    # (parse_git_branch, for example). It cannot resolve outside that shell, and
    # reporting it would be a fixture artefact, not a defect. Only external
    # commands are checkable here.
    first="${body%% *}"
    if grep -qE "^\s*(function +)?${first} *\(\)" "$REPO/$rc"; then
      continue
    fi
    err="$TMP/err"; out="$TMP/out"
    ( cd "$TMP/work" && eval "$body" ) >"$out" 2>"$err"
    if [ -s "$err" ]; then
      note "$rc: PS1 substitution wrote to stderr: $(head -1 "$err")"
      echo "       body: $body"
    fi
    if [ ! -s "$out" ]; then
      note "$rc: PS1 substitution produced nothing"
      echo "       body: $body"
    fi
  done
done

if [ "$fails" -ne 0 ]; then
  exit 1
fi
echo "ok: every PS1 substitution renders cleanly with a non-empty result"
