#!/usr/bin/env bash
# Smoke: синтаксис YT-DPI.sh (Git Bash / Linux).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/YT-DPI.sh"
[[ -f "$target" ]] || { echo "Missing $target" >&2; exit 1; }
bash -n "$target"
echo "YT-DPI.sh bash -n: OK"
