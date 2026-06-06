#!/usr/bin/env bash
# sql.sh — per-slug SQL query library. Runs queries via the bq CLI against
# cheshirecode's BigQuery warehouse (which exposes prod_spanner_multi_region as
# a connector dataset, so Spanner tables are queryable too).
#
# Layout:
#   queries/<slug>/<name>.sql      — committed SQL with header
#   .cache/queries/<slug>/<name>.json — response cache (gitignored)
#
# SQL header (required):
#   -- @env: prod | staging
#   -- @description: <one-liner — what question this answers>
#   -- @params: key=val, key=val   (optional)
#   -- @max-rows: 1000             (optional; default 1000)
#
# PII rule (enforced on `run` + `new`):
#   No literal email addresses, no /^[A-Za-z0-9+/=]{20,}$/ tokens
#   (catches base64-encoded user_id / org_id pasted directly).
#   Use parameters via `bq --parameter=name:STRING:value` if you need them.
#
# Usage:
#   bin/sql.sh list [<slug>]                   list saved queries
#   bin/sql.sh show <slug> <name>              cat the SQL
#   bin/sql.sh run <slug> <name> [--no-cache]  run + cache response
#   bin/sql.sh new <slug> <name>               scaffold a new query
#
# Cache: keyed only on file path. Re-run with --no-cache when you want fresh
# data; otherwise `run` returns the cached JSON. The cache exists so design
# doc reviewers can read the same numbers the author saw.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

usage() {
  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
}

CMD="${1:-}"
[[ -z "$CMD" || "$CMD" == "-h" || "$CMD" == "--help" ]] && { usage; exit 0; }
shift || true

case "$CMD" in
  list)
    SLUG="${1:-}"
    if [[ -n "$SLUG" ]]; then
      [[ -d "queries/$SLUG" ]] || { echo "no queries for slug: $SLUG" >&2; exit 0; }
      ls "queries/$SLUG"/*.sql 2>/dev/null | sed 's|queries/||; s|\.sql$||' || true
    else
      find queries -name '*.sql' 2>/dev/null | sed 's|queries/||; s|\.sql$||' | sort
    fi
    ;;

  show)
    SLUG="${1:?show: need <slug>}"
    NAME="${2:?show: need <name>}"
    cat "queries/$SLUG/$NAME.sql"
    ;;

  new)
    SLUG="${1:?new: need <slug>}"
    NAME="${2:?new: need <name>}"
    F="queries/$SLUG/$NAME.sql"
    [[ -f "$F" ]] && { echo "already exists: $F" >&2; exit 1; }
    mkdir -p "queries/$SLUG"
    cat > "$F" <<'EOF'
-- @env: prod
-- @description: <one-liner>
-- @max-rows: 1000

SELECT 1 AS placeholder
EOF
    echo "scaffolded $F — edit, then: bin/sql.sh run $SLUG $NAME"
    ;;

  run)
    SLUG="${1:?run: need <slug>}"
    NAME="${2:?run: need <name>}"
    NO_CACHE=0
    [[ "${3:-}" == "--no-cache" ]] && NO_CACHE=1
    F="queries/$SLUG/$NAME.sql"
    [[ -f "$F" ]] || { echo "no such query: $F" >&2; exit 1; }

    # Parse header
    ENV="$(awk -F': *' '/^-- @env:/ {print $2; exit}' "$F" | tr -d '[:space:]')"
    [[ -z "$ENV" ]] && { echo "missing -- @env: prod|staging in $F" >&2; exit 2; }
    [[ "$ENV" == "prod" || "$ENV" == "staging" ]] || { echo "@env must be prod or staging, got: $ENV" >&2; exit 2; }
    DESC="$(awk -F': *' '/^-- @description:/ {sub(/^-- @description: */,""); print; exit}' "$F")"
    [[ -z "$DESC" ]] && { echo "missing -- @description: in $F" >&2; exit 2; }
    MAX_ROWS="$(awk -F': *' '/^-- @max-rows:/ {print $2; exit}' "$F" | tr -d '[:space:]')"
    [[ -z "$MAX_ROWS" ]] && MAX_ROWS=1000

    # PII guard
    if grep -qE "[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" "$F"; then
      echo "sql: refusing to run — literal email address in $F. Use a parameter." >&2
      exit 2
    fi
    if grep -qE "['\"][A-Za-z0-9+/=]{20,}['\"]" "$F"; then
      echo "sql: refusing to run — long base64-shaped literal in $F (looks like a user_id / org_id)." >&2
      echo "     Use bq --parameter=name:STRING:value if you need to scope by id." >&2
      exit 2
    fi

    PROJECT="cheshirecode"
    [[ "$ENV" == "staging" ]] && PROJECT="cheshirecode"

    CACHE_DIR=".cache/queries/$SLUG"
    CACHE="$CACHE_DIR/$NAME.json"
    mkdir -p "$CACHE_DIR"

    if [[ "$NO_CACHE" -eq 0 && -f "$CACHE" ]]; then
      echo "sql: cache hit ($CACHE) — re-run with --no-cache to refresh" >&2
      cat "$CACHE"
      exit 0
    fi

    # Strip header lines (anything starting with -- @) before sending to bq;
    # bq accepts them as comments but it's cleaner without.
    SQL="$(grep -v '^-- @' "$F")"

    echo "sql: $ENV / $SLUG / $NAME — $DESC" >&2
    echo "sql: project=$PROJECT max_rows=$MAX_ROWS" >&2
    if ! bq query --project_id="$PROJECT" --use_legacy_sql=false \
         --format=json --max_rows="$MAX_ROWS" "$SQL" > "$CACHE.tmp" 2>"$CACHE.err"; then
      echo "sql: bq query failed:" >&2
      cat "$CACHE.err" >&2
      rm -f "$CACHE.tmp" "$CACHE.err"
      exit 1
    fi
    mv "$CACHE.tmp" "$CACHE"
    rm -f "$CACHE.err"
    echo "sql: wrote $CACHE ($(wc -c < "$CACHE") bytes)" >&2
    cat "$CACHE"
    ;;

  *) usage; exit 2 ;;
esac
