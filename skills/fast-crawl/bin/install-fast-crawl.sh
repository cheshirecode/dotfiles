#!/usr/bin/env bash
# Install pinned, checksum-verified crawl engines for fcrawl.py.
#
#   lightpanda  release binary, SHA-256 pinned below
#   crw         fastCRW release tarball, SHA-256 pinned below (from SHA256SUMS)
#   crawl4ai    uv venv + Playwright Chromium; opt-in, about 1.1 GB on disk
#
# Everything lands under $FAST_CRAWL_HOME (default ~/.local/share/fast-crawl).
# Nothing is added to PATH and no shell profile is edited; fcrawl.py looks in
# $FAST_CRAWL_HOME/bin first.
#
# Usage: install-fast-crawl.sh [--engines LIST] [--dry-run] [--force]
set -uo pipefail

LIGHTPANDA_VERSION="0.4.1"
CRW_VERSION="0.36.0"
CRAWL4AI_VERSION="0.9.4"
CRAWL4AI_PYTHON="3.12"

ENGINES="lightpanda,crw"
DRY_RUN=0
FORCE=0

usage() {
  cat <<'USAGE'
Usage: install-fast-crawl.sh [flags]

Install pinned crawl engines under $FAST_CRAWL_HOME
(default ~/.local/share/fast-crawl). Each download is checked against a
SHA-256 pinned in this script; a mismatch installs nothing.

Flags:
  --engines LIST  Comma list of lightpanda, crw, crawl4ai
                  (default lightpanda,crw; crawl4ai needs uv and ~1.1 GB)
  --dry-run       Print what would be downloaded and where; change nothing
  --force         Reinstall even when the pinned version is present
  -h, --help      Show this help

Environment:
  FAST_CRAWL_HOME    install root (bin/, venv/, playwright/)
  FAST_CRAWL_MIRROR  base URL that replaces the GitHub release URLs
                     (the asset name is appended); used by the tests

Exit codes: 0 ok, 1 install step failed, 2 usage or missing tool,
4 checksum mismatch, 5 unsupported OS or CPU.
USAGE
}

log() { printf '%s\n' "==> $*"; }
die() { printf '%s\n' "ERROR: $*" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --engines) [ $# -ge 2 ] || die "--engines needs a value" 2; ENGINES="$2"; shift ;;
    --engines=*) ENGINES="${1#--engines=}" ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown flag: $1" 2 ;;
  esac
  shift
done

IFS=',' read -r -a WANT <<<"$ENGINES"
for e in "${WANT[@]}"; do
  case "$e" in
    lightpanda|crw|crawl4ai) ;;
    *) die "unknown engine '$e' (expected lightpanda, crw, crawl4ai)" 2 ;;
  esac
done

FC_HOME="${FAST_CRAWL_HOME:-$HOME/.local/share/fast-crawl}"
os="${FAST_CRAWL_FAKE_OS:-$(uname -s)}"
arch="${FAST_CRAWL_FAKE_ARCH:-$(uname -m)}"

# --- platform -> asset + pinned SHA-256 --------------------------------------
case "$os/$arch" in
  Darwin/arm64|Darwin/aarch64)
    LP_ASSET="lightpanda-aarch64-macos"
    LP_SHA="99e67739ed8cf5b985af7cbfa7c76b2bab257b171b2dad21109bd74b4f3bb510"
    CRW_ASSET="crw-darwin-arm64.tar.gz"
    CRW_SHA="4293f288a66515bc65acd3536323994fa8fb650408e662daa1d378e6209c3077" ;;
  Darwin/x86_64)
    LP_ASSET="lightpanda-x86_64-macos"
    LP_SHA="9f8ed2787476e39e9c8ba4890a4971391fb7098bbe6384350b21a3649b485eec"
    CRW_ASSET="crw-darwin-x64.tar.gz"
    CRW_SHA="b9d3261977287ef24fa1e0342ad4f14243338c315e538f3ec614ca7481face02" ;;
  Linux/x86_64|Linux/amd64)
    LP_ASSET="lightpanda-x86_64-linux"
    LP_SHA="1d40801e72c0bc61b2cbd3f3562bcfc46de7b79e0568f33f686b64f2e587610a"
    CRW_ASSET="crw-linux-x64.tar.gz"
    CRW_SHA="d72c6900b6355630cf0251f4e712a53f645655a43bc19998e7cfed0f2932bfb1" ;;
  Linux/aarch64|Linux/arm64)
    LP_ASSET="lightpanda-aarch64-linux"
    LP_SHA="664775c7f5ab69cc3189954c7f9345e25c167cb4dace016173e629f9a5e82c42"
    CRW_ASSET="crw-linux-arm64.tar.gz"
    CRW_SHA="945a9e6bbe850f865997e36c11ed467866eaa35e3cfd09d8ec7cb17f71bdc5d8" ;;
  *) die "unsupported platform '$os/$arch' (macOS or Linux on arm64/x86_64; Windows via WSL)" 5 ;;
esac

LP_URL="https://github.com/lightpanda-io/browser/releases/download/$LIGHTPANDA_VERSION/$LP_ASSET"
CRW_URL="https://github.com/fastcrw/crw/releases/download/v$CRW_VERSION/$CRW_ASSET"
if [ -n "${FAST_CRAWL_MIRROR:-}" ]; then
  LP_URL="${FAST_CRAWL_MIRROR%/}/$LP_ASSET"
  CRW_URL="${FAST_CRAWL_MIRROR%/}/$CRW_ASSET"
fi

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else die "need shasum or sha256sum to verify downloads" 2
  fi
}

# fetch_verified URL SHA DEST: download to DEST, or exit 4 and remove it.
fetch_verified() {
  local url="$1" want="$2" dest="$3" got
  curl -fsSL --retry 2 -o "$dest" "$url" || die "download failed: $url" 1
  got="$(sha256_of "$dest")"
  if [ "$got" != "$want" ]; then
    rm -f "$dest"
    die "checksum mismatch for $url: got $got, want $want" 4
  fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fast-crawl.XXXXXX")" || die "mktemp failed" 1
trap 'rm -rf "$TMP"' EXIT

install_lightpanda() {
  local dst="$FC_HOME/bin/lightpanda"
  if [ "$FORCE" -eq 0 ] && [ -x "$dst" ] &&
     [ "$(LIGHTPANDA_DISABLE_TELEMETRY=true "$dst" version 2>/dev/null)" = "$LIGHTPANDA_VERSION" ]; then
    log "lightpanda $LIGHTPANDA_VERSION already installed at $dst"; return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then log "would fetch $LP_URL (sha256 $LP_SHA) -> $dst"; return 0; fi
  fetch_verified "$LP_URL" "$LP_SHA" "$TMP/lightpanda"
  chmod +x "$TMP/lightpanda"
  mkdir -p "$FC_HOME/bin" && mv -f "$TMP/lightpanda" "$dst" || die "cannot write $dst" 1
  log "lightpanda $LIGHTPANDA_VERSION -> $dst"
}

install_crw() {
  local dst="$FC_HOME/bin/crw"
  if [ "$FORCE" -eq 0 ] && [ -x "$dst" ] &&
     [ "$("$dst" --version 2>/dev/null)" = "crw $CRW_VERSION" ]; then
    log "crw $CRW_VERSION already installed at $dst"; return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then log "would fetch $CRW_URL (sha256 $CRW_SHA) -> $dst"; return 0; fi
  fetch_verified "$CRW_URL" "$CRW_SHA" "$TMP/crw.tar.gz"
  tar -xzf "$TMP/crw.tar.gz" -C "$TMP" crw || die "tarball has no crw binary: $CRW_URL" 1
  mkdir -p "$FC_HOME/bin" && mv -f "$TMP/crw" "$dst" || die "cannot write $dst" 1
  log "crw $CRW_VERSION -> $dst"
}

install_crawl4ai() {
  local venv="$FC_HOME/venv" pw="$FC_HOME/playwright"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "would create $venv (python $CRAWL4AI_PYTHON), install crawl4ai==$CRAWL4AI_VERSION, Chromium -> $pw"
    return 0
  fi
  command -v uv >/dev/null 2>&1 || die "crawl4ai needs uv; install it, or drop crawl4ai from --engines" 2
  if [ "$FORCE" -eq 1 ] || [ ! -x "$venv/bin/python" ]; then
    uv venv -q --python "$CRAWL4AI_PYTHON" "$venv" || die "uv venv failed" 1
  fi
  VIRTUAL_ENV="$venv" uv pip install -q "crawl4ai==$CRAWL4AI_VERSION" || die "uv pip install crawl4ai failed" 1
  PLAYWRIGHT_BROWSERS_PATH="$pw" "$venv/bin/python" -m playwright install chromium ||
    die "playwright install chromium failed" 1
  log "crawl4ai $CRAWL4AI_VERSION -> $venv (Chromium in $pw)"
}

log "target $FC_HOME ($os/$arch)"
for e in "${WANT[@]}"; do "install_$e"; done
[ "$DRY_RUN" -eq 1 ] || log "check with: python3 $(cd "$(dirname "$0")" && pwd)/fcrawl.py doctor"
