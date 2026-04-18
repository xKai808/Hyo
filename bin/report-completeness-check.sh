#!/usr/bin/env bash
# bin/report-completeness-check.sh — Daily scheduled check that all required
# reports were published. Opens a ticket and troubleshoots if anything is missing.
#
# Required every weekday:
#   - morning-report        (05:00 MT)
#   - newsletter-ra-DATE    (03:00 MT)
#   - nel-daily-DATE
#   - ra-daily-DATE
#   - sam-daily-DATE
#   - aether-daily-DATE     (skip weekends)
#   - kai-daily-DATE
#   - aether-analysis-DATE  (skip weekends — generated 23:00 MT, check next morning)
#
# Required every Saturday:
#   - nel-weekly-WEEK, ra-weekly-WEEK, sam-weekly-WEEK,
#     aether-weekly-WEEK, kai-weekly-WEEK
#
# Runs at 08:00 MT daily via launchd.
# If any report is missing: opens a ticket, runs the missing report generator,
# verifies success, closes ticket. No exceptions.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
DOW=$(TZ=America/Denver date +%u)   # 1=Mon 6=Sat 7=Sun
WEEK=$(TZ=America/Denver date +%Y-W%V)
YESTERDAY=$(TZ=America/Denver date -v-1d +%Y-%m-%d 2>/dev/null || TZ=America/Denver date -d 'yesterday' +%Y-%m-%d)

FEED_GIT="$ROOT/agents/sam/website/data/feed.json"
TICKETS_PATH="$ROOT/kai/tickets/tickets.jsonl"
CHECK_LOG="$ROOT/kai/ledger/completeness-check.log"

log() { echo "[check $(TZ=America/Denver date +%H:%M:%S)] $*" | tee -a "$CHECK_LOG"; }
fail() { log "FAIL: $*"; }
pass() { log "OK: $*"; }

log "=== Completeness check $TODAY (dow=$DOW) ==="
FAILURES=0

# ── Check if entry exists in feed ───────────────────────────────────────────
check_feed_entry() {
  local entry_id="$1"
  python3 -c "
import json, sys
with open('$FEED_GIT') as f:
    d = json.load(f)
sys.exit(0 if any(r.get('id') == '$entry_id' for r in d.get('reports',[])) else 1)
" 2>/dev/null
}

# ── Open a ticket for a missing report ──────────────────────────────────────
open_ticket() {
  local agent="$1" title="$2" id="$3"
  local ts=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
  local ticket_id="REPORT-CHECK-$(TZ=America/Denver date +%Y%m%d%H%M)-${agent}"
  echo "{\"id\":\"$ticket_id\",\"agent\":\"$agent\",\"status\":\"ACTIVE\",\"priority\":\"P1\",\"title\":\"Missing report: $title\",\"created\":\"$ts\",\"sla_override\":\"1hr\",\"expected_id\":\"$id\",\"auto_remediate\":true}" >> "$TICKETS_PATH"
  log "Ticket opened: $ticket_id — $title"
  echo "$ticket_id"
}

close_ticket() {
  local ticket_id="$1" summary="$2"
  local ts=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
  python3 - "$TICKETS_PATH" "$ticket_id" "$ts" "$summary" << 'PY'
import json, sys
path, tid, ts, summary = sys.argv[1:5]
lines = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            t = json.loads(line)
            if t.get('id') == tid:
                t['status'] = 'CLOSED'
                t['closed_at'] = ts
                t['resolution'] = summary
            lines.append(json.dumps(t))
        except: lines.append(line)
with open(path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
PY
}

# ── Remediate a missing report ───────────────────────────────────────────────
remediate() {
  local agent="$1" report_type="$2"
  log "Remediating: $agent $report_type"
  case "$report_type" in
    daily)
      HYO_ROOT="$ROOT" bash "$ROOT/bin/daily-agent-report.sh" "$agent" && return 0 || return 1 ;;
    newsletter)
      HYO_ROOT="$ROOT" bash "$ROOT/agents/ra/pipeline/newsletter.sh" --no-gather && return 0 || return 1 ;;
    morning-report)
      HYO_ROOT="$ROOT" bash "$ROOT/bin/generate-morning-report.sh" && return 0 || return 1 ;;
    weekly)
      HYO_ROOT="$ROOT" bash "$ROOT/bin/weekly-report.sh" --force && return 0 || return 1 ;;
    aether-analysis)
      HYO_ROOT="$ROOT" bash "$ROOT/agents/aether/analysis/run_analysis.sh" && return 0 || return 1 ;;
  esac
  return 1
}

# ────────────────────────────────────────────────────────────────────────────
# WEEKEND: Saturday checks only
if [[ "$DOW" == "6" ]]; then
  log "Saturday — checking weekly reports..."
  for agent in nel ra sam aether kai; do
    wid="${agent}-weekly-${WEEK}"
    if check_feed_entry "$wid"; then
      pass "weekly $agent"
    else
      fail "weekly $agent ($wid)"
      tid=$(open_ticket "$agent" "${agent^} weekly $WEEK" "$wid")
      if remediate "$agent" "weekly"; then
        close_ticket "$tid" "Auto-remediated: weekly-report.sh"
        pass "weekly $agent — FIXED"
      else
        fail "weekly $agent — REMEDIATION FAILED — manual intervention required"
        ((FAILURES++)) || true
      fi
    fi
  done
  log "=== Saturday check done. Failures: $FAILURES ==="
  exit $FAILURES
fi

# Sunday — no reports
if [[ "$DOW" == "7" ]]; then
  log "Sunday — no reports required."
  exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
# WEEKDAY checks
PREV_DOW=$(TZ=America/Denver date -v-1d +%u 2>/dev/null || TZ=America/Denver date -d 'yesterday' +%u)
CHECK_DATE="$TODAY"
# Check at 08:00 — the aether analysis runs at 23:00, so check yesterday's
AETHER_CHECK_DATE="$YESTERDAY"

# 1. Morning report (checked for TODAY — runs 05:00, we check 08:00)
MR_ID="morning-report-${TODAY}"
if check_feed_entry "$MR_ID"; then
  pass "morning-report $TODAY"
else
  fail "morning-report $TODAY ($MR_ID)"
  tid=$(open_ticket "kai" "Morning report $TODAY" "$MR_ID")
  if remediate "kai" "morning-report"; then
    close_ticket "$tid" "Auto-remediated: generate-morning-report.sh"
  else
    fail "morning-report — REMEDIATION FAILED"
    ((FAILURES++)) || true
  fi
fi

# 2. Newsletter
NL_ID="newsletter-ra-${TODAY}"
NL_HTML="$ROOT/agents/sam/website/daily/${TODAY}.html"
# Newsletter runs at 03:00 — by 08:00 it should exist
if check_feed_entry "$NL_ID"; then
  pass "newsletter $TODAY"
  # GATE: also verify the HTML file that readLink points to actually exists
  if [[ ! -f "$NL_HTML" ]]; then
    fail "newsletter HTML missing at website/daily/${TODAY}.html — readLink will 404"
    tid=$(open_ticket "ra" "Newsletter HTML missing for $TODAY" "$NL_ID")
    # Try to copy from ra/output
    SRC="$ROOT/agents/ra/output/${TODAY}.html"
    if [[ -f "$SRC" ]]; then
      cp "$SRC" "$NL_HTML"
      pass "newsletter HTML recovered from ra/output"
      close_ticket "$tid" "Auto-recovered: copied from agents/ra/output/${TODAY}.html"
    else
      fail "newsletter HTML UNRECOVERABLE — ra/output/${TODAY}.html also missing"
      ((FAILURES++)) || true
    fi
  fi
else
  fail "newsletter $TODAY ($NL_ID)"
  tid=$(open_ticket "ra" "Newsletter $TODAY" "$NL_ID")
  if remediate "ra" "newsletter"; then
    close_ticket "$tid" "Auto-remediated: newsletter.sh --no-gather"
  else
    fail "newsletter — REMEDIATION FAILED"
    ((FAILURES++)) || true
  fi
fi

# 3. Daily agent reports
for agent in nel ra sam aether kai; do
  # Skip Aether on weekends
  [[ "$PREV_DOW" == "6" || "$PREV_DOW" == "7" ]] && [[ "$agent" == "aether" ]] && continue
  
  did="${agent}-daily-${TODAY}"
  if check_feed_entry "$did"; then
    pass "daily $agent"
  else
    fail "daily $agent ($did)"
    tid=$(open_ticket "$agent" "${agent^} daily $TODAY" "$did")
    if remediate "$agent" "daily"; then
      close_ticket "$tid" "Auto-remediated: daily-agent-report.sh $agent"
    else
      fail "daily $agent — REMEDIATION FAILED"
      ((FAILURES++)) || true
    fi
  fi
done

# 4. Aether daily analysis (check yesterday's — runs 23:00)
# Skip if yesterday was weekend
if [[ "$PREV_DOW" != "6" && "$PREV_DOW" != "7" ]]; then
  AA_ID="aether-analysis-${AETHER_CHECK_DATE}"
  if check_feed_entry "$AA_ID"; then
    pass "aether-analysis $AETHER_CHECK_DATE"
  else
    fail "aether-analysis $AETHER_CHECK_DATE ($AA_ID)"
    tid=$(open_ticket "aether" "Aether analysis $AETHER_CHECK_DATE" "$AA_ID")
    if remediate "aether" "aether-analysis"; then
      close_ticket "$tid" "Auto-remediated: run_analysis.sh"
    else
      fail "aether-analysis — REMEDIATION FAILED — check Mini API keys"
      ((FAILURES++)) || true
    fi
  fi
fi

# 5. Commit check results
cd "$ROOT"
git add kai/tickets/tickets.jsonl agents/sam/website/data/feed.json website/data/feed.json 2>/dev/null || true
git diff --cached --quiet || git commit -m "chore: completeness check $TODAY — failures=$FAILURES" 2>/dev/null || true
git push origin main 2>&1 | tail -2 || true

log "=== Completeness check done. Failures: $FAILURES ==="
if [[ $FAILURES -gt 0 ]]; then
  log "ACTION REQUIRED: $FAILURES report(s) failed auto-remediation"
  exit 1
fi
exit 0
