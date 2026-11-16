#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
python3 -m unittest discover -s "$here" -p test_graph.py
