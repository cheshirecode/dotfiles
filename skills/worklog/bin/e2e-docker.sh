#!/usr/bin/env bash
# Build + run the e2e test in both Linux Docker images (debian-slim
# glibc/GNU + alpine musl/busybox+coreutils). Default: parallel.
#
# Usage:
#   bin/e2e-docker.sh             # build both, run both, parallel
#   bin/e2e-docker.sh --serial    # serial; useful when debugging one image
#   bin/e2e-docker.sh debian      # only the debian image
#   bin/e2e-docker.sh alpine      # only the alpine image

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

want_debian=1
want_alpine=1
parallel=1

for arg in "$@"; do
  case "$arg" in
    --serial) parallel=0 ;;
    debian)   want_alpine=0 ;;
    alpine)   want_debian=0 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "e2e-docker: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

run_image() {
  local label="$1"
  local dockerfile="$2"
  local tag="worklog-e2e:$label"
  local logfile="/tmp/e2e-${label}.log"
  echo "[${label}] building $tag ..."
  docker build -q -t "$tag" -f "$dockerfile" . >"$logfile" 2>&1 || {
    echo "[${label}] BUILD FAILED — see $logfile"; tail -20 "$logfile"; return 1
  }
  echo "[${label}] running $tag ..."
  docker run --rm "$tag" >>"$logfile" 2>&1 || {
    echo "[${label}] E2E FAILED — see $logfile"; tail -30 "$logfile"; return 1
  }
  echo "[${label}] PASS — log: $logfile"
}

start=$SECONDS

if (( parallel )); then
  pids=()
  (( want_debian )) && { run_image debian Dockerfile.debian & pids+=($!); }
  (( want_alpine )) && { run_image alpine Dockerfile.alpine & pids+=($!); }
  rc=0
  for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
  (( rc == 0 )) || exit 1
else
  (( want_debian )) && run_image debian Dockerfile.debian
  (( want_alpine )) && run_image alpine Dockerfile.alpine
fi

elapsed=$((SECONDS - start))
echo
echo "e2e-docker: PASS in ${elapsed}s"
