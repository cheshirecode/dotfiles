#!/usr/bin/env bash
# Repo invariants for machine-local credential files. This repo is public, so
# each of these is the difference between a secret holder being ignorable and
# being committable.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$REPO" || exit 2

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# 1. The live credential file must be ignored, so it cannot be committed even
#    if a copy lands inside a checkout.
git check-ignore -q .env.secrets ||
  note ".env.secrets is NOT gitignored; a filled-in credential file is committable"

# 2. The template must be TRACKED. `.env.*` ignores anything named
#    .env.secrets.example, which would look tracked in the working tree while
#    being absent from every fresh clone -- so install.sh would silently
#    create nothing. The name templates/env.secrets.example avoids that rule.
git ls-files --error-unmatch templates/env.secrets.example >/dev/null 2>&1 ||
  note "templates/env.secrets.example is not tracked; a fresh clone has no template"

# 3. The template must never carry a value. Keys only.
if [ -r templates/env.secrets.example ]; then
  if filled="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.+' templates/env.secrets.example)"; then
    note "the tracked template ships a value: $filled"
  fi
fi

# 4. No .shell_common.* overlay may be tracked. These are machine-local by
#    definition; one was tracked and published before this rule existed.
if tracked="$(git ls-files | grep -E '^\.shell_common\..+')"; then
  note "tracked .shell_common.* overlay(s): $(printf '%s' "$tracked" | tr '\n' ' ')"
fi

# 5. ...and the ignore rule must be the class, not one remembered name, so the
#    next suffix cannot be tracked by accident.
for probe in .shell_common.local .shell_common.vault .shell_common.anything-new; do
  git check-ignore -q "$probe" || note "$probe is not gitignored"
done

# 6. `.shell_common` itself must stay tracked. A `.shell_common.*` rule that
#    also caught the base file would silently drop the main shell config.
git ls-files --error-unmatch .shell_common >/dev/null 2>&1 ||
  note ".shell_common is no longer tracked; the ignore rule is too broad"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: credential file ignored, template tracked and empty, no .shell_common.* tracked"
