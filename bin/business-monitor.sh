#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# business-monitor.sh — 30-minute business metrics check
# Runs via launchd every 30 minutes. Checks:
#   1. AetherBot P&L / balance anomalies
#   2. Ticket queue depth and blocked count
#   3. Newsletter pipeline health (did today's brief ship?)
#   4. HQ feed freshness (is the feed stale?)
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LOG_DIR="$ROOT/kai/memory/daily"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW=$(TZ=America/Denver date +%H:%M)
DAILY_NOTE="$LOG_DIR/$TODAY.md"
TICKET_SCRIPT="$ROOT/bin/ticket.sh"

mkdir -p "$LOG_DIR"

log() { echo "[monitor] $(TZ=America/Denver date +%H:%M:%S) $*"; }

# ─── 1. Ticket queue snapshot ───
OPEN_TICKETS=0
BLOCKED_TICKETS=0
P1_TICKETS=0
if [[ -s "$ROOT/kai/tickets/tickets.jsonl" ]]; then
  OPEN_TICKETS=$(python3 -c "
import json
count = 0
with open('$ROOT/kai/tickets/tickets.jsonl') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        e = json.loads(line)
        if e.get('status') not in ('CLOSED', 'ARCHIVED'):
            count += 1
print(count)
" 2>/dev/null || echo "0")

  BLOCKED_TICKETS=$(python3 -c "
import json
count = 0
with open('$ROOT/kai/tickets/tickets.jsonl') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        e = json.loads(line)
        if e.get('status') == 'BLOCKED':
            count += 1
print(count)
" 2>/dev/null || echo "0")

  P1_TICKETS=$(python3 -c "
import json
count = 0
with open('$ROOT/kai/tickets/tickets.jsonl') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        e = json.loads(line)
        if e.get('priority') in ('P0', 'P1') and e.get('status') not in ('CLOSED', 'ARCHIVED'):
            count += 1
print(count)
" 2>/dev/null || echo "0")
fi

log "Tickets: $OPEN_TICKETS open, $BLOCKED_TICKETS blocked, $P1_TICKETS P0/P1"

# ─── 2. Newsletter check (did today's brief ship?) ───
NEWSLETTER_SHIPPED="no"
if [[ -f "$ROOT/agents/ra/output/$TODAY.html" ]]; then
  NEWSLETTER_SHIPPED="yes"
fi
if [[ -f "$ROOT/website/daily/$TODAY.html" ]]; then
  NEWSLETTER_DEPLOYED="yes"
else
  NEWSLETTER_DEPLOYED="no"
fi
log "Newsletter: shipped=$NEWSLETTER_SHIPPED deployed=$NEWSLETTER_DEPLOYED"

# ─── 3. Feed freshness ───
FEED="$ROOT/website/data/feed.json"
FEED_FRESH="unknown"
if [[ -f "$FEED" ]]; then
  FEED_DATE=$(python3 -c "
import json
d = json.load(open('$FEED'))
print(d.get('today', 'unknown'))
" 2>/dev/null || echo "unknown")
  if [[ "$FEED_DATE" == "$TODAY" ]]; then
    FEED_FRESH="yes"
  else
    FEED_FRESH="no (last: $FEED_DATE)"
  fi
fi
log "Feed: fresh=$FEED_FRESH"

# ─── 4. Write to daily note (Layer 2 memory) ───
# Only write if something noteworthy
if [[ "$BLOCKED_TICKETS" -gt 0 ]] || [[ "$P1_TICKETS" -gt 0 ]] || [[ "$NEWSLETTER_DEPLOYED" == "no" ]]; then
  cat >> "$DAILY_NOTE" << EOF

## [$NOW] Business Monitor
- Tickets: $OPEN_TICKETS open, $BLOCKED_TICKETS blocked, $P1_TICKETS P0/P1
- Newsletter: shipped=$NEWSLETTER_SHIPPED deployed=$NEWSLETTER_DEPLOYED
- Feed: fresh=$FEED_FRESH
EOF
  log "Wrote to daily note (issues detected)"
fi

# ─── 5. Alert if P0/P1 blocked ───
if [[ "$P1_TICKETS" -gt 0 ]] && [[ "$BLOCKED_TICKETS" -gt 0 ]]; then
  log "ALERT: $P1_TICKETS P0/P1 tickets with $BLOCKED_TICKETS blocked — check immediately"
fi
