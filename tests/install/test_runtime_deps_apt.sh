#!/usr/bin/env bash
# On a Coder workspace install.sh must apt-install the runtime deps bin/doctor.sh
# requires when they are missing, report what it could not install, and stay
# out of apt everywhere else. sudo and apt-get are stubs; no package is touched.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-deps.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

DEPS="$(sed -n 's/^ *for pair in \(.*\); do$/\1/p' "$REPO/install.sh" | tr ' ' '\n' | cut -d: -f1 | tr '\n' ' ')"
[ -n "$DEPS" ] || { echo "FAIL: cannot read the dependency list from install.sh"; exit 1; }

# A PATH with everything from /usr/bin and /bin except the tools under test,
# plus stub sudo and apt-get. The apt-get stub records its arguments and, on
# install, provides the binary each package name stands for.
mk_path() {  # <dir> <sudo ok: 1|0> <tool to remove>...
  local d="$1" sudo_ok="$2"; shift 2
  mkdir -p "$d/bin"
  for f in /usr/bin/* /bin/*; do ln -sf "$f" "$d/bin/$(basename "$f")" 2>/dev/null; done
  # Every tool install.sh checks is present unless named below, whatever this
  # host lacks: the list is read from install.sh, so a new entry is covered.
  for t in $DEPS; do
    [ -e "$d/bin/$t" ] || { printf '#!/bin/sh\nexit 0\n' > "$d/bin/$t"; chmod +x "$d/bin/$t"; }
  done
  for t in "$@" sudo apt-get; do rm -f "$d/bin/$t"; done
  if [ "$sudo_ok" = 1 ]; then
    # shellcheck disable=SC2016  # literal $1/$@ for the stub script
    printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' > "$d/bin/sudo"
  else
    printf '#!/bin/sh\nexit 1\n' > "$d/bin/sudo"
  fi
  cat > "$d/bin/apt-get" <<EOF
#!/bin/sh
echo "\$*" >> "$d/apt.log"
[ "\$1" = install ] || exit 0
for p in "\$@"; do
  case "\$p" in -*|install) continue ;; ripgrep) p=rg ;; esac
  printf '#!/bin/sh\nexit 0\n' > "$d/bin/\$p"; chmod +x "$d/bin/\$p"
done
EOF
  chmod +x "$d/bin/sudo" "$d/bin/apt-get"
}

run() {  # <dir> <coder workspace id or empty>
  mkdir -p "$1/home"
  (cd "$REPO" && env -i HOME="$1/home" CODER_SYMLINK_DIR="$1/home" HOOK_BIN_DIR="$1/hookbin" \
    PATH="$1/bin" DOTFILES_PRIMARY="$TMP/no-primary" CODER_WORKSPACE_ID="$2" \
    bash install.sh > "$1/out" 2>&1)
}

# 1. Coder, two deps missing, sudo works: both installed by package name.
mk_path "$TMP/c1" 1 rg direnv; run "$TMP/c1" ws-test
grep -q 'install .*ripgrep' "$TMP/c1/apt.log" 2>/dev/null || note "case 1: ripgrep (for rg) was not apt-installed"
grep -q 'install .*direnv' "$TMP/c1/apt.log" 2>/dev/null || note "case 1: direnv was not apt-installed"
grep -q 'install .* gh\b' "$TMP/c1/apt.log" 2>/dev/null && note "case 1: a present tool (gh) was installed too"
grep -q 'Installing missing runtime deps: rg direnv' "$TMP/c1/out" || note "case 1: the install was not announced"
grep -q 'still missing' "$TMP/c1/out" && note "case 1: reported tools as still missing after a good install"

# 1b. Coder, the suite tools missing: zsh and shellcheck installed by name.
mk_path "$TMP/c1b" 1 zsh shellcheck; run "$TMP/c1b" ws-test
grep -q 'install .*zsh' "$TMP/c1b/apt.log" 2>/dev/null || note "case 1b: zsh was not apt-installed"
grep -q 'install .*shellcheck' "$TMP/c1b/apt.log" 2>/dev/null || note "case 1b: shellcheck was not apt-installed"

# 2. Not Coder: apt is never touched, whatever is missing.
mk_path "$TMP/c2" 1 rg direnv; run "$TMP/c2" ""
[ -e "$TMP/c2/apt.log" ] && note "case 2: apt-get ran outside a Coder workspace"

# 3. Coder, no passwordless sudo: report, do not call apt.
mk_path "$TMP/c3" 0 direnv; run "$TMP/c3" ws-test
[ -e "$TMP/c3/apt.log" ] && note "case 3: apt-get ran without passwordless sudo"
grep -q 'missing runtime deps (no apt-get or no passwordless sudo): direnv' "$TMP/c3/out" ||
  note "case 3: the missing tool was not reported"

# 4. Coder, nothing missing: silent and no apt.
mk_path "$TMP/c4" 1; run "$TMP/c4" ws-test
[ -e "$TMP/c4/apt.log" ] && note "case 4: apt-get ran with nothing missing"

for c in c1 c1b c2 c3 c4; do
  grep -q 'Dotfiles installation complete.' "$TMP/$c/out" || note "$c: installer did not reach its last line"
done

if [ "$fails" -ne 0 ]; then
  for c in c1 c3; do echo "--- $c ---"; tail -6 "$TMP/$c/out"; done
  exit 1
fi
echo "ok: missing runtime deps apt-installed on Coder only, reported when they cannot be"
