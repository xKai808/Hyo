#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# session-prep.sh — Nightly session integrity verifier
# Part of SESSION_CONTINUITY_PROTOCOL.md (kai/protocols/)
#
# Runs at 06:45 MT daily via kai-autonomous.sh (after morning report, before
# Hyo wakes up). Verifies that last night's session was properly closed and
# the next session will have everything it needs. If anything is wrong, it
# writes to hyo-inbox.jsonl so the next Kai sees it immediately at session start.
#
# Usage:
#   bin/session-prep.sh           # run check
#   kai session-prep              # via dispatcher
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TIMESTAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
YESTERDAY=$(TZ=America/Denver date -v-1d +%Y-%m-%d 2>/dev/null || TZ=America/Denver date -d "yesterday" +%Y-%m-%d)

HANDOFF_FILE="$HYO_ROOT/kai/ledger/session-handoff.json"
DAILY_NOTE="$HYO_ROOT/kai/memory/daily/$TODAY.md"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
PREP_LOG="$HYO_ROOT/kai/ledger/session-prep.log"

FAILURES=()
WARNINGS=()

log()  { echo "[$(TZ=America/Denver date +%H:%M:%S)] $1" | tee -a "$PREP_LOG"; }
fail() { FAILURES+=("$1"); log "FAIL: $1"; }
warn() { WARNINGS+=("$1"); log "WARN: $1"; }
pass() { log "PASS: $1"; }

log "═══════════════════════════════════════════════════════"
log "SESSION PREP CHECK — $TODAY"
log "═══════════════════════════════════════════════════════"

# ─── CHECK 1: session-handoff.json exists and is recent ───────────────────

if [[ -f "$HANDOFF_FILE" ]]; then
  HANDOFF_AGE_H=$(python3 -c "
import os, time, json
age_h = int((time.time() - os.path.getmtime('$HANDOFF_FILE')) / 3600)
try:
  d = json.load(open('$HANDOFF_FILE'))
  top = d.get('top_priority','unknown')
  print(f'{age_h}|{top[:60]}')
except:
  print(f'{age_h}|unreadable')
" 2>/dev/null || echo "999|error")
  AGE_H="${HANDOFF_AGE_H%%|*}"
  TOP_PRIO="${HANDOFF_AGE_H#*|}"

  if [[ "$AGE_H" -lt 24 ]]; then
    pass "session-handoff.json exists (${AGE_H}h old) — top: $TOP_PRIO"
  else
    fail "session-handoff.json is ${AGE_H}h old — session was not properly closed"
  fi
else
  fail "session-handoff.json MISSING — last session was not properly closed"
fi

# ─── CHECK 2: KAI_BRIEF.md was updated today or yesterday ─────────────────

BRIEF_AGE_H=$(python3 -c "
import os, time
print(int((time.time() - os.path.getmtime('$HYO_ROOT/KAI_BRIEF.md')) / 3600))
" 2>/dev/null || echo "9999")

if [[ "$BRIEF_AGE_H" -lt 30 ]]; then
  pass "KAI_BRIEF.md fresh (${BRIEF_AGE_H}h old)"
elif [[ "$BRIEF_AGE_H" -lt 48 ]]; then
  warn "KAI_BRIEF.md is ${BRIEF_AGE_H}h old — end-of-session update may have been skipped"
else
  fail "KAI_BRIEF.md is ${BRIEF_AGE_H}h old — session close was not completed"
fi

# ─── CHECK 3: daily note exists for today ─────────────────────────────────

if [[ -f "$DAILY_NOTE" ]]; then
  LINE_COUNT=$(wc -l < "$DAILY_NOTE" 2>/dev/null || echo "0")
  pass "Daily note $TODAY.md exists ($LINE_COUNT lines)"
else
  warn "Daily note $TODAY.md does not exist yet (may be pre-session — OK if before 22:00)"
fi

# ─── CHECK 4: KAI_TASKS.md has ★ NEXT SESSION block ──────────────────────

HAS_PRIO_BLOCK=$(grep -c '★ NEXT SESSION' "$HYO_ROOT/KAI_TASKS.md" 2>/dev/null || echo "0")
if [[ "$HAS_PRIO_BLOCK" -gt 0 ]]; then
  pass "KAI_TASKS.md has ★ NEXT SESSION PRIORITY QUEUE block"
else
  fail "KAI_TASKS.md is missing ★ NEXT SESSION PRIORITY QUEUE block"
fi

# ─── CHECK 5: all queued commits landed ───────────────────────────────────

PENDING_JOBS=$(ls "$HYO_ROOT/kai/queue/pending/"*.json 2>/dev/null | wc -l || echo "0")
if [[ "$PENDING_JOBS" -eq 0 ]]; then
  pass "No pending commit jobs — queue is clear"
else
  warn "$PENDING_JOBS commit job(s) still pending in queue — may not have landed yet"
  # List them
  for f in "$HYO_ROOT/kai/queue/pending/"*.json 2>/dev/null; do
    [[ -f "$f" ]] && warn "  Pending: $(basename "$f")"
  done
fi

# ─── CHECK 6: Open P0 tickets ─────────────────────────────────────────────

P0_COUNT=$(python3 -c "
import json
count = 0
try:
  with open('$HYO_ROOT/kai/tickets/tickets.jsonl') as f:
    for line in f:
      try:
        t = json.loads(line.strip())
        if t.get('priority') == 'P0' and t.get('status') not in ('CLOSED','ARCHIVED'):
          count += 1
      except: pass
except: pass
print(count)
" 2>/dev/null || echo "0")

if [[ "$P0_COUNT" -gt 0 ]]; then
  warn "$P0_COUNT open P0 ticket(s) — next session must address immediately"
else
  pass "No open P0 tickets"
fi

# ─── CHECK 7: simulation-outcomes freshness ───────────────────────────────

SIM_AGE_H=$(python3 -c "
import os, time
try:
  f = '$HYO_ROOT/kai/ledger/simulation-outcomes.jsonl'
  print(int((time.time() - os.path.getmtime(f)) / 3600))
except:
  print(9999)
" 2>/dev/null || echo "9999")

if [[ "$SIM_AGE_H" -lt 25 ]]; then
  pass "simulation-outcomes.jsonl updated ${SIM_AGE_H}h ago"
elif [[ "$SIM_AGE_H" -lt 50 ]]; then
  warn "simulation-outcomes.jsonl is ${SIM_AGE_H}h old — nightly simulation may have not run"
else
  fail "simulation-outcomes.jsonl is ${SIM_AGE_H}h old — simulation has not run in 2+ days"
fi

# ─── CHECK 8: Memory DB health ────────────────────────────────────────────

DB_PATH="$HYO_ROOT/kai/memory/agent_memory/memory.db"
if [[ -f "$DB_PATH" ]]; then
  DB_SIZE=$(du -k "$DB_PATH" | cut -f1)
  pass "Memory DB exists (${DB_SIZE}KB)"
  # Check for today's entries
  TODAY_ENTRIES=$(python3 -c "
import sqlite3
try:
  conn = sqlite3.connect('$DB_PATH')
  count = conn.execute(\"SELECT COUNT(*) FROM raw_events WHERE created_at LIKE '$TODAY%'\").fetchone()[0]
  print(count)
except:
  print(0)
" 2>/dev/null || echo "0")
  if [[ "$TODAY_ENTRIES" -gt 0 ]]; then
    pass "Memory DB has $TODAY_ENTRIES entries written today"
  else
    warn "Memory DB has 0 entries for today — memory engine may not be recording"
  fi
else
  warn "Memory DB not found at $DB_PATH — using flat-file fallback only"
fi

# ─── RESULTS AND INBOX WRITE ──────────────────────────────────────────────

log ""
log "═══ PREP RESULTS ═══"
log "Failures: ${#FAILURES[@]}  Warnings: ${#WARNINGS[@]}"

# Write results back to session-handoff.json
if [[ -f "$HANDOFF_FILE" ]]; then
  python3 << PYEOF
import json, os
try:
  with open('$HANDOFF_FILE', 'r') as f:
    d = json.load(f)
  d['prep_results'] = {
    'checked_at': '$TIMESTAMP',
    'failures': $(python3 -c "import json; print(json.dumps([f for f in [$(printf '"%s",' "${FAILURES[@]+"${FAILURES[@]}"}' | sed 's/,$//')]))" 2>/dev/null || echo '[]'),
    'warnings': $(python3 -c "import json; print(json.dumps([w for w in [$(printf '"%s",' "${WARNINGS[@]+"${WARNINGS[@]}"}' | sed 's/,$//')]))" 2>/dev/null || echo '[]'),
    'p0_count': $P0_COUNT,
    'pending_jobs': $PENDING_JOBS
  }
  with open('$HANDOFF_FILE', 'w') as f:
    json.dump(d, f, indent=2)
except Exception as e:
  print(f'Could not update handoff: {e}')
PYEOF
fi

# If any failures, write to hyo-inbox so next session sees them immediately
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  FAILURE_LIST=$(printf '%s; ' "${FAILURES[@]}")
  python3 - << PYEOF
import json
msg = {
  "ts": "$TIMESTAMP",
  "from": "session-prep",
  "priority": "P1",
  "status": "unread",
  "message": "SESSION PREP FOUND ${#FAILURES[@]} FAILURE(S): $FAILURE_LIST\nNext session must fix these before starting new work.",
  "action_required": True
}
with open('$INBOX', 'a') as f:
  f.write(json.dumps(msg) + '\n')
print("Wrote P1 alert to hyo-inbox.jsonl")
PYEOF
  log "P1 alert written to hyo-inbox.jsonl"
elif [[ "${#WARNINGS[@]}" -gt 0 ]]; then
  log "Warnings only — no inbox alert needed"
else
  log "All checks passed — next session fully prepped"
fi

# Write today's prep entry to daily note
echo "" >> "$DAILY_NOTE"
echo "## [$(TZ=America/Denver date +%H:%M)] Session Prep Check (06:45 MT automated)" >> "$DAILY_NOTE"
echo "- Failures: ${#FAILURES[@]}, Warnings: ${#WARNINGS[@]}" >> "$DAILY_NOTE"
for f in "${FAILURES[@]+"${FAILURES[@]}"}"; do echo "- FAIL: $f" >> "$DAILY_NOTE"; done
for w in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do echo "- WARN: $w" >> "$DAILY_NOTE"; done

log "Done."
