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
# PHASE 0: HYDRATION CHECK (Kai W1 fix — runs first, every cycle)
# Verifies all 12 hydration files are fresh. Logs stale files to session-errors.
# Gate question: "Did hydration-check pass?" NO → log warning, continue (non-blocking)
# ═══════════════════════════════════════════════════════════════════════════════
log_section "PHASE 0: HYDRATION CHECK"
if [[ -f "$HYO_ROOT/bin/kai-hydration-check.sh" ]]; then
    if HYO_ROOT="$HYO_ROOT" bash "$HYO_ROOT/bin/kai-hydration-check.sh" >> "$LOG" 2>&1; then
        log "Hydration check: PASS — all files fresh"
    else
        log "Hydration check: WARN — stale files detected (see receipt in kai/ledger/)"
        # Non-blocking: log the warning but continue. Blocking would prevent autonomous ops.
    fi
else
    log "Hydration check: SKIP — kai-hydration-check.sh not found"
fi

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

# ════════════════════════════════════════════════════════════════════════════
# DEPENDENCY-ORDERED SCHEDULE (see kai/protocols/SYSTEM_SCHEDULE.md)
#
# Sequence rationale:
#   Agents report (22-23h) → Consolidation (01-01:15h) → Ra newsletter (03h)
#   → Flywheel/growth cycle (04:30h) → Doctor+SICQ morning (05:30h)
#   → OMP+memory snapshot (06h) → Morning report (07h, has ALL fresh data)
#   → Completeness check (07:15h) → Midday maintenance (09-15h)
#
# DEPENDENCY CHAIN (critical path for morning report):
#   Nel/Sam/Aether runners (22:00-22:45) MUST precede morning report
#   Ra newsletter (03:00) MUST precede morning report
#   Flywheel/self-improve (04:30) MUST precede morning doctor+SICQ (05:30)
#   Flywheel doctor/SICQ (05:30) MUST precede OMP (06:00)
#   OMP (06:00) MUST precede morning report (07:00)
#   Morning report (07:00) MUST precede completeness check (07:15)
# ════════════════════════════════════════════════════════════════════════════

# Self-improvement cycle for all agents (04:30) — runs BEFORE morning report
# Moved from 08:00: flywheel results (aric-latest.json) must exist before morning report
# runs at 07:00. Previously the morning report always showed yesterday's flywheel output.
check_and_dispatch 4 30 "agent-self-improve-all" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/agent-self-improve.sh all >> $HYO_ROOT/kai/ledger/self-improve.log 2>&1" \
  "self_improve_run"

# Flywheel doctor + SICQ — morning run (05:30)
# Moved from 09:00: SICQ must be fresh BEFORE morning report at 07:00.
# Was previously written at 09:00 (after report) — morning report always showed yesterday's SICQ.
# Runs after flywheel (04:30) so it can validate the cycle that just completed.
check_and_dispatch 5 30 "flywheel-doctor-morning" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/flywheel-doctor.sh >> $HYO_ROOT/kai/ledger/flywheel-doctor.log 2>&1" \
  "flywheel_doctor_morning_run"

# OMP measurement (06:00) — outcome quality, after SICQ is fresh
# Moved from 06:45: gives more buffer before morning report + allows Saturday
# cross-agent review to stay at 06:45 without conflict.
# Publishes omp-daily to HQ feed. Injects GROWTH evidence if Kai metric drops.
check_and_dispatch 6 0 "omp-measure" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/omp-measure.sh >> $HYO_ROOT/kai/ledger/omp-measure.log 2>&1" \
  "omp_measure_run"

# Memory snapshot (06:15) — push today's SICQ + OMP to SQLite memory engine
# Ensures intra-day recall queries see today's scores (not just after 01:00 consolidation).
check_and_dispatch 6 15 "memory-snapshot" \
  "HYO_ROOT=$HYO_ROOT python3 $HYO_ROOT/kai/memory/agent_memory/memory_engine.py observe 'Daily metric snapshot: SICQ+OMP computed' --type metric_snapshot >> $HYO_ROOT/kai/ledger/memory-snapshot.log 2>&1 || true" \
  "memory_snapshot_run"

# Saturday only: weekly report (06:00) + cross-agent adversarial review (06:45)
# Weekly report at 06:00 — before OMP at 06:00 (both run, different state_keys)
# Cross-agent review at 06:45 — after OMP, before morning report
if [[ $DOW -eq 6 ]]; then
  check_and_dispatch 6 0 "weekly-report" \
    "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/weekly-report.sh >> $HYO_ROOT/kai/ledger/weekly-report.log 2>&1" \
    "weekly_report_run"

  # Cross-agent adversarial peer review (Saturday 06:45)
  # Nel reviews Sam, Sam reviews Nel, Ra reviews Aether, Dex reviews all
  # Primary antidote to echo chamber dynamics in the self-improvement flywheel
  check_and_dispatch 6 45 "cross-agent-review" \
    "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/cross-agent-review.sh >> $HYO_ROOT/kai/ledger/cross-agent-review.log 2>&1" \
    "cross_agent_review_run"
fi

# Morning report (07:00) — now has ALL fresh data:
#   ✓ Agent dailies (Nel/Sam/Aether ran at 22:00-22:45)
#   ✓ Ra newsletter (ran at 03:00)
#   ✓ Flywheel results (ran at 04:30)
#   ✓ SICQ fresh (doctor ran at 05:30)
#   ✓ OMP fresh (ran at 06:00)
check_and_dispatch 7 0 "morning-report" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/generate-morning-report.sh >> $HYO_ROOT/kai/ledger/morning-report.log 2>&1" \
  "morning_report_run"

# Completeness check (07:15) — verifies all required HQ entries exist; auto-remediates gaps
check_and_dispatch 7 15 "completeness-check" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/report-completeness-check.sh >> $HYO_ROOT/kai/ledger/completeness.log 2>&1" \
  "completeness_check_run"

# Session prep check (06:45) — verifies last session was properly closed, memory is fresh,
# and the next Kai session has everything it needs. Writes failures to hyo-inbox.jsonl.
# Runs EVERY day. On Saturday this runs alongside cross-agent-review (different state_key).
check_and_dispatch 6 45 "session-prep" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/session-prep.sh >> $HYO_ROOT/kai/ledger/session-prep.log 2>&1" \
  "session_prep_run"

# Queue hygiene (09:00)
check_and_dispatch 9 0 "queue-hygiene" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/queue-hygiene.sh >> $HYO_ROOT/kai/ledger/queue-hygiene.log 2>&1" \
  "queue_hygiene_run"

# Flywheel doctor midday check (09:30) — catch daytime drift, write SICQ update
check_and_dispatch 9 30 "flywheel-doctor-midday" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/flywheel-doctor.sh >> $HYO_ROOT/kai/ledger/flywheel-doctor.log 2>&1" \
  "flywheel_doctor_midday_run"

# Root-cause enforcer (15:00)
check_and_dispatch 15 0 "root-cause-enforcer" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/root-cause-enforcer.sh >> $HYO_ROOT/kai/ledger/root-cause-enforcer.log 2>&1" \
  "root_cause_run"

# Flywheel doctor evening check (17:00) — third check for P0 issues before agents run at 22:00
check_and_dispatch 17 0 "flywheel-doctor-evening" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/bin/flywheel-doctor.sh >> $HYO_ROOT/kai/ledger/flywheel-doctor.log 2>&1" \
  "flywheel_doctor_evening_run"

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
