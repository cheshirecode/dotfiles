# Manual Drive upload recipe

Read only when preparing upload instructions and `gws` plus existing auth are
available. Do not run this script for the user unless separately authorized.
Fill COMPANY, JID, DATE, OUT, and FILES from the saved artifact manifest.
OUT is the absolute output directory the user selected; FILES holds the actual
basenames and extensions. Shell-quote each value (for example with Python
`shlex.quote`) rather than interpolating unescaped user text into shell code.

```bash
COMPANY='Example Company'
JID='123'
DATE='2026-09-10'
OUT='/absolute/path/to/application'
FILES=('resume-example-123.docx' 'cover-letter-example-123.txt' 'skills-keywords-example-123.txt')

set -euo pipefail
# Confirm every source before making any Drive request.
for f in "${FILES[@]}"; do
  [ -f "$OUT/$f" ] || { printf 'Missing artifact: %s\n' "$OUT/$f" >&2; exit 1; }
done
FOLDER_NAME="${COMPANY} — ${JID} — ${DATE}"
PARAMS=$(python3 - "$FOLDER_NAME" <<'PYQUERY'
import json, sys
name = sys.argv[1].replace("\\", "\\\\").replace("'", "\\'")
print(json.dumps({"q": "name = '" + name + "' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"}))
PYQUERY
)
FOLDER_ID=$(gws drive files list --params "$PARAMS" --format json | jq -r '.files[0].id // empty')
if [ -z "$FOLDER_ID" ]; then
  PAYLOAD=$(jq -cn --arg name "$FOLDER_NAME" '{name:$name,mimeType:"application/vnd.google-apps.folder"}')
  FOLDER_ID=$(gws drive files create --json "$PAYLOAD" --format json | jq -er '.id')
fi
for f in "${FILES[@]}"; do
  PAYLOAD=$(jq -cn --arg name "$f" --arg parent "$FOLDER_ID" '{name:$name,parents:[$parent]}')
  gws drive files create --upload "$OUT/$f" --json "$PAYLOAD"
done
```

The folder is reused when found. Uploading again can create duplicate files;
do not describe the whole upload as idempotent. Retain the manual drag-and-drop
path even when this script is included.
