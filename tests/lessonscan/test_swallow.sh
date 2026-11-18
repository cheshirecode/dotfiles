#!/usr/bin/env bash
# lessonscan's `swallow` class must see the forms it names:
#   - `except X:` then `pass`/`continue` on the next line. The pattern spans two
#     lines but scan() ran every pattern per line, so it never fired; only the
#     one-line `except: pass` was caught.
#   - a BROAD except (bare, Exception, BaseException) whose body only returns a
#     sentinel. A guard hook's `except Exception: return None` turned a
#     TypeError (an unsupported kwarg) into "could not read", so a code bug
#     read as an environment failure.
# A narrowed except that returns a sentinel is a deliberate answer: not flagged.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCAN="$ROOT/skills/lessons-to-guards/scripts/lessonscan.py"
T="$(mktemp -d "${TMPDIR:-/tmp}/lessonscan.XXXXXX")"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R"

cat > "$R/next_line_pass.py" <<'PY'
def a():
    try:
        x()
    except Exception:
        pass
PY
cat > "$R/broad_sentinel.py" <<'PY'
def b():
    try:
        return read()
    except Exception as exc:
        return None
PY
cat > "$R/bare_sentinel.py" <<'PY'
def c():
    try:
        return read()
    except:
        return ""
PY
cat > "$R/one_line.py" <<'PY'
try: x()
except: pass
PY
cat > "$R/narrow_sentinel.py" <<'PY'
def d():
    try:
        return read()
    except (ValueError, OSError):
        return None
PY

out="$(python3 -I "$SCAN" "$R" 2>&1)"
fails=0; ran=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
want() {  # want <file:line> <why>
  ran=$((ran + 1))
  printf '%s\n' "$out" | grep -qE "^[A-Z]+ swallow $1: " || note "$2 (no swallow finding at $1)"
}
want "next_line_pass.py:4" "except Exception: then pass on the next line"
want "broad_sentinel.py:4" "except Exception as exc: then return None"
want "bare_sentinel.py:4"  "bare except: then return \"\""
want "one_line.py:2"       "one-line except: pass"
ran=$((ran + 1))
printf '%s\n' "$out" | grep -qE '^[A-Z]+ swallow narrow_sentinel\.py:' && note "a narrowed except returning a sentinel was flagged"
[ "$ran" -eq 5 ] || note "expected 5 cases, ran $ran"

if [ "$fails" -ne 0 ]; then printf '%s\n' "--- scanner output ---" "$out"; exit 1; fi
echo "ok: swallow sees next-line pass, broad except returning a sentinel, and one-line except; narrowed excepts pass"
