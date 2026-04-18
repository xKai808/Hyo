#!/usr/bin/env bash
# kai-bridge-call.sh — Call the kai-bridge from anywhere (Cowork sandbox, any machine)
# Usage: bash bin/kai-bridge-call.sh "command here" [timeout_seconds] [host]
#
# Examples:
#   bash bin/kai-bridge-call.sh "echo hello"
#   bash bin/kai-bridge-call.sh "git status" 10 100.77.143.7
#   bash bin/kai-bridge-call.sh "bash agents/nel/nel.sh" 120

set -euo pipefail

CMD="${1:-echo ok}"
TIMEOUT="${2:-30}"
HOST="${3:-100.77.143.7}"  # Tailscale IP of Mac Mini
PORT="${4:-9876}"

HYO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOKEN_FILE="$HYO_ROOT/agents/nel/security/founder.token"

if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "[bridge-call] ERROR: token not found at $TOKEN_FILE" >&2
    exit 1
fi

TOKEN="$(cat "$TOKEN_FILE" | tr -d '[:space:]')"
BRIDGE_URL="http://${HOST}:${PORT}/exec"

BODY="$(python3 -c "
import json, sys
print(json.dumps({'cmd': sys.argv[1], 'timeout': int(sys.argv[2])}))
" "$CMD" "$TIMEOUT")"

echo "[bridge-call] → $HOST:$PORT"
echo "[bridge-call] cmd: ${CMD:0:100}"

RESPONSE="$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    --max-time $((TIMEOUT + 10)) \
    "$BRIDGE_URL")"

if [[ -z "$RESPONSE" ]]; then
    echo "[bridge-call] ERROR: no response from bridge (is it running?)" >&2
    exit 1
fi

EXIT_CODE="$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('exit_code',1))")"
STDOUT="$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stdout',''))" 2>/dev/null)"
STDERR="$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stderr',''))" 2>/dev/null)"
ELAPSED="$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('elapsed_ms',0))" 2>/dev/null)"

echo "[bridge-call] ← exit=$EXIT_CODE elapsed=${ELAPSED}ms"

if [[ -n "$STDOUT" ]]; then
    echo "$STDOUT"
fi

if [[ -n "$STDERR" ]]; then
    echo "[stderr] $STDERR" >&2
fi

exit "$EXIT_CODE"
