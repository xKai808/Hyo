#!/usr/bin/env bash
# kai/queue/fetch-hyo-messages.sh — Pull Hyo's messages from Vercel and persist to hyo-inbox.jsonl
#
# Run by: healthcheck.sh (every cycle) or manually via `kai exec "bash kai/queue/fetch-hyo-messages.sh"`
# Writes new messages to: kai/ledger/hyo-inbox.jsonl
#
# Architecture:
#   Vercel lambda (globalThis.__hq.hyoMessages) stores messages sent from HQ.
#   This script fetches them via /api/hq?action=data and appends any new ones
#   (those not already in hyo-inbox.jsonl) to the persistent ledger.

set -uo pipefail

ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
INBOX="$ROOT/kai/ledger/hyo-inbox.jsonl"
HQ_URL="${HQ_URL:-https://hyo.world}"
FOUNDER_TOKEN="${HYO_FOUNDER_TOKEN:-}"

# We need the founder token to authenticate
if [[ -z "$FOUNDER_TOKEN" ]]; then
  FOUNDER_TOKEN_FILE="$ROOT/.secrets/founder.token"
  if [[ -f "$FOUNDER_TOKEN_FILE" ]]; then
    FOUNDER_TOKEN=$(cat "$FOUNDER_TOKEN_FILE" | tr -d '[:space:]')
  fi
fi

if [[ -z "$FOUNDER_TOKEN" ]]; then
  echo "[fetch-hyo-messages] ERROR: no founder token available — skipping" >&2
  exit 1
fi

# Fetch messages from Vercel store
response=$(curl -sf \
  -H "x-founder-token: $FOUNDER_TOKEN" \
  "${HQ_URL}/api/hq?action=hyo-export" 2>/dev/null) || {
  # Fallback: try the data endpoint directly with a session token approach
  # (founder token can read the store too via a special export action we'll add)
  echo "[fetch-hyo-messages] WARNING: could not fetch from ${HQ_URL}/api/hq?action=hyo-export" >&2
  exit 0
}

if [[ -z "$response" ]]; then
  echo "[fetch-hyo-messages] No response from server" >&2
  exit 0
fi

# Parse messages and append new ones
touch "$INBOX"
new_count=0

python3 - "$response" "$INBOX" << 'PYEOF'
import json, sys

try:
    data = json.loads(sys.argv[1])
    messages = data.get('hyoMessages', [])
except:
    print("[fetch-hyo-messages] Could not parse response")
    sys.exit(0)

inbox_path = sys.argv[2]

# Read existing messages to avoid duplicates
existing_keys = set()
try:
    with open(inbox_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                existing_keys.add(e.get('ts', '') + e.get('message', ''))
            except:
                pass
except FileNotFoundError:
    pass

new_count = 0
with open(inbox_path, 'a') as f:
    for m in reversed(messages):  # reversed = oldest first
        key = m.get('ts', '') + m.get('message', '')
        if key in existing_keys:
            continue
        entry = {
            'ts': m.get('ts', ''),
            'from': 'hyo',
            'message': m.get('message', ''),
            'status': 'unread',
            'source': 'hq-dispatch',
        }
        f.write(json.dumps(entry) + '\n')
        existing_keys.add(key)
        new_count += 1

if new_count > 0:
    print(f"[fetch-hyo-messages] {new_count} new message(s) from Hyo written to hyo-inbox.jsonl")
else:
    print("[fetch-hyo-messages] No new messages")
PYEOF
