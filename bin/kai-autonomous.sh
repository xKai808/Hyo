#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# kai-autonomous.sh — Master orchestrator daemon
# Version: 1.0 — 2026-04-21
#
# Runs every 15 minutes via launchd (com.hyo.kai-autonomous.plist).
# Single point of truth for "is the system healthy and are all agents running?"
#
# Responsibilities:
#   1. Track what ran vs what should have run (freshness checks)
#   2. Self-heal stale agents (retry, re-queue)
#   3. Compute system health score (0-100)
#   4. Enforce report completeness
#   5. Coordinate sequencing (some agents depend on others)
#   6. Drain and maintain the command queue
#   7. Publish daily health report to HQ
#   8. Never let Hyo wake up to a broken system
#
# Log: kai/ledger/kai-autonomous.log
# State: kai/ledger/kai-autonomous-state.json
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LOG="$HYO_ROOT/kai/ledger/kai-autonomous.log"
STATE="$HYO_ROOT/kai/ledger/kai-autonomous-state.json"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
PUBLISH_SH="$HYO_ROOT/bin/publish-to-feed.sh"

mkdir -p "$(dirname "$LOG")"

NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
NOW_EPOCH=$(date +%s)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
HOUR=$(TZ=America/Denver date +%H)
MINUTE=$(TZ=America/Denver date +%M)
DOW=$(TZ=America/Denver date +%u)  # 1=Monday, 7=Sunday

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_section() { echo "" >> "$LOG"; echo "══ $* ══" | tee -a "$LOG"; }

# ─── State management ─────────────────────────────────────────────────────────
read_state() {
  python3 -c "
import json, sys
try:
    with open('$STATE') as f:
        print(json.dumps(json.load(f)))
except:
    print(json.dumps({}))
"
}

write_state() {
  local key="$1" value="$2"
  python3 - "$STATE" "$key" "$value" "$NOW_MT" << 'PYEOF'
import json, sys
state_path, key, value, ts = sys.argv[1:5]
try:
    with open(state_path) as f:
        state = json.load(f)
except:
    state = {}
state[key] = value
state[f"{key}_at"] = ts
with open(state_path, "w") as f:
    json.dump(state, f, indent=2)
PYEOF
}

get_state() {
  local key="$1"
  python3 -c "
import json
try:
    with open('$STATE') as f:
        s = json.load(f)
    print(s.get('$key', ''))
except:
    print('')
"
}

# ─── Agent freshness check ────────────────────────────────────────────────────
# Returns hours since last successful run of agent
agent_freshness_hours() {
  local agent="$1"
  local marker_file="$HYO_ROOT/agents/$agent/ledger/ACTIVE.md"
  [[ ! -f "$marker_file" ]] && echo 999 && return
  local mtime
  mtime=$(stat -f %m "$marker_file" 2>/dev/null || stat -c %Y "$marker_file" 2>/dev/null || echo 0)
  echo $(( (NOW_EPOCH - mtime) / 3600 ))
}

# ─── Log freshness check ─────────────────────────────────────────────────────
log_freshness_hours() {
  local agent="$1"
  local log_pattern="$HYO_ROOT/agents/$agent/logs/${agent}-${TODAY}.md"
  local log_file
  log_file=$(ls -t "$log_pattern" 2>/dev/null | head -1)
  [[ -z "$log_file" ]] && echo 999 && return
  local mtime
  mtime=$(stat -f %m "$log_file" 2>/dev/null || stat -c %Y "$log_file" 2>/dev/null || echo 0)
  echo $(( (NOW_EPOCH - mtime) / 3600 ))
}

# ─── Queue a command to the Mini ──────────────────────────────────────────────
queue_job() {
  local cmd="$1"
  local jid
  jid=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
  python3 -c "
import json
print(json.dumps({'id': '$jid', 'ts': '$NOW_MT', 'command': $(python3 -c "import json; print(json.dumps('$cmd'))")}))
" > "$HYO_ROOT/kai/queue/pending/${jid}.json"
  log "  → Queued: $jid"
}

# ─── Open a ticket if missing ─────────────────────────────────────────────────
open_ticket_if_missing() {
  local agent="$1" title="$2" priority="$3"
  local exists
  exists=$(python3 -c "
import json
try:
    with open('$HYO_ROOT/kai/tickets/tickets.jsonl') as f:
        for line in f:
            e = json.loads(line.strip())
            if e.get('owner') == '$agent' and e.get('title') == '$title' and e.get('status') not in ('CLOSED','ARCHIVED','RESOLVED'):
                print('yes')
                break
except:
    pass
")
  [[ "$exists" == "yes" ]] && return 0
  HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
    --agent "$agent" --title "$title" --priority "$priority" \
    --created-by "kai-autonomous" 2>/dev/null || true
  log "  → Opened ticket: [$priority] $agent: $title"
}

# ─── Hyo inbox page ───────────────────────────────────────────────────────────
page_hyo() {
  local msg="$1"
  python3 -c "
import json
print(json.dumps({'ts': '$NOW_MT', 'from': 'kai-autonomous', 'priority': 'URGENT', 'status': 'unread', 'message': $(python3 -c "import json; print(json.dumps('$msg'))")}))
" >> "$INBOX"
  log "  → Paged Hyo: $msg"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: AGENT FRESHNESS + SELF-HEALING
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 1: AGENT FRESHNESS"

HEALTH_SCORE=0
AGENT_HEALTH=0

for agent in nel ra sam aether dex hyo; do
  freshness=$(agent_freshness_hours "$agent")
  threshold=26
  [[ "$agent" == "aether" ]] && threshold=1  # Aether every 15 min

  if [[ $freshness -le $threshold ]]; then
    log "✓ $agent — ${freshness}h ago (within ${threshold}h threshold)"
    AGENT_HEALTH=$((AGENT_HEALTH + 1))
  else
    log "✗ $agent — STALE ${freshness}h (threshold ${threshold}h)"
    # Self-heal: queue a run
    case "$agent" in
      nel)
        queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/nel/nel.sh >> $HYO_ROOT/agents/nel/logs/nel-${TODAY}.md 2>&1"
        open_ticket_if_missing "nel" "Nel stale: ${freshness}h since last run" "P1"
        ;;
      ra)
        queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/ra/ra.sh >> $HYO_ROOT/agents/ra/logs/ra-${TODAY}.md 2>&1"
        open_ticket_if_missing "ra" "Ra stale: ${freshness}h since last run" "P1"
        ;;
      sam)
        queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/sam/sam.sh test >> $HYO_ROOT/agents/sam/logs/sam-${TODAY}.md 2>&1"
        open_ticket_if_missing "sam" "Sam stale: ${freshness}h since last run" "P1"
        ;;
      aether)
        queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/aether/aether.sh >> $HYO_ROOT/agents/aether/logs/aether-${TODAY}.log 2>&1"
        open_ticket_if_missing "aether" "Aether stale: ${freshness}h since last metrics update" "P0"
        ;;
      dex)
        queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/dex/dex.sh >> $HYO_ROOT/agents/dex/logs/dex-${TODAY}.md 2>&1"
        open_ticket_if_missing "dex" "Dex stale: ${freshness}h since last integrity scan" "P2"
        ;;
      hyo)
        queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/hyo/hyo.sh >> $HYO_ROOT/agents/hyo/logs/hyo-${TODAY}.md 2>&1"
        open_ticket_if_missing "hyo" "Hyo agent stale: ${freshness}h since last surface audit" "P3"
        ;;
    esac
    # If stale for >48h → page Hyo
    [[ $freshness -gt 48 ]] && page_hyo "$agent agent has been stale ${freshness}h — self-healing attempts may be failing. Check queue."
  fi
done

# Agent freshness score: 20 pts (max) = 6 agents × 3.33 pts each
HEALTH_SCORE=$((HEALTH_SCORE + (AGENT_HEALTH * 20 / 6)))

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: NEWSLETTER CHECK
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 2: NEWSLETTER FRESHNESS"

NEWSLETTER_FRESH=0
NEWSLETTER_FILE=$(ls -t "$HYO_ROOT/agents/ra/output/newsletter-ra-${TODAY}"*.html 2>/dev/null | head -1)
if [[ -n "$NEWSLETTER_FILE" ]]; then
  log "✓ Newsletter: $NEWSLETTER_FILE"
  NEWSLETTER_FRESH=1
  HEALTH_SCORE=$((HEALTH_SCORE + 15))
else
  log "✗ Newsletter: missing for $TODAY"
  # After 06:00 MT, this becomes a problem
  if [[ $HOUR -ge 6 ]]; then
    open_ticket_if_missing "ra" "Newsletter missing for $TODAY (after 06:00 MT)" "P0"
    # Re-trigger newsletter pipeline
    queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/ra/pipeline/newsletter.sh >> $HYO_ROOT/agents/ra/logs/newsletter-${TODAY}.log 2>&1"
    log "  → Newsletter pipeline re-queued"
    # After 10:00 MT missing → page Hyo
    [[ $HOUR -ge 10 ]] && page_hyo "Newsletter still missing at ${HOUR}:${MINUTE} MT. Ra pipeline re-queued. May need API keys check."
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 3: HQ REPORT COMPLETENESS
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 3: HQ REPORT COMPLETENESS"

COMPLETENESS_SCORE=0
REPORTS_NEEDED=5
REPORTS_FOUND=0

# Check feed.json for today's required report types
FEED_FILE="$HYO_ROOT/agents/sam/website/data/feed.json"
if [[ -f "$FEED_FILE" ]]; then
  for rtype in "morning-report" "nel-daily" "ra-daily" "sam-daily" "aether-daily"; do
    found=$(python3 -c "
import json
try:
    with open('$FEED_FILE') as f:
        feed = json.load(f)
    reports = feed.get('reports', [])
    today = '$TODAY'
    found = any(r.get('date','') == today and '$rtype' in r.get('type','') for r in reports)
    print('yes' if found else 'no')
except:
    print('no')
")
    if [[ "$found" == "yes" ]]; then
      log "✓ Report: $rtype published today"
      REPORTS_FOUND=$((REPORTS_FOUND + 1))
    else
      log "✗ Report: $rtype NOT published today"
      # Open ticket for missing report if after expected publication time
      case "$rtype" in
        morning-report) [[ $HOUR -ge 7 ]] && open_ticket_if_missing "kai" "Morning report missing for $TODAY" "P0" ;;
        nel-daily)      [[ $HOUR -ge 23 ]] && open_ticket_if_missing "nel" "Nel daily report missing for $TODAY" "P1" ;;
        ra-daily)       [[ $HOUR -ge 23 ]] && open_ticket_if_missing "ra" "Ra daily report missing for $TODAY" "P1" ;;
        sam-daily)      [[ $HOUR -ge 23 ]] && open_ticket_if_missing "sam" "Sam daily report missing for $TODAY" "P1" ;;
        aether-daily)   [[ $HOUR -ge 23 ]] && open_ticket_if_missing "aether" "Aether daily report missing for $TODAY" "P1" ;;
      esac
    fi
  done
fi

HEALTH_SCORE=$((HEALTH_SCORE + (REPORTS_FOUND * 15 / REPORTS_NEEDED)))

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 4: TICKET SLA COMPLIANCE
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 4: TICKET SLA COMPLIANCE"

TICKET_SCORE=$(python3 - "$HYO_ROOT/kai/tickets/tickets.jsonl" "$NOW_EPOCH" << 'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta

ledger = sys.argv[1]
now = int(sys.argv[2])

sla_map = {'P0': 1800, 'P1': 3600, 'P2': 14400, 'P3': 86400}
total = 0
within_sla = 0
p0_open = 0

try:
    with open(ledger) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            e = json.loads(line)
            if e.get('status') in ('CLOSED', 'ARCHIVED', 'RESOLVED'): continue
            total += 1
            if e.get('priority') == 'P0': p0_open += 1
            try:
                created = datetime.fromisoformat(e.get('created_at', ''))
                age_sec = now - int(created.timestamp())
                sla = sla_map.get(e.get('priority', 'P2'), 14400)
                if age_sec <= sla:
                    within_sla += 1
            except:
                within_sla += 1  # can't parse = give benefit of doubt
except:
    pass

pct = int((within_sla / total * 100)) if total > 0 else 100
# Ticket health: 15 pts if ≥90%, 10 pts if ≥70%, 5 pts if ≥50%, 0 otherwise
score = 15 if pct >= 90 else (10 if pct >= 70 else (5 if pct >= 50 else 0))
# P0 bonus/penalty: -10 if any P0s open
if p0_open > 0: score = max(0, score - 10)
print(f"{pct} {p0_open} {score}")
PYEOF
)

SLA_PCT=$(echo "$TICKET_SCORE" | awk '{print $1}')
P0_OPEN=$(echo "$TICKET_SCORE" | awk '{print $2}')
TICKET_HEALTH=$(echo "$TICKET_SCORE" | awk '{print $3}')
HEALTH_SCORE=$((HEALTH_SCORE + TICKET_HEALTH))

log "Ticket SLA: ${SLA_PCT}% within SLA | P0 open: $P0_OPEN | score: $TICKET_HEALTH/15"
[[ "$P0_OPEN" -gt 0 ]] && \
  log "⚠️ P0 tickets open: $P0_OPEN — ticket-sla-enforcer will handle escalation"

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 5: SYSTEM QUALITY METRICS
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 5: QUALITY METRICS"

# Queue hygiene (5 pts)
QUEUE_COMPLETED=$(ls "$HYO_ROOT/kai/queue/completed/" 2>/dev/null | wc -l | tr -d ' ')
if [[ $QUEUE_COMPLETED -lt 50 ]]; then
  HEALTH_SCORE=$((HEALTH_SCORE + 5))
  log "✓ Queue hygiene: $QUEUE_COMPLETED completed items"
else
  log "✗ Queue hygiene: $QUEUE_COMPLETED items — triggering cleanup"
  queue_job "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/queue-hygiene.sh >> $HYO_ROOT/kai/ledger/queue-hygiene.log 2>&1"
fi

# Recurring patterns (5 pts)
PATTERN_COUNT=$(python3 -c "
try:
    count = 0
    with open('$HYO_ROOT/kai/ledger/known-issues.jsonl') as f:
        for line in f:
            e = __import__('json').loads(line.strip())
            if e.get('status','') == 'ACTIVE' and e.get('occurrences', 1) >= 3:
                count += 1
    print(count)
except:
    print(0)
" 2>/dev/null || echo 0)

if [[ $PATTERN_COUNT -lt 20 ]]; then
  HEALTH_SCORE=$((HEALTH_SCORE + 5))
  log "✓ Recurring patterns: $PATTERN_COUNT (threshold: 20)"
else
  log "✗ Recurring patterns: $PATTERN_COUNT — root-cause enforcer will address"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 6: SCHEDULE-DRIVEN TASK DISPATCH
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 6: SCHEDULED DISPATCH"

# Dispatch tasks that should run at this time window (±15 min tolerance)
# This replaces 15 individual launchd plists with one intelligent dispatcher

check_and_dispatch() {
  local target_hour="$1" target_min="$2" task_name="$3" command="$4" state_key="$5"
  local last_run
  last_run=$(get_state "$state_key")
  local cur_min_total=$((HOUR * 60 + MINUTE))
  local target_min_total=$((target_hour * 60 + target_min))
  local window=15  # ±15 minute window

  # Check if within window
  local diff=$((cur_min_total - target_min_total))
  [[ $diff -lt 0 ]] && diff=$((-diff))

  if [[ $diff -le $window && "$last_run" != "$TODAY-$target_hour$target_min" ]]; then
    log "→ Dispatching: $task_name"
    queue_job "$command"
    write_state "$state_key" "$TODAY-$target_hour$target_min"
  fi
}

# Morning report (07:00)
check_and_dispatch 7 0 "morning-report" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/generate-morning-report.sh >> $HYO_ROOT/kai/ledger/morning-report.log 2>&1" \
  "morning_report_run"

# Completeness check (07:15)
check_and_dispatch 7 15 "completeness-check" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/report-completeness-check.sh >> $HYO_ROOT/kai/ledger/completeness.log 2>&1" \
  "completeness_check_run"

# Queue hygiene (09:30)
check_and_dispatch 9 30 "queue-hygiene" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/queue-hygiene.sh >> $HYO_ROOT/kai/ledger/queue-hygiene.log 2>&1" \
  "queue_hygiene_run"

# Root-cause enforcer (15:00)
check_and_dispatch 15 0 "root-cause-enforcer" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/root-cause-enforcer.sh >> $HYO_ROOT/kai/ledger/root-cause-enforcer.log 2>&1" \
  "root_cause_run"

# Weekly report (Saturday 06:00)
if [[ $DOW -eq 6 ]]; then
  check_and_dispatch 6 0 "weekly-report" \
    "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/weekly-report.sh >> $HYO_ROOT/kai/ledger/weekly-report.log 2>&1" \
    "weekly_report_run"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 7: HEALTH SCORE + REPORTING
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 7: HEALTH SCORE"

# Cap at 100
[[ $HEALTH_SCORE -gt 100 ]] && HEALTH_SCORE=100

if [[ $HEALTH_SCORE -ge 85 ]]; then
  STATUS="GREEN"
elif [[ $HEALTH_SCORE -ge 70 ]]; then
  STATUS="YELLOW"
else
  STATUS="RED"
  page_hyo "System health: RED (score: $HEALTH_SCORE/100). Check kai-autonomous.log for details."
fi

log "System health: $STATUS ($HEALTH_SCORE/100)"
log "Agents online: $AGENT_HEALTH/6 | Newsletter: $NEWSLETTER_FRESH | Queue: ${QUEUE_COMPLETED} items | Recurring: ${PATTERN_COUNT} patterns"

# Write state
write_state "health_score" "$HEALTH_SCORE"
write_state "health_status" "$STATUS"
write_state "agent_health" "$AGENT_HEALTH"

# Daily health report at 23:50 (or first run after 23:45)
LAST_HEALTH_REPORT=$(get_state "health_report_today")
if [[ $HOUR -ge 23 && $MINUTE -ge 45 && "$LAST_HEALTH_REPORT" != "$TODAY" ]]; then
  # Publish health score to HQ
  SECTIONS_FILE="/tmp/kai-health-${TODAY}.json"
  python3 -c "
import json
s = {
  'summary': 'System health: $STATUS ($HEALTH_SCORE/100). Agents: $AGENT_HEALTH/6. Newsletter: $([ $NEWSLETTER_FRESH -eq 1 ] && echo published || echo missing). P0 open: $P0_OPEN. Recurring patterns: $PATTERN_COUNT.',
  'health_score': $HEALTH_SCORE,
  'status': '$STATUS',
  'agents_online': $AGENT_HEALTH,
  'sla_compliance_pct': $SLA_PCT,
  'p0_open': $P0_OPEN
}
print(json.dumps(s))
" > "$SECTIONS_FILE"
  HYO_ROOT="$HYO_ROOT" bash "$PUBLISH_SH" ceo-report kai \
    "System Health — $(TZ=America/Denver date '+%b %d, %Y') — $STATUS" \
    "$SECTIONS_FILE" 2>/dev/null || true
  write_state "health_report_today" "$TODAY"
  log "→ Daily health report published to HQ"
fi

exit 0
