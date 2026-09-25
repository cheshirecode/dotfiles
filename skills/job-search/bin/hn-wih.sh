#!/bin/sh
# Convenience wrapper: hn-wih.sh [extra args...] -> python3 hn-wih.py "$@"
exec python3 "$(dirname "$0")/hn-wih.py" "$@"
