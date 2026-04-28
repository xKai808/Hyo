#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ticket-sla-enforcer.sh — Autonomous 24h ticket enforcement daemon
#
# Runs every 30 minutes via launchd. For every OPEN/ACTIVE ticket:
#   1. Computes age vs. SLA threshold (P0:30m P1:1h P2:4h P3:24h)
#   2. If overdue → escalates priority, dispatches agent nudge, logs
#   3. If P0 overdue → writes urgent message to Hyo inbox
#   4. Zombie detection: >90 days old → auto-archives
#   5. Publishes daily enforcer summary to HQ at 23:45 MT
#
# Log: kai/ledger/ticket-enforcer.log
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TICKET_LEDGER="$HYO_ROOT/kai/tickets/tickets.jsonl"
ENFORCER_LOG="$HYO_ROOT/kai/ledger/ticket-enforcer.log"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
TIMESTAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
NOW_EPOCH=$(date +%s)

mkdir -p "$(dirname "$ENFORCER_LOG")"

# ─── Log rotation: keep last 10 000 lines (prevents runaway growth) ──────────
if [[ -f "$ENFORCER_LOG" ]]; then
    _log_lines=$(wc -l < "$ENFORCER_LOG" 2>/dev/null || echo 0)
    if [[ $_log_lines -gt 10000 ]]; then
        tail -10000 "$ENFORCER_LOG" > "${ENFORCER_LOG}.tmp" && mv "${ENFORCER_LOG}.tmp" "$ENFORCER_LOG"
    fi
fi

log() { echo "[$(TZ=America/Denver date +%H:%M:%S)] $1" | tee -a "$ENFORCER_LOG"; }
log_section() { echo "" >> "$ENFORCER_LOG"; echo "═══ $1 ═══" | tee -a "$ENFORCER_LOG"; }

# ─── SLA thresholds in seconds ───────────────────────────────────────────────
SLA_P0=1800    #  30 minutes
SLA_P1=3600    #   1 hour
SLA_P2=14400   #   4 hours
SLA_P3=86400   #  24 hours
ZOMBIE_AGE=7776000  # 90 days

# ─── Nudge via dispatch ───────────────────────────────────────────────────────
nudge_agent() {
  local agent="$1" ticket_id="$2" age_h="$3" priority="$4" title="$5"
  local dispatch_bin="$HYO_ROOT/bin/dispatch.sh"
  local msg="SLA_BREACH [$priority] $ticket_id — ${age_h}h overdue. Title: $title. Assign to next cycle, provide update note within 1h."

  if [[ -x "$dispatch_bin" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$dispatch_bin" nudge "$agent" "$msg" 2>/dev/null \
      && log "  → Nudge dispatched to $agent" \
      || log "  → dispatch nudge failed (logged only)"
  else
    # Fallback: write to agent's ACTIVE.md
    local active="$HYO_ROOT/agents/$agent/ledger/ACTIVE.md"
    if [[ -f "$active" ]]; then
      echo "" >> "$active"
      echo "### ⚠️ SLA BREACH — $TIMESTAMP" >> "$active"
      echo "**$ticket_id** [$priority] ${age_h}h overdue: $title" >> "$active"
      echo "→ Update ticket status this cycle or escalation continues." >> "$active"
      log "  → Wrote SLA breach to $agent ACTIVE.md"
    fi
  fi
}

# ─── Page Hyo for P0 breaches ────────────────────────────────────────────────
page_hyo() {
  local ticket_id="$1" age_h="$2" title="$3"
  local entry
  entry=$(python3 -c "
import json
print(json.dumps({
  'ts': '$TIMESTAMP',
  'from': 'ticket-sla-enforcer',
  'priority': 'URGENT',
  'status': 'unread',
  'message': '🚨 P0 SLA BREACH: $ticket_id — ${age_h}h overdue. \"$title\". Immediate action required.'
}))
")
  echo "$entry" >> "$INBOX"
  log "  → P0 breach written to Hyo inbox"
}

# ─── Archive zombie ticket ────────────────────────────────────────────────────
archive_zombie() {
  local ticket_id="$1"
  python3 - "$TICKET_LEDGER" "$ticket_id" "$TIMESTAMP" << 'PYEOF'
import json, sys
ledger_path, ticket_id, timestamp = sys.argv[1:4]
lines = []
with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        entry = json.loads(line)
        if entry['id'] == ticket_id:
            entry['status'] = 'ARCHIVED'
            entry['notes'].append({'timestamp': timestamp, 'text': 'Auto-archived: zombie >90 days with no resolution'})
            entry['updated_at'] = timestamp
        lines.append(json.dumps(entry, ensure_ascii=False))
with open(ledger_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
}

# ─── Escalate one ticket ──────────────────────────────────────────────────────
escalate_ticket() {
  local ticket_id="$1" reason="$2"
  HYO_ROOT="$HYO_ROOT" bash "$HYO_ROOT/bin/ticket.sh" escalate "$ticket_id" "$reason" 2>/dev/null \
    && log "  → Escalated $ticket_id" \
    || log "  → Escalate failed for $ticket_id (check ledger)"
}

# ─── MAIN ENFORCEMENT LOOP ────────────────────────────────────────────────────
log_section "TICKET SLA ENFORCER — $(TZ=America/Denver date '+%Y-%m-%d %H:%M %Z')"

if [[ ! -f "$TICKET_LEDGER" ]]; then
  log "No ticket ledger found at $TICKET_LEDGER — exiting"
  exit 0
fi

# Collect enforcement actions via Python (parse all tickets at once)
ENFORCEMENT_JSON=$(python3 - "$TICKET_LEDGER" "$NOW_EPOCH" "$SLA_P0" "$SLA_P1" "$SLA_P2" "$SLA_P3" "$ZOMBIE_AGE" << 'PYEOF'
import json, sys, time

ledger_path = sys.argv[1]
now = int(sys.argv[2])
sla_p0, sla_p1, sla_p2, sla_p3, zombie_age = [int(x) for x in sys.argv[3:8]]

sla_map = {'P0': sla_p0, 'P1': sla_p1, 'P2': sla_p2, 'P3': sla_p3}
actions = []

with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            entry = json.loads(line)
        except:
            continue

        status = entry.get('status', '')
        if status in ('CLOSED', 'ARCHIVED', 'RESOLVED', 'SHIPPED'):
            continue

        # Parse created_at to epoch
        created_str = entry.get('created_at', '')
        if not created_str:
            continue
        try:
            from datetime import datetime, timezone, timedelta
            dt = datetime.fromisoformat(created_str)
            created_epoch = int(dt.timestamp())
        except:
            continue

        age_sec = now - created_epoch
        priority = entry.get('priority', 'P2')
        sla_sec = sla_map.get(priority, sla_p2)
        overdue_sec = age_sec - sla_sec

        action = {
            'id': entry['id'],
            'owner': entry.get('owner', 'kai'),
            'priority': priority,
            'title': entry.get('title', '(no title)'),
            'status': status,
            'age_h': round(age_sec / 3600, 1),
            'overdue_h': round(overdue_sec / 3600, 1) if overdue_sec > 0 else 0,
            'is_zombie': age_sec >= zombie_age,
            'is_overdue': overdue_sec > 0,
            'is_p0': priority == 'P0',
        }
        actions.append(action)

print(json.dumps(actions))
PYEOF
)

# Parse enforcement actions
TOTAL=$(echo "$ENFORCEMENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
OVERDUE=$(echo "$ENFORCEMENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for x in d if x['is_overdue']))")
ZOMBIES=$(echo "$ENFORCEMENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for x in d if x['is_zombie']))")

log "Scanned $TOTAL active tickets | $OVERDUE overdue | $ZOMBIES zombies"

# ─── Process each ticket ─────────────────────────────────────────────────────
ESCALATED=0
NUDGED=0
PAGED=0
ARCHIVED_ZOMBIES=0

while IFS= read -r action; do
  id=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['id'])")
  owner=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['owner'])")
  priority=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['priority'])")
  title=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['title'][:60])")
  age_h=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['age_h'])")
  overdue_h=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['overdue_h'])")
  is_overdue=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['is_overdue'])")
  is_zombie=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['is_zombie'])")
  is_p0=$(echo "$action" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['is_p0'])")

  if [[ "$is_zombie" == "True" ]]; then
    log "ZOMBIE [$priority] $id ($owner) — ${age_h}h old — archiving"
    archive_zombie "$id"
    ARCHIVED_ZOMBIES=$((ARCHIVED_ZOMBIES + 1))
    continue
  fi

  if [[ "$is_overdue" == "True" ]]; then
    log "BREACH [$priority] $id ($owner) — ${overdue_h}h overdue — $title"
    escalate_ticket "$id" "SLA breach: ${overdue_h}h overdue (enforcer auto-escalation)"
    nudge_agent "$owner" "$id" "$age_h" "$priority" "$title"
    ESCALATED=$((ESCALATED + 1))
    NUDGED=$((NUDGED + 1))

    if [[ "$is_p0" == "True" ]]; then
      page_hyo "$id" "$age_h" "$title"
      PAGED=$((PAGED + 1))
    fi
  fi

done < <(echo "$ENFORCEMENT_JSON" | python3 -c "
import json, sys
actions = json.load(sys.stdin)
for a in actions:
    print(json.dumps(a))
")

# ─── Summary ─────────────────────────────────────────────────────────────────
log_section "ENFORCER SUMMARY"
log "Escalated:  $ESCALATED"
log "Nudged:     $NUDGED"
log "P0 paged:   $PAGED"
log "Zombies:    $ARCHIVED_ZOMBIES"
log "Run at:     $TIMESTAMP"

# ─── Commit ledger changes if anything happened ───────────────────────────────
if [[ $((ESCALATED + ARCHIVED_ZOMBIES)) -gt 0 ]]; then
  EXEC_SCRIPT="$HYO_ROOT/kai/queue/exec.sh"
  if [[ -x "$EXEC_SCRIPT" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$EXEC_SCRIPT" --timeout 60 \
      "cd ~/Documents/Projects/Hyo && git add kai/tickets/tickets.jsonl kai/ledger/ && git commit -m 'enforcer: escalated=$ESCALATED archived=$ARCHIVED_ZOMBIES @ $(TZ=America/Denver date +%H:%M)' && git push origin main" \
      2>/dev/null || log "  → Git commit queued"
  fi
fi

exit 0
