#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# escalate-blocked.sh — Hourly blocked ticket escalation
# Runs via launchd every hour. Checks all BLOCKED tickets against SLA.
# Auto-escalates any that have breached. Writes to daily note.
# ═══════════════════════════════════════════════════════════════════════════
set -o pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TICKET_SCRIPT="$ROOT/bin/ticket.sh"
TICKET_LEDGER="$ROOT/kai/tickets/tickets.jsonl"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW=$(TZ=America/Denver date +%H:%M)
DAILY_NOTE="$ROOT/kai/memory/daily/$TODAY.md"

log() { echo "[escalate] $(TZ=America/Denver date +%H:%M:%S) $*"; }

if [[ ! -s "$TICKET_LEDGER" ]]; then
  log "No tickets in ledger. Nothing to escalate."
  exit 0
fi

# Run SLA check and capture output
SLA_OUTPUT=$(HYO_ROOT="$ROOT" bash "$TICKET_SCRIPT" sla-check 2>&1)
echo "$SLA_OUTPUT"

BREACH_COUNT=$(echo "$SLA_OUTPUT" | grep -c "overdue" 2>/dev/null) || BREACH_COUNT=0

if [[ "$BREACH_COUNT" -gt 0 ]]; then
  log "Found $BREACH_COUNT SLA breaches — escalating"

  # Extract ticket IDs and escalate each
  BREACH_IDS=$(echo "$SLA_OUTPUT" | grep -oE "TASK-[0-9]+-[a-z]+-[0-9]+" || true)
  for bid in $BREACH_IDS; do
    HYO_ROOT="$ROOT" bash "$TICKET_SCRIPT" escalate "$bid" "SLA breach (auto-escalated by hourly check)" 2>&1
    log "  Escalated: $bid"
  done

  # Write to daily note
  mkdir -p "$(dirname "$DAILY_NOTE")"
  cat >> "$DAILY_NOTE" << EOF

## [$NOW] Escalation Check
- $BREACH_COUNT tickets breached SLA
- Escalated: $(echo "$BREACH_IDS" | tr '\n' ', ')
EOF
else
  log "No SLA breaches. All clear."
fi

# Also check for BLOCKED tickets that are just sitting there
BLOCKED_COUNT=$(python3 -c "
import json
count = 0
with open('$TICKET_LEDGER') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        e = json.loads(line)
        if e.get('status') == 'BLOCKED':
            count += 1
print(count)
" 2>/dev/null || echo "0")

if [[ "$BLOCKED_COUNT" -gt 0 ]]; then
  log "WARNING: $BLOCKED_COUNT tickets still BLOCKED"
fi
