#!/usr/bin/env bash
# bin/agent-outcome-check.sh — Outcome-based monitoring (not activity-based)
#
# KEY INSIGHT FROM RESEARCH: agents silently fail for hours with perfect-looking
# activity logs. The correct test is: did the agent produce expected OUTPUT
# at the expected LOCATION — not just "did it run."
#
# Sources: DEV Community "6 hours undetected downtime" | CIO "agents drift, not crash"
#
# Runs in kai-autonomous.sh Phase 7 (before health score calculation).
# Opens P1 ticket for any expected output that is missing.

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
HOUR=$(TZ=America/Denver date +%H)
LOG="$ROOT/kai/ledger/outcome-check.log"

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }

FAILURES=0
CHECKS=0

check_output() {
  local agent="$1" description="$2" path="$3" min_size="${4:-100}"
  CHECKS=$((CHECKS+1))
  if [[ ! -f "$path" ]]; then
    log "  ✗ $agent: MISSING $description — expected at $path"
    FAILURES=$((FAILURES+1))
    return 1
  fi
  local size
  size=$(wc -c < "$path" 2>/dev/null || echo 0)
  if [[ $size -lt $min_size ]]; then
    log "  ✗ $agent: STUB $description — only ${size}B at $path (min: ${min_size}B)"
    FAILURES=$((FAILURES+1))
    return 1
  fi
  log "  ✓ $agent: $description (${size}B)"
  return 0
}

log "=== Agent Outcome Check — $TODAY ==="

# Morning report (expected by 07:30 MT — check after 07:00)
if [[ $HOUR -ge 7 ]]; then
  MORNING_REPORT=$(python3 -c "
import json
with open('$ROOT/agents/sam/website/data/feed.json') as f:
    feed = json.load(f)
reports = [r for r in feed.get('reports',[]) if r.get('type')=='morning-report' and r.get('date','')=='$TODAY']
print(reports[0].get('id','') if reports else '')
" 2>/dev/null)
  if [[ -z "$MORNING_REPORT" ]]; then
    log "  ✗ kai: morning-report MISSING from feed.json for $TODAY"
    FAILURES=$((FAILURES+1))
  else
    log "  ✓ kai: morning-report present ($MORNING_REPORT)"
  fi
  CHECKS=$((CHECKS+1))
fi

# Newsletter (expected by 06:00 MT)
if [[ $HOUR -ge 6 ]]; then
  check_output "ra" "newsletter HTML" "$ROOT/website/daily/newsletter-${TODAY}.html" 1000
  check_output "ra" "newsletter MD" "$ROOT/agents/ra/output/${TODAY}.md" 500
fi

# Nel daily log (expected after each 6h cycle)
check_output "nel" "daily log" "$ROOT/agents/nel/logs/nel-${TODAY}.md" 200

# Sam self-review (expected daily)
check_output "sam" "self-review" "$ROOT/agents/sam/logs/self-review-${TODAY}.md" 100

# Aether analysis (expected after 23:00 MT — check in morning)
if [[ $HOUR -le 8 ]]; then
  YESTERDAY=$(TZ=America/Denver date -d "yesterday" +%Y-%m-%d 2>/dev/null || TZ=America/Denver date -v-1d +%Y-%m-%d)
  check_output "aether" "daily analysis" "$ROOT/agents/aether/analysis/Analysis_${YESTERDAY}.txt" 500
fi

# Verified state (expected every 15min — fail if >2h old)
if [[ -f "$ROOT/kai/ledger/verified-state.json" ]]; then
  AGE=$(python3 -c "import os,time; print(int((time.time()-os.path.getmtime('$ROOT/kai/ledger/verified-state.json'))/60))" 2>/dev/null || echo 999)
  if [[ $AGE -gt 120 ]]; then
    log "  ✗ kai: verified-state.json is ${AGE}min old (expected <120min)"
    FAILURES=$((FAILURES+1))
  else
    log "  ✓ kai: verified-state.json fresh (${AGE}min old)"
  fi
  CHECKS=$((CHECKS+1))
fi

log "=== Outcome Check: $CHECKS checked, $FAILURES failures ==="

# Open P1 tickets for each failure
if [[ $FAILURES -gt 0 ]]; then
  if [[ -f "$ROOT/bin/ticket.sh" ]]; then
    HYO_ROOT="$ROOT" bash "$ROOT/bin/ticket.sh" create \
      --agent "kai" \
      --title "Outcome check: $FAILURES agent output(s) missing for $TODAY" \
      --priority "P1" --type "monitoring" --created-by "agent-outcome-check" 2>/dev/null || true
  fi
fi

echo "$FAILURES" # return failure count for caller
