#!/usr/bin/env bash
# kai/queue/exec.sh — Execute a command on the Mini via queue, wait for result.
#
# Usage:
#   bash kai/queue/exec.sh "git status"
#   bash kai/queue/exec.sh --timeout 120 "npm run build"
#   bash kai/queue/exec.sh "launchctl list | grep hyo"
#
# From Cowork/Claude Code, HYO_ROOT should point to the mounted Hyo folder.
# On the Mini directly, it defaults to ~/Documents/Projects/Hyo.

set -euo pipefail

WAIT=45
TIMEOUT=60

while [[ $# -gt 1 ]]; do
    case "$1" in
        --wait)    WAIT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *)         break ;;
    esac
done

COMMAND="${1:?Usage: exec.sh [--wait N] [--timeout N] \"command\"}"

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
SUBMIT="$ROOT/kai/queue/submit.py"

if [[ ! -f "$SUBMIT" ]]; then
    echo "ERROR: submit.py not found at $SUBMIT" >&2
    exit 1
fi

# Submit and wait
exec python3 "$SUBMIT" --wait "$WAIT" --timeout "$TIMEOUT" "$COMMAND"
