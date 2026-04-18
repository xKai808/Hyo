#!/usr/bin/env bash
# kai/queue/dispatch-sync-hyo-messages.sh
# Runs at 16:00 MT daily via launchd (autonomous) AND on-demand.
#
# Logic:
#   1. Fetch any Hyo→Kai messages from Vercel (hyo-export endpoint)
#   2. Check if a Cowork/Kai session was active in the last 24h
#      (proxy: KAI_BRIEF.md mtime or hyo-inbox.jsonl last-entry ts)
#   3. If a session WAS present: also export conversation context
#      (the unsynced messages were likely discussed in-session; log them for audit)
#   4. If NO session: critical window — persist everything so next Kai open
#      picks up full context
#   5. Always: append unread messages to kai/ledger/hyo-inbox.jsonl
#   6. Log sync result to kai/ledger/dispatch-sync.log

set -uo pipefail

ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
INBOX="$ROOT/kai/ledger/hyo-inbox.jsonl"
SYNC_LOG="$ROOT/kai/ledger/dispatch-sync.log"
HQ_URL="${HQ_URL:-https://hyo.world}"
NOW_MT=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S%z")
NOW_EPOCH=$(date +%s)

log() { echo "[dispatch-sync $NOW_MT] $*" | tee -a "$SYNC_LOG"; }
log "=== Dispatch sync starting ==="

# ── Load founder token ──
FOUNDER_TOKEN=""
TOKEN_FILE="$ROOT/.secrets/founder.token"
if [[ -f "$TOKEN_FILE" ]]; then
  FOUNDER_TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
fi
if [[ -z "$FOUNDER_TOKEN" ]]; then
  FOUNDER_TOKEN="${HYO_FOUNDER_TOKEN:-}"
fi
if [[ -z "$FOUNDER_TOKEN" ]]; then
  log "ERROR: no founder token — cannot fetch from HQ"
  exit 1
fi

# ── Step 1: Check if Kai had a session in last 24h ──
SESSION_PRESENT=false
BRIEF="$ROOT/KAI_BRIEF.md"
if [[ -f "$BRIEF" ]]; then
  if stat -c %Y / >/dev/null 2>&1; then
    BRIEF_MTIME=$(stat -c %Y "$BRIEF" 2>/dev/null || echo 0)
  else
    BRIEF_MTIME=$(stat -f %m "$BRIEF" 2>/dev/null || echo 0)
  fi
  AGE=$(( NOW_EPOCH - BRIEF_MTIME ))
  if [[ $AGE -lt 86400 ]]; then
    SESSION_PRESENT=true
    SESSION_AGE_H=$(( AGE / 3600 ))
    log "Session detected: KAI_BRIEF.md updated ${SESSION_AGE_H}h ago — chat was present"
  else
    log "No recent session: KAI_BRIEF.md last updated $(( AGE / 3600 ))h ago"
  fi
fi

# Also check session transcripts if accessible (Claude Code stores in ~/.claude/)
CLAUDE_PROJECTS="$HOME/.claude/projects"
if [[ -d "$CLAUDE_PROJECTS" && "$SESSION_PRESENT" == "false" ]]; then
  # Look for any transcript modified in last 24h
  RECENT=$(find "$CLAUDE_PROJECTS" -name "*.jsonl" -newer "$BRIEF" 2>/dev/null | head -1)
  if [[ -n "$RECENT" ]]; then
    SESSION_PRESENT=true
    log "Session detected: recent transcript found at $RECENT"
  fi
fi

# ── Step 2: Fetch messages from Vercel ──
log "Fetching Hyo messages from $HQ_URL..."
HTTP_RESPONSE=$(curl -sf \
  -H "x-founder-token: $FOUNDER_TOKEN" \
  -w "\n__STATUS__%{http_code}" \
  "${HQ_URL}/api/hq?action=hyo-export" 2>/dev/null) || {
  log "WARNING: curl failed — network issue or endpoint unavailable"
  HTTP_RESPONSE=""
}

HTTP_BODY=$(echo "$HTTP_RESPONSE" | head -n -1)
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1 | sed 's/__STATUS__//')

if [[ "$HTTP_CODE" != "200" ]]; then
  log "WARNING: HQ returned HTTP $HTTP_CODE — skipping fetch this cycle"
  HTTP_BODY=""
fi

# ── Step 3: Parse + persist new messages ──
NEW_COUNT=0
TOTAL_IN_STORE=0

if [[ -n "$HTTP_BODY" ]]; then
  touch "$INBOX"
  RESULT=$(python3 - "$HTTP_BODY" "$INBOX" "$NOW_MT" "$SESSION_PRESENT" << 'PYEOF'
import json, sys

try:
    data = json.loads(sys.argv[1])
    messages = data.get('hyoMessages', [])
except Exception as e:
    print(f"0 0 PARSE_ERROR: {e}")
    sys.exit(0)

inbox_path = sys.argv[2]
now_mt = sys.argv[3]
session_present = sys.argv[4] == 'true'

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
                existing_keys.add(e.get('ts', '') + '|' + e.get('message', ''))
            except:
                pass
except FileNotFoundError:
    pass

new_count = 0
total = len(messages)

with open(inbox_path, 'a') as f:
    for m in reversed(messages):  # oldest first
        key = m.get('ts', '') + '|' + m.get('message', '')
        if key in existing_keys:
            continue
        entry = {
            'ts': m.get('ts', ''),
            'from': 'hyo',
            'message': m.get('message', ''),
            'status': 'unread',
            'source': 'hq-dispatch',
            'synced_at': now_mt,
            'session_was_present': session_present,
        }
        f.write(json.dumps(entry) + '\n')
        existing_keys.add(key)
        new_count += 1

print(f"{new_count} {total}")
PYEOF
  )
  NEW_COUNT=$(echo "$RESULT" | awk '{print $1}')
  TOTAL_IN_STORE=$(echo "$RESULT" | awk '{print $2}')
  log "Fetched $TOTAL_IN_STORE messages from store, wrote $NEW_COUNT new to hyo-inbox.jsonl"
else
  log "No data from HQ (fetch skipped or failed)"
fi

# ── Step 4: Summary ──
INBOX_TOTAL=$(wc -l < "$INBOX" 2>/dev/null | tr -d ' ')
INBOX_UNREAD=$(grep -c '"status": "unread"' "$INBOX" 2>/dev/null || echo 0)

log "hyo-inbox.jsonl: $INBOX_TOTAL total, $INBOX_UNREAD unread"
if [[ "$SESSION_PRESENT" == "true" ]]; then
  log "Context: session was active in last 24h — Kai likely has live context"
else
  log "Context: NO session in last 24h — messages queued for next Kai open"
fi
log "=== Dispatch sync complete: $NEW_COUNT new messages ==="

# ── Step 5: If new messages and no session, push a notification entry to feed ──
# (so next morning report surfaces the queued messages)
if [[ "$NEW_COUNT" -gt 0 && "$SESSION_PRESENT" == "false" ]]; then
  NOTIFY_FILE="$ROOT/kai/ledger/hyo-pending-notify.json"
  python3 -c "
import json
data = {
  'ts': '$NOW_MT',
  'type': 'hyo_message_queued',
  'count': $NEW_COUNT,
  'unread': $INBOX_UNREAD,
  'note': 'Hyo sent $NEW_COUNT message(s) while Kai was offline. Surface at next session start.'
}
with open('$NOTIFY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null && log "Pending notify written: $NOTIFY_FILE"
fi
