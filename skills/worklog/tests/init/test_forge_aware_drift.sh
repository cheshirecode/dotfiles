#!/usr/bin/env bash
# Guardrail: the init light-path drift check must be forge-aware.
#
# Failure mode being pinned: the documented check was `gh pr list --author @me`.
# On a machine with no `gh` and GitLab clones, that command emits nothing, so
# the `drift:` block rendered EMPTY and read as "no drift" — structurally unable
# to report drift and silent about it. Real drift existed at the time (5 active
# tasks marked in-review whose GitLab MRs were already merged).
set -uo pipefail

# A developer BASH_ENV re-prepends ~/.local/bin in every child bash, undoing the
# PATH pinning below — the real `glab` then answers and the fixture silently
# measures the live vault instead of the stubs. Same hazard tests/run.sh guards.
unset BASH_ENV

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FORGE="$ROOT/bin/forge-prs.sh"
INIT_MODE="$ROOT/modes/init.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() { # check <label> <condition-result>
  if [[ "$2" == 0 ]]; then echo "ok: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi
}

# ---------------------------------------------------------------- doc contract
if [[ -f "$INIT_MODE" ]]; then
  grep -q 'forge-prs.sh' "$INIT_MODE"; check "init.md light path routes drift through forge-prs.sh" $?
  grep -q 'gap:' "$INIT_MODE"; check "init.md documents an explicit gap: line" $?
  if grep -q 'run `gh pr list --author @me --state open --json' "$INIT_MODE"; then
    check "init.md light path no longer hardcodes gh across all clones" 1
  else
    check "init.md light path no longer hardcodes gh across all clones" 0
  fi
else
  check "modes/init.md exists" 1
fi

if [[ ! -x "$FORGE" ]]; then
  echo "FAIL: bin/forge-prs.sh missing or not executable (forge selection is unimplemented)"
  exit 1
fi

# ------------------------------------------------------------------- fake repos
mk_clone() { # mk_clone <dir> <origin-url>
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}
mk_clone "$TMP/clones/midas" "git@gitlab.com:textemma/midas.git"
mk_clone "$TMP/clones/dotfiles" "https://github.com/cheshirecode/dotfiles.git"

# ------------------------------------------------- stub CLIs (glab yes, gh no)
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/glab" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
esac
if [[ "$1" == api && "$2" == user ]]; then
  echo '{"username":"fred.tran","state":"active"}'; exit 0
fi
if [[ "$1" == mr && "$2" == list ]]; then
  # Only the MR list for textemma/midas is populated.
  for a in "$@"; do [[ "$a" == "textemma/midas" ]] && found=1; done
  if [[ -n "${found:-}" ]]; then
    echo '[{"iid":1770,"title":"splus-19029 payout guard","web_url":"https://gitlab.com/textemma/midas/-/merge_requests/1770"}]'
  else
    echo '[]'
  fi
  exit 0
fi
if [[ "$1" == api && "$2" == *merge_requests* ]]; then
  # Adversarial payload: the object's own state is "merged" but a NESTED
  # author.state of "active" appears LATER in the one-line JSON. A greedy
  # regex takes the last match and reports the wrong, confident answer.
  echo '{"iid":1770,"state":"merged","author":{"username":"fred.tran","state":"active"}}'
  exit 0
fi
exit 1
EOF
chmod +x "$STUB/glab"
# Construct the absence of the forge CLIs; do not inherit it. This used to say
# "no `gh` stub -- this machine's exact condition" and pin
# PATH="$STUB:/usr/bin:/bin", which asserts `gh` is absent while leaving
# /usr/bin on PATH. It passed only because this box happened to have no gh.
# Installing gh (it is in install-runtime-deps.sh's REQUIRED list, so any
# properly provisioned machine has it) turned three assertions red at once.
# MIRROR is /usr/bin + /bin with the forge CLIs subtracted, so "no gh" is a
# property of the fixture rather than of the host.
MIRROR="$TMP/nobin"
mkdir -p "$MIRROR"
for d in /usr/bin /bin; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -x "$f" ] && [ ! -d "$f" ] || continue
    base="${f##*/}"
    case "$base" in gh|glab) continue ;; esac
    [ -e "$MIRROR/$base" ] || ln -sf "$f" "$MIRROR/$base"
  done
done
export PATH="$STUB:$MIRROR"

# Self-check: if PATH pinning did not take, every assertion below would be
# measuring the live forge instead of the stubs and could pass for wrong reasons.
[[ "$(command -v glab)" == "$STUB/glab" ]]
check "PATH pinning took: glab resolves to the stub" $?
[[ -z "$(command -v gh)" ]]
check "PATH pinning took: gh is absent" $?

out="$("$FORGE" list --author fred.tran "$TMP/clones/midas" "$TMP/clones/dotfiles" 2>/dev/null)"

[[ -n "$out" ]]; check "drift output is never silently empty" $?

# The load-bearing assertion: the GitLab clone must actually report its MR.
printf '%s' "$out" | grep -Eq $'^open\tgitlab\ttextemma/midas\t1770\t'
check "GitLab clone reports MR !1770 as drift candidate" $?

# The unreachable GitHub clone must be named, not silently dropped.
printf '%s' "$out" | grep -Eq $'^gap\tgithub\tcheshirecode/dotfiles\tgh-not-installed$'
check "unchecked GitHub repo is named in an explicit gap row" $?

# ------------------------------------------------- merged-MR drift (in-review)
st="$("$FORGE" state "$TMP/clones/midas" 1770 2>/dev/null)"
[[ "$st" == merged ]]
check "in-review drift: MR state parsed as 'merged' (got '$st'; nested author.state=active must not win)" $?

# --------------------------------------------- no forge CLI at all → all gaps
# MIRROR excludes gh AND glab, so this really is "no forge CLI" rather than
# "whichever of the two this host lacks today".
export PATH="$MIRROR"
out2="$("$FORGE" list --author fred.tran "$TMP/clones/midas" "$TMP/clones/dotfiles" 2>/dev/null)"
[[ -n "$out2" ]]; check "no-CLI case still produces output instead of an empty drift block" $?
printf '%s' "$out2" | grep -q $'^gap\tgitlab\ttextemma/midas\tglab-not-installed$'
check "no-CLI case names the GitLab repo it could not check" $?
printf '%s' "$out2" | grep -q $'^gap\tgithub\tcheshirecode/dotfiles\tgh-not-installed$'
check "no-CLI case names the GitHub repo it could not check" $?

# ------------------------------------- two clones of one project = one report
# /workspace/midas and /workspace/midas-wt-mockfix are both clones of
# textemma/midas, so a per-clone loop queries the project twice and every MR is
# reported twice. A reader cross-referencing 10 rows against 5 tracked MRs sees
# drift that is not there.
export PATH="$TMP/stub:$MIRROR"
git init -q "$TMP/clones/midas-wt" 2>/dev/null
git -C "$TMP/clones/midas-wt" remote add origin "https://gitlab.com/textemma/midas.git"
dup="$("$FORGE" list --author fred.tran "$TMP/clones/midas" "$TMP/clones/midas-wt" 2>/dev/null \
       | grep -c $'^open\tgitlab\ttextemma/midas\t1770\t' || true)"
[[ "$dup" == 1 ]]
check "one project cloned twice reports each MR once (got $dup rows)" $?

[[ $fails -eq 0 ]] || { echo "$fails assertion(s) failed"; exit 1; }
echo "ok: init light-path drift check is forge-aware"
