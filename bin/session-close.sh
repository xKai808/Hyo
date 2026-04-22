#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# session-close.sh — Mandatory end-of-session protocol
# Part of SESSION_CONTINUITY_PROTOCOL.md (kai/protocols/)
#
# Runs at end of every Kai session. If skipped, run at START of next session.
# Never skip. This is what makes sessions recoverable.
#
# Usage:
#   bin/session-close.sh                          # interactive (asks for inputs)
#   bin/session-close.sh --auto                   # non-interactive (reads from env)
#   kai session-close                             # via kai.sh dispatcher
#
# Environment (for --auto mode):
#   SESSION_ID       — e.g. "27c9"
#   SESSION_SHIPPED  — comma-separated list of what shipped
#   SESSION_TOP_PRIO — single most important next action
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TIMESTAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW_H=$(TZ=America/Denver date +%H:%M)
AUTO_MODE="${1:-}"

HANDOFF_FILE="$HYO_ROOT/kai/ledger/session-handoff.json"
DAILY_NOTE="$HYO_ROOT/kai/memory/daily/$TODAY.md"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
CYN='\033[0;36m'
RST='\033[0m'

pass() { echo -e "${GRN}✓${RST} $1"; }
fail() { echo -e "${RED}✗${RST} $1"; }
warn() { echo -e "${YLW}⚠${RST} $1"; }
info() { echo -e "${CYN}→${RST} $1"; }

CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
  local label="$1"
  local result="$2"  # "pass" or "fail"
  if [[ "$result" == "pass" ]]; then
    pass "$label"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    fail "$label"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          KAI SESSION CLOSE PROTOCOL v1.0             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "  Time: $(TZ=America/Denver date)"
echo ""

# ─── STEP 1: Collect session summary ─────────────────────────────────────────

info "Step 1/7: Collecting session info..."

SESSION_ID="${SESSION_ID:-$(TZ=America/Denver date +%Y%m%d-%H%M)}"

# Read top priority from KAI_TASKS ★ block
TOP_PRIORITY="${SESSION_TOP_PRIO:-}"
if [[ -z "$TOP_PRIORITY" ]]; then
  TOP_PRIORITY=$(grep -A 3 '★ NEXT SESSION' "$HYO_ROOT/KAI_TASKS.md" 2>/dev/null \
    | grep 'STEP 2' | head -1 | sed 's/.*\*\*//;s/\*\*.*//' || echo "See KAI_TASKS.md ★ block")
fi

# Read open P0s from tickets.jsonl
OPEN_P0S=$(python3 -c "
import json, sys
p0s = []
try:
  with open('$HYO_ROOT/kai/tickets/tickets.jsonl') as f:
    for line in f:
      try:
        t = json.loads(line.strip())
        if t.get('priority') == 'P0' and t.get('status') not in ('CLOSED', 'ARCHIVED'):
          p0s.append(t.get('id','?') + ': ' + t.get('title','')[:80])
      except: pass
except: pass
print(json.dumps(p0s))
" 2>/dev/null || echo '[]')

# Read Hyo-pending from KAI_TASKS
HYO_PENDING=$(python3 -c "
import re, json
try:
  with open('$HYO_ROOT/KAI_TASKS.md') as f:
    content = f.read()
  # Find lines marked [H] that are not completed
  items = re.findall(r'- \[ \] \*\*\[H\]\*\* \*\*(.*?)\*\*', content)
  print(json.dumps(items[:5]))
except:
  print('[]')
" 2>/dev/null || echo '[]')

# Read queued commits
QUEUED_COMMITS=$(python3 -c "
import os, json, glob
pending = glob.glob('$HYO_ROOT/kai/queue/pending/*.json')
jobs = []
for p in pending:
  try:
    with open(p) as f:
      d = json.load(f)
    jobs.append(os.path.basename(p))
  except: pass
print(json.dumps(jobs))
" 2>/dev/null || echo '[]')

# ─── STEP 2: Write session-handoff.json ──────────────────────────────────────

info "Step 2/7: Writing session-handoff.json..."

SHIPPED_THIS_SESSION="${SESSION_SHIPPED:-See KAI_BRIEF.md Shipped today section}"

python3 << PYEOF
import json, os
from datetime import datetime

handoff = {
  "session_id": "$SESSION_ID",
  "ended_at": "$TIMESTAMP",
  "written_by": "session-close.sh",
  "top_priority": "$TOP_PRIORITY",
  "shipped_this_session": "$SHIPPED_THIS_SESSION".split(",") if "," in "$SHIPPED_THIS_SESSION" else ["$SHIPPED_THIS_SESSION"],
  "open_p0s": $OPEN_P0S,
  "hyo_actions_pending": $HYO_PENDING,
  "commits_queued": $QUEUED_COMMITS,
  "commits_to_verify": ["Run: git log --oneline -8 to confirm queue jobs landed"],
  "memory_freshness": {
    "kai_brief_mtime": str(datetime.fromtimestamp(os.path.getmtime("$HYO_ROOT/KAI_BRIEF.md")).strftime("%Y-%m-%dT%H:%M:%S")),
    "kai_tasks_mtime": str(datetime.fromtimestamp(os.path.getmtime("$HYO_ROOT/KAI_TASKS.md")).strftime("%Y-%m-%dT%H:%M:%S")),
    "daily_note_exists": os.path.exists("$DAILY_NOTE"),
    "handoff_written_at": "$TIMESTAMP"
  },
  "prep_failures": [],
  "continuity_protocol": "kai/protocols/SESSION_CONTINUITY_PROTOCOL.md",
  "notes": "Read this file FIRST next session — before KAI_BRIEF, before anything else."
}

with open("$HANDOFF_FILE", "w") as f:
  json.dump(handoff, f, indent=2)
print("  Handoff written: $HANDOFF_FILE")
PYEOF

if [[ -f "$HANDOFF_FILE" ]]; then
  check "session-handoff.json written" "pass"
else
  check "session-handoff.json written" "fail"
fi

# ─── STEP 3: Verify KAI_BRIEF freshness ──────────────────────────────────────

info "Step 3/7: Checking KAI_BRIEF.md freshness..."

BRIEF_AGE_MIN=$(python3 -c "
import os, time
mtime = os.path.getmtime('$HYO_ROOT/KAI_BRIEF.md')
print(int((time.time() - mtime) / 60))
" 2>/dev/null || echo "9999")

if [[ "$BRIEF_AGE_MIN" -lt 120 ]]; then
  check "KAI_BRIEF.md updated within 2h (${BRIEF_AGE_MIN}m ago)" "pass"
else
  check "KAI_BRIEF.md updated within 2h (${BRIEF_AGE_MIN}m ago — STALE)" "fail"
  warn "  → Update KAI_BRIEF.md before ending session"
fi

# ─── STEP 4: Verify KAI_TASKS freshness ──────────────────────────────────────

info "Step 4/7: Checking KAI_TASKS.md..."

TASKS_HAS_BLOCK=$(grep -c '★ NEXT SESSION' "$HYO_ROOT/KAI_TASKS.md" 2>/dev/null || echo "0")
if [[ "$TASKS_HAS_BLOCK" -gt 0 ]]; then
  check "KAI_TASKS.md has ★ NEXT SESSION PRIORITY QUEUE block" "pass"
else
  check "KAI_TASKS.md missing ★ NEXT SESSION PRIORITY QUEUE block" "fail"
  warn "  → Add the priority queue block to top of KAI_TASKS.md"
fi

# ─── STEP 5: Verify daily note ───────────────────────────────────────────────

info "Step 5/7: Checking daily note..."

if [[ -f "$DAILY_NOTE" ]]; then
  SESSION_END_IN_NOTE=$(grep -c 'Session end\|session-end\|End of Session\|SESSION_COMPLETE' "$DAILY_NOTE" 2>/dev/null || echo "0")
  if [[ "$SESSION_END_IN_NOTE" -gt 0 ]]; then
    check "Daily note $TODAY.md has session-end entry" "pass"
  else
    check "Daily note exists but missing session-end entry" "fail"
    warn "  → Append ## [$NOW_H] Session end entry to $DAILY_NOTE"
    # Auto-append a minimal entry
    echo "" >> "$DAILY_NOTE"
    echo "## [$NOW_H] Session end — auto-written by session-close.sh" >> "$DAILY_NOTE"
    echo "- session_id: $SESSION_ID" >> "$DAILY_NOTE"
    echo "- handoff written: $HANDOFF_FILE" >> "$DAILY_NOTE"
    echo "- top_priority: $TOP_PRIORITY" >> "$DAILY_NOTE"
    pass "  → Auto-appended session-end entry to daily note"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    CHECKS_FAILED=$((CHECKS_FAILED - 1))
  fi
else
  fail "Daily note $TODAY.md does not exist"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  mkdir -p "$(dirname "$DAILY_NOTE")"
  echo "## [$NOW_H] Session end — auto-written by session-close.sh" >> "$DAILY_NOTE"
  echo "- session_id: $SESSION_ID" >> "$DAILY_NOTE"
  echo "- handoff written: $HANDOFF_FILE" >> "$DAILY_NOTE"
  warn "  → Created minimal daily note"
fi

# ─── STEP 6: Queue commit for any uncommitted changes ────────────────────────

info "Step 6/7: Checking for uncommitted protocol changes..."

MODIFIED_FILES=$(cd "$HYO_ROOT" && git diff --name-only HEAD 2>/dev/null | grep -v '.json$' || echo "")
UNTRACKED=$(cd "$HYO_ROOT" && git ls-files --others --exclude-standard 2>/dev/null | grep 'kai/protocols\|kai/memory\|bin/' || echo "")

if [[ -n "$MODIFIED_FILES" ]] || [[ -n "$UNTRACKED" ]]; then
  warn "Uncommitted changes detected — queuing commit job..."

  COMMIT_JOB="$HYO_ROOT/kai/queue/pending/session-close-$(TZ=America/Denver date +%Y%m%d%H%M).json"
  python3 << PYEOF2
import json
job = {
  "id": "session-close-$(TZ=America/Denver date +%Y%m%d%H%M)",
  "created": "$TIMESTAMP",
  "type": "exec",
  "priority": "P1",
  "description": "Commit session close protocol files",
  "command": "cd ~/Documents/Projects/Hyo && git add kai/protocols/SESSION_CONTINUITY_PROTOCOL.md bin/session-close.sh bin/session-prep.sh kai/ledger/session-handoff.json KAI_BRIEF.md KAI_TASKS.md kai/memory/daily/$TODAY.md && git commit -m 'chore: session close protocol + handoff ($SESSION_ID)' && git push origin main",
  "expected_output": "main branch updated",
  "on_failure": "log P1: session-close commit failed",
  "session": "$SESSION_ID"
}
with open("$COMMIT_JOB", "w") as f:
  json.dump(job, f, indent=2)
print(f"  Queued: {job['id']}")
PYEOF2
  check "Commit job queued for modified files" "pass"
else
  check "No uncommitted protocol files (clean)" "pass"
fi

# ─── STEP 7: Final gate ───────────────────────────────────────────────────────

info "Step 7/7: Running final memory gate..."

GATE_PASSED=true

# KAI_BRIEF < 2h
[[ "$BRIEF_AGE_MIN" -gt 120 ]] && GATE_PASSED=false

# Handoff file exists
[[ ! -f "$HANDOFF_FILE" ]] && GATE_PASSED=false

# Daily note exists
[[ ! -f "$DAILY_NOTE" ]] && GATE_PASSED=false

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Session Close Results"
echo "  Passed: $CHECKS_PASSED  Failed: $CHECKS_FAILED"
echo "══════════════════════════════════════════════════════"

if [[ "$GATE_PASSED" == "true" ]] && [[ "$CHECKS_FAILED" -eq 0 ]]; then
  echo -e "  ${GRN}★ SESSION PROPERLY CLOSED${RST}"
  echo "  Next session reads: kai/ledger/session-handoff.json"
  echo "  Top priority: $TOP_PRIORITY"
else
  echo -e "  ${RED}✗ SESSION CLOSE INCOMPLETE — fix failures above before ending${RST}"
  exit 1
fi

echo ""
