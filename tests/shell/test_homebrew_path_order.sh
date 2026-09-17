#!/usr/bin/env bash
# .shell_common must put a real homebrew prefix AHEAD of /usr/bin.
#
# macOS path_helper reads /etc/paths before /etc/paths.d, so the homebrew
# entry lands after /usr/bin and /usr/bin wins. Measured 2026-09-17: every
# shell on this host resolved python3 to /usr/bin/python3 3.9.6 while
# /opt/homebrew/bin/python3 was 3.14.6 and installed. bin/doctor.sh reported
# FAIL on python>=3.10 and unittest's enterContext (3.11+) raised
# AttributeError in the browser-use fixtures, both from that one ordering.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# Which state is this host in? Reported, never inferred: a vacuous pass on a
# machine with no homebrew reads exactly like a verified one.
brew_prefix=""
for p in /opt/homebrew /usr/local; do
  if [ -x "$p/bin/brew" ]; then brew_prefix="$p"; break; fi
done

# Source .shell_common from a PATH that reproduces the defect: /usr/bin first,
# the brew prefix last. If the block works, the order is inverted afterwards.
probe() {
  env -i HOME="$HOME" DOTFILES_QUIET=1 \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin${brew_prefix:+:$brew_prefix/bin}" \
      bash -c '. "$1" >/dev/null 2>&1; printf "%s" "$PATH"' _ "$REPO/.shell_common"
}

path_after="$(probe)"
if [ -z "$path_after" ]; then
  note "sourcing .shell_common produced an empty PATH"
  exit 1
fi

pos() { # pos <dir> -> 1-based index in $path_after, or empty
  printf '%s' "$path_after" | tr ':' '\n' | grep -nxF "$1" | head -1 | cut -d: -f1
}

if [ -n "$brew_prefix" ]; then
  echo "state: homebrew present at $brew_prefix"
  brew_pos="$(pos "$brew_prefix/bin")"
  usr_pos="$(pos /usr/bin)"
  if [ -z "$brew_pos" ]; then
    note "$brew_prefix/bin is absent from PATH after sourcing .shell_common"
  elif [ -z "$usr_pos" ]; then
    note "/usr/bin is absent from PATH after sourcing .shell_common"
  elif [ "$brew_pos" -ge "$usr_pos" ]; then
    note "$brew_prefix/bin is at position $brew_pos, /usr/bin at $usr_pos — /usr/bin still wins"
  fi

  # The outcome that actually matters, not just the ordering that causes it.
  # bin/doctor.sh requires python3 >= 3.10; assert the resolved one clears it.
  if [ -x "$brew_prefix/bin/python3" ]; then
    resolved="$(env -i HOME="$HOME" DOTFILES_QUIET=1 \
      PATH="/usr/bin:/bin:$brew_prefix/bin" \
      bash -c '. "$1" >/dev/null 2>&1; command -v python3' _ "$REPO/.shell_common")"
    [ "$resolved" = "$brew_prefix/bin/python3" ] ||
      note "python3 resolved to '$resolved', want $brew_prefix/bin/python3"
    ver="$("$brew_prefix/bin/python3" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
    major="${ver%%.*}"; minor="${ver#*.}"
    if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 10 ]; }; then
      note "homebrew python3 is $ver, below the 3.10 bin/doctor.sh requires"
    fi
  else
    echo "state: homebrew present but has no python3 — ordering asserted, version not"
  fi
else
  # No brew binary on this host. The rule is conditional, so there is nothing
  # to order -- but say so, and assert the block did not invent a path.
  echo "state: no homebrew prefix on this host; the block must be a no-op"
  for p in /opt/homebrew /usr/local; do
    if [ -n "$(pos "$p/bin")" ] && [ ! -x "$p/bin/brew" ]; then
      note "$p/bin was prepended although $p/bin/brew is not executable"
    fi
  done
fi

if [ "$fails" -ne 0 ]; then
  echo "--- PATH after sourcing:"; printf '%s\n' "$path_after" | tr ':' '\n' | head -8
  exit 1
fi
echo "ok: homebrew ordering correct for this host's state"
