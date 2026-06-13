#!/usr/bin/env bash
# Archive a task: move active/<slug>.md → archive/<slug>.md, set status=archived,
# clear next_action, emit Worklog-* trailers, commit + push.
#
# Usage:
#   bin/archive.sh <slug>
#   bin/archive.sh <slug> --pr=10997
#   bin/archive.sh <slug> --reason="shipped"          # default: shipped
#   bin/archive.sh <slug> --reason="superseded by eng-1600-foo"

set -euo pipefail

SLUG=""
PR=""
REASON="shipped"
SUMMARY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr=*)       PR="${1#--pr=}" ;;
    --reason=*)   REASON="${1#--reason=}" ;;
    --summary=*)  SUMMARY="${1#--summary=}" ;;
    --pr)         PR="$2"; shift ;;
    --reason)     REASON="$2"; shift ;;
    --summary)    SUMMARY="$2"; shift ;;
    -h|--help)
      cat <<EOF
usage: archive.sh <slug> [--pr=N] [--reason="..."] [--summary="..."]
  --pr       attach a PR number (also written into frontmatter pr: if absent)
  --reason   short marker written into the Context opener. One of:
             shipped | declined | abandoned | superseded | merged | obsolete
             (or "superseded by <slug>"). Default: shipped.
  --summary  2-3 line summary written into frontmatter summary: for archive
             browsability. Recommended — warns if absent.
EOF
      exit 0
      ;;
    *) SLUG="$1" ;;
  esac
  shift
done

if [[ -z "$SLUG" ]]; then
  echo "archive: slug required" >&2
  exit 2
fi

# Reason enum. Accepts the literal values or `superseded by <slug>` form.
# Historical archives pre-dating this rule are grandfathered (lint-only warning).
case "$REASON" in
  shipped|declined|abandoned|superseded|merged|obsolete) ;;
  "superseded by "*) ;;
  *)
    echo "archive: invalid --reason=\"$REASON\"" >&2
    echo "archive: allowed: shipped | declined | abandoned | superseded | merged | obsolete | \"superseded by <slug>\"" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
LDAP="$(resolve_ldap)"
verify_provenance || exit 1
detect_session_collision "$SLUG" 2>&1 || true

SRC="people/$LDAP/active/$SLUG.md"
DST="people/$LDAP/archive/$SLUG.md"
if [[ ! -f "$SRC" ]]; then
  echo "archive: $SRC not found" >&2
  exit 1
fi

# Orphan check: refuse if any active task points at this slug via a
# directional relation (parent_slug / supersedes / reopens) — those imply
# durable structural dependence and the child should be reparented first.
# `related[]` is a peer link and resolves fine to an archived target per
# AGENTS.md § Task relations, so it does not block archive.
if [[ -x "$SCRIPT_DIR/index.sh" ]]; then
  "$SCRIPT_DIR/index.sh" >/dev/null 2>&1 || true
  if [[ -f .cache/index.jsonl ]]; then
    ORPHAN_REPORT="$(jq -r --arg s "$SLUG" '
      select(.state == "active" and .slug != $s)
      | . as $r
      | if $r.parent_slug == $s then "  parent_slug: \($r.slug)"
        elif $r.supersedes == $s then "  supersedes: \($r.slug)"
        elif $r.reopens == $s then "  reopens: \($r.slug)"
        else empty end
    ' .cache/index.jsonl 2>/dev/null)"
    if [[ -n "$ORPHAN_REPORT" ]]; then
      echo "archive: WARNING — active tasks still reference $SLUG:" >&2
      echo "$ORPHAN_REPORT" >&2
      if [[ -z "${WORKLOG_ARCHIVE_FORCE:-}" ]]; then
        echo "archive: refuse to orphan children. Reparent them first, or set WORKLOG_ARCHIVE_FORCE=1 to proceed." >&2
        exit 1
      fi
      echo "archive: WORKLOG_ARCHIVE_FORCE=1 set, proceeding anyway." >&2
    fi
  fi
fi

if [[ -z "$SUMMARY" ]]; then
  echo "archive: WARNING — no --summary provided. Archive browsability suffers." >&2
  echo "archive: consider re-running with --summary=\"<2-3 line recap>\"." >&2
fi

TODAY="$(date +%Y-%m-%d)"

# Capture this session's tail into people/$LDAP/transcripts/<slug>.md before
# the body-edit so the body-edit can decide whether to add a Transcript: link.
# Silent skip if env not present.
SLUG="$SLUG" LDAP="$LDAP" TRIGGER="archive" \
  python3 "$SCRIPT_DIR/_dump_transcript.py" 2>/dev/null || true

TRANSCRIPT_FILE="people/$LDAP/transcripts/$SLUG.md"

python3 - "$SRC" "$TODAY" "$REASON" "$PR" "$SUMMARY" "$TRANSCRIPT_FILE" <<'PY'
import sys, re, pathlib
path, today, reason, pr, summary, transcript_rel = sys.argv[1:7]
p = pathlib.Path(path)
text = p.read_text()

def sub(field, value):
    global text
    # Match the field line PLUS any indented continuation lines (multi-line
    # YAML scalars). Without this, replacing a multi-line `next_action:` only
    # rewrites line 1 and leaves continuation orphans → YAML parse error in
    # the archived file. See worklog-protocol-archive-multiline-fix lesson.
    pattern = re.compile(rf'^{field}:.*(?:\n[ \t]+.*)*$', re.MULTILINE)
    if pattern.search(text):
        text = pattern.sub(lambda _m: f'{field}: {value}', text, count=1)
    else:
        text = re.sub(r'^(---\n.*?)(\n---)',
                      lambda m: f'{m.group(1)}\n{field}: {value}{m.group(2)}',
                      text, count=1, flags=re.DOTALL)

sub('status', 'archived')
sub('last_updated', today)
sub('next_action', '—')

# Strip operational claim: block (mutex metadata, not history). An orphan claim
# survives into archive otherwise and inflates project list's held= count.
text = re.sub(r'^claim:\n(?:  .*\n)+', '', text, flags=re.MULTILINE)
if summary:
    # Quote to survive colons / special chars in YAML.
    escaped = summary.replace('"', '\\"')
    sub('summary', f'"{escaped}"')

if pr:
    m = re.search(r'^pr:\s*(.+)$', text, re.MULTILINE)
    if not m:
        sub('pr', f'[{pr}]')
    else:
        existing = re.findall(r'\d+', m.group(1))
        if pr not in existing:
            existing.append(pr)
            sub('pr', '[' + ', '.join(existing) + ']')

# Prepend archive marker to Context if not already archived-marked. If an older
# task lacks ## Context entirely, create it instead of silently archiving without
# the browsability marker.
marker = f'Archived {today}: {reason}.'
transcript_link = ''
if transcript_rel and pathlib.Path(transcript_rel).exists():
    # archive/<slug>.md and transcripts/<slug>.md are sibling dirs.
    transcript_link = f'\nTranscript: [../transcripts/{pathlib.Path(transcript_rel).name}](../transcripts/{pathlib.Path(transcript_rel).name})'
marker_block = f'\n## Context\n\n{marker}{transcript_link}\n\n'
if '\n## Context\n' in text:
    if 'Archived ' not in text.split('\n## Context\n', 1)[1][:200]:
        text = re.sub(
            r'\n## Context\n\n?',
            f'\n## Context\n\n{marker}{transcript_link}\n\n',
            text,
            count=1,
        )
elif '\n## Next\n' in text:
    text = text.replace('\n## Next\n', f'{marker_block}## Next\n', 1)
else:
    text = text.rstrip() + marker_block

p.write_text(text)
PY

git pull --no-rebase --autostash -q
mkdir -p "$(dirname "$DST")"
git mv "$SRC" "$DST"
git add "$DST"
# Stage the transcript file alongside the archive so one ship == one commit.
if [[ -f "$TRANSCRIPT_FILE" ]]; then
  git add "$TRANSCRIPT_FILE"
fi

# Read back frontmatter for trailers.
KIND="$(awk -F': *' '/^kind:/ {print $2; exit}' "$DST" || true)"
LINEAR="$(awk -F': *' '/^linear:/ {print $2; exit}' "$DST" || true)"
PROJECT="$(awk -F': *' '/^project:/ {print $2; exit}' "$DST" || true)"
FM_PRS="$(python3 - "$DST" <<'PY' 2>/dev/null || true
import sys, re, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'^pr:\s*(.+)$', t, re.MULTILINE)
if not m: sys.exit(0)
v = m.group(1).strip()
nums = re.findall(r'\d+', v) if v.startswith('[') else ([v] if v else [])
print(",".join(n for n in nums if n))
PY
)"

TRAILERS="Worklog-Slug: $SLUG
Worklog-Status: archived
Worklog-Kind: ${KIND:-}
Worklog-Linear: ${LINEAR:-}"
[[ -n "$PROJECT" ]] && TRAILERS+="
Worklog-Project: $PROJECT"
PR_EMIT="${PR:-$FM_PRS}"
[[ -n "$PR_EMIT" ]] && TRAILERS+="
Worklog-PR: $PR_EMIT"

git commit -q -m "$SLUG: archive ($REASON)" -m "next: —" -m "$TRAILERS"
push_with_retry || exit 1
if [[ -x "$SCRIPT_DIR/autosave-flush.sh" ]]; then
  "$SCRIPT_DIR/autosave-flush.sh" >/dev/null 2>&1 || true
fi
record_session_touch "$SLUG" "archive"
echo "archive: pushed $SLUG"

# Soft retro prompt — archive is the natural end-of-arc moment. Stderr only,
# silence is a valid response. Suppress with WORKLOG_NO_RETRO=1.
if [[ "${WORKLOG_NO_RETRO:-0}" != "1" ]]; then
  cat >&2 <<EOF

retro: $SLUG is archived. Cross-task lesson worth preserving?
  Signal: "we'd want a future agent to know this without re-reading 10 commits."
  If yes → append to docs/lessons.md (newest at top in current month section).
  If no  → skip. Most archives don't generalize; that's fine.
EOF
fi
