#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# flywheel-doctor.sh — Self-healing for the agent self-improvement flywheel
# Version: 1.0 — 2026-04-21
#
# PROTOCOL: FLYWHEEL_RECOVERY.md
#
# When the flywheel breaks, this script doesn't just ticket the problem —
# it attempts automated recovery in order of severity. Only escalates to
# Hyo when automated recovery is impossible.
#
# Every detected issue has a recovery path. Nothing is left hanging.
#
# Recovery hierarchy (attempted in order):
#   1. Automated fix (script can repair it)
#   2. State reset (return agent to safe known-good state)
#   3. P0 ticket + Kai signal (human-level awareness, Kai acts)
#   4. Hyo inbox entry (only for issues Kai cannot resolve)
#
# Called by: kai-autonomous.sh every 4 hours
# Log: kai/ledger/flywheel-doctor.log
# Report: kai/ledger/flywheel-doctor-latest.json
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/flywheel-doctor.log"
REPORT="$HYO_ROOT/kai/ledger/flywheel-doctor-latest.json"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
DISPATCH_SH="$HYO_ROOT/bin/dispatch.sh"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
KNOWLEDGE_MD="$HYO_ROOT/kai/memory/KNOWLEDGE.md"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
MAX_WEAKNESS_AGE_P0=7    # days before P0 weakness triggers alert
MAX_WEAKNESS_AGE_P1=14   # days before P1 weakness triggers alert
MAX_WEAKNESS_AGE_P2=30   # days before P2 weakness triggers alert
KNOWLEDGE_STALE_DAYS=7   # days since KNOWLEDGE.md last modified before alert
NO_RESOLVE_DAYS=14       # days with no resolved weakness before alert
SICQ_LOW_THRESHOLD=40    # SICQ below this for N days → system failure alert
SICQ_WARN_THRESHOLD=60   # SICQ below this → warning
SICQ_CONSECUTIVE_DAYS=3  # consecutive days below threshold before escalating
AGENTS=("nel" "sam" "aether" "ra" "dex" "kai")

log()     { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_sec() { echo "" >> "$LOG"; echo "══ $* ══" | tee -a "$LOG"; }

# Track all issues found and fixes applied for the report
ISSUES_FOUND=()
FIXES_APPLIED=()
ESCALATIONS=()

# ─── Ticket helper ────────────────────────────────────────────────────────────
open_ticket() {
  local agent="$1" title="$2" priority="$3"
  if [[ -f "$TICKET_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "$agent" --title "$title" --priority "$priority" \
      --type "improvement" --created-by "flywheel-doctor" 2>/dev/null || true
  fi
}

# ─── Hyo inbox helper ─────────────────────────────────────────────────────────
notify_hyo() {
  local subject="$1" body="$2"
  python3 - "$INBOX" "$subject" "$body" "$NOW_MT" << 'PYEOF'
import json, sys
path, subject, body, ts = sys.argv[1:5]
entry = {"ts": ts, "from": "flywheel-doctor", "subject": subject, "body": body, "status": "unread"}
with open(path, 'a') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF
}

# ─── Check 1: State JSON integrity ───────────────────────────────────────────
check_state_integrity() {
  log_sec "CHECK 1: State JSON integrity"
  for agent in "${AGENTS[@]}"; do
    local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
    [[ ! -f "$state_file" ]] && continue  # missing = will be initialized on first run

    local valid
    valid=$(python3 -c "
import json, sys
try:
    d = json.load(open('$state_file'))
    required = {'current_weakness', 'stage', 'cycles', 'failure_count'}
    missing = required - set(d.keys())
    if missing:
        print('CORRUPT:missing=' + ','.join(missing))
    elif d['stage'] not in ('research','implement','verify'):
        print('CORRUPT:invalid_stage=' + str(d['stage']))
    else:
        print('OK')
except Exception as e:
    print('CORRUPT:' + str(e)[:50])
" 2>/dev/null || echo "CORRUPT:parse_error")

    if [[ "$valid" == "OK" ]]; then
      log "  ✓ $agent state.json valid"
    else
      log "  ✗ $agent state.json CORRUPT ($valid) — resetting to safe state"
      ISSUES_FOUND+=("$agent: state.json corrupt ($valid)")
      # Recovery: reset to W1/research — safe known-good state
      echo '{"current_weakness":"W1","stage":"research","cycles":0,"failure_count":0,"improvements":[],"last_run":""}' > "$state_file"
      FIXES_APPLIED+=("$agent: state.json reset to W1/research")
      open_ticket "$agent" "Doctor: reset corrupt self-improve state for $agent" "P1"
      log "  ✓ Reset applied"
    fi
  done
}

# ─── Check 2: GROWTH.md presence and parseability ────────────────────────────
check_growth_md() {
  log_sec "CHECK 2: GROWTH.md presence and parseability"
  for agent in "${AGENTS[@]}"; do
    local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"

    if [[ ! -f "$growth_file" ]]; then
      log "  ✗ $agent GROWTH.md MISSING — creating minimal bootstrap"
      ISSUES_FOUND+=("$agent: GROWTH.md missing")
      # Recovery: create minimal bootstrap so flywheel can start
      cat > "$growth_file" << GROWTHEOF
# ${agent^} GROWTH.md — Auto-bootstrapped by flywheel-doctor
**Agent:** ${agent^}
**Date:** $TODAY
**Note:** Auto-created by flywheel-doctor.sh — needs human review to populate real weaknesses

## Active Weaknesses

### W1: Bootstrap Weakness — Needs Real Assessment
**Severity:** P2
**Status:** active — auto-created $TODAY

**Evidence:**
GROWTH.md was missing entirely. Agent's real weaknesses have not been assessed yet.

**Root cause:**
Agent was created without a GROWTH.md or the file was lost.

**Fix approach:**
Have a Kai session review the agent's logs and tickets and write real W1/W2/W3 entries.
GROWTHEOF
      FIXES_APPLIED+=("$agent: GROWTH.md bootstrapped — needs human review")
      open_ticket "$agent" "Doctor: auto-bootstrapped GROWTH.md for $agent — needs real weakness assessment" "P1"
    else
      # Check it parses
      local item_count
      item_count=$(python3 -c "
import re
content = open('$growth_file').read()
items = re.findall(r'^### [WE]\d+:', content, re.MULTILINE)
print(len(items))
" 2>/dev/null || echo "0")
      if [[ "$item_count" -eq 0 ]]; then
        log "  ✗ $agent GROWTH.md has no parseable W/E items — possible corruption"
        ISSUES_FOUND+=("$agent: GROWTH.md has 0 parseable W/E items")
        open_ticket "$agent" "Doctor: GROWTH.md for $agent has no parseable weakness items — review needed" "P1"
      else
        log "  ✓ $agent GROWTH.md: $item_count W/E items"
      fi
    fi
  done
}

# ─── Check 3: State machine stuck in same weakness too long ──────────────────
check_stuck_weakness() {
  log_sec "CHECK 3: Stuck weakness detection"
  for agent in "${AGENTS[@]}"; do
    local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
    [[ ! -f "$state_file" ]] && continue

    local failure_count current_weakness last_run
    failure_count=$(python3 -c "import json; print(json.load(open('$state_file')).get('failure_count',0))" 2>/dev/null || echo "0")
    current_weakness=$(python3 -c "import json; print(json.load(open('$state_file')).get('current_weakness','W1'))" 2>/dev/null || echo "W1")
    last_run=$(python3 -c "import json; print(json.load(open('$state_file')).get('last_run',''))" 2>/dev/null || echo "")

    # Check if stuck at MAX_RETRIES on same weakness for > 2 days
    if [[ "$failure_count" -ge 3 ]] && [[ -n "$last_run" ]]; then
      # Calculate days since last meaningful progress
      local days_stuck
      days_stuck=$(python3 -c "
from datetime import datetime, timezone
import sys
try:
    last = '$last_run'
    # Handle offset format
    if last:
        from datetime import datetime
        import re
        # Normalize timezone
        last = re.sub(r'(\+|-)(\d{2})(\d{2})$', r'\1\2:\3', last)
        dt = datetime.fromisoformat(last)
        if dt.tzinfo is None:
            from datetime import timezone
            dt = dt.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        print(max(0, (now - dt).days))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")

      if [[ "$days_stuck" -ge 2 ]]; then
        log "  ✗ $agent stuck on $current_weakness for ${days_stuck}d with failure_count=$failure_count — force-advancing"
        ISSUES_FOUND+=("$agent: stuck on $current_weakness for ${days_stuck}d (failures=$failure_count)")
        # Recovery: force advance to next weakness
        local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
        local next_wid="W1"
        if [[ -f "$growth_file" ]]; then
          next_wid=$(python3 - "$growth_file" "$current_weakness" << 'PYEOF'
import sys, re, json
growth_file = sys.argv[1]
curr = sys.argv[2]
content = open(growth_file).read()
items = re.findall(r'^### ([WE]\d+):', content, re.MULTILINE)
if curr in items:
    idx = items.index(curr)
    remaining = items[idx+1:]
    if remaining:
        print(remaining[0])
    else:
        print(items[0] if items else 'W1')
else:
    print(items[0] if items else 'W1')
PYEOF
)
        fi
        python3 - "$state_file" "$next_wid" "$NOW_MT" << 'PYEOF'
import json, sys
path, next_wid, ts = sys.argv[1:4]
d = json.load(open(path))
d['current_weakness'] = next_wid
d['stage'] = 'research'
d['failure_count'] = 0
d['last_run'] = ts
json.dump(d, open(path, 'w'), indent=2)
PYEOF
        FIXES_APPLIED+=("$agent: force-advanced from stuck $current_weakness → $next_wid")
        open_ticket "$agent" "Doctor: force-advanced $agent from stuck $current_weakness to $next_wid after ${days_stuck}d" "P1"
        log "  ✓ Force-advanced $agent → $next_wid"
      else
        log "  ~ $agent on $current_weakness: failure_count=$failure_count, days=${days_stuck} (monitoring)"
      fi
    fi
  done
}

# ─── Check 4: Research file stale (state says implement but no research file) ─
check_research_implement_mismatch() {
  log_sec "CHECK 4: Research/implement stage mismatch"
  for agent in "${AGENTS[@]}"; do
    local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
    [[ ! -f "$state_file" ]] && continue

    local stage current_weakness
    stage=$(python3 -c "import json; print(json.load(open('$state_file')).get('stage','research'))" 2>/dev/null || echo "research")
    current_weakness=$(python3 -c "import json; print(json.load(open('$state_file')).get('current_weakness','W1'))" 2>/dev/null || echo "W1")

    if [[ "$stage" == "implement" ]]; then
      local research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
      if [[ ! -f "$research_file" ]]; then
        log "  ✗ $agent in 'implement' stage but no research file for today — resetting to research"
        ISSUES_FOUND+=("$agent: implement stage but research file missing for $current_weakness")
        # Recovery: reset stage to research so it can regenerate
        python3 - "$state_file" "$NOW_MT" << 'PYEOF'
import json, sys
path, ts = sys.argv[1:3]
d = json.load(open(path))
d['stage'] = 'research'
d['last_run'] = ts
json.dump(d, open(path, 'w'), indent=2)
PYEOF
        FIXES_APPLIED+=("$agent: reset implement→research (missing research file for $current_weakness)")
        log "  ✓ Reset $agent to research stage"
      else
        log "  ✓ $agent implement stage: research file present"
      fi
    fi
  done
}

# ─── Check 5: Knowledge stagnation ───────────────────────────────────────────
check_knowledge_stagnation() {
  log_sec "CHECK 5: Knowledge stagnation"
  if [[ ! -f "$KNOWLEDGE_MD" ]]; then
    log "  ✗ KNOWLEDGE.md not found"
    ISSUES_FOUND+=("KNOWLEDGE.md missing")
    open_ticket "kai" "Doctor: KNOWLEDGE.md not found — memory system broken" "P0"
    return
  fi

  local days_since_update
  days_since_update=$(python3 - "$KNOWLEDGE_MD" << 'PYEOF'
import os, sys
from datetime import datetime, timezone
path = sys.argv[1]
mtime = os.path.getmtime(path)
dt = datetime.fromtimestamp(mtime, tz=timezone.utc)
now = datetime.now(timezone.utc)
print((now - dt).days)
PYEOF
)
  if [[ "$days_since_update" -ge "$KNOWLEDGE_STALE_DAYS" ]]; then
    log "  ✗ KNOWLEDGE.md not updated in ${days_since_update} days — learning pipeline may be stalled"
    ISSUES_FOUND+=("KNOWLEDGE.md stale: ${days_since_update}d since last update")
    open_ticket "kai" "Doctor: KNOWLEDGE.md stale (${days_since_update}d) — flywheel not persisting knowledge" "P2"
    ESCALATIONS+=("KNOWLEDGE.md stale ${days_since_update}d — investigate persist_knowledge() failures")
  else
    log "  ✓ KNOWLEDGE.md updated ${days_since_update}d ago"
  fi
}

# ─── Check 6: Flywheel log freshness ─────────────────────────────────────────
check_flywheel_running() {
  log_sec "CHECK 6: Flywheel log freshness"
  local si_log="$HYO_ROOT/kai/ledger/self-improve.log"
  if [[ ! -f "$si_log" ]]; then
    log "  ✗ self-improve.log not found — flywheel may never have run"
    ISSUES_FOUND+=("self-improve.log missing — flywheel never ran")
    open_ticket "kai" "Doctor: self-improve.log missing — agent-self-improve.sh has never run" "P1"
    return
  fi

  local hours_since_log
  hours_since_log=$(python3 - "$si_log" << 'PYEOF'
import os, sys
from datetime import datetime, timezone
path = sys.argv[1]
mtime = os.path.getmtime(path)
dt = datetime.fromtimestamp(mtime, tz=timezone.utc)
now = datetime.now(timezone.utc)
print(int((now - dt).total_seconds() / 3600))
PYEOF
)
  if [[ "$hours_since_log" -ge 48 ]]; then
    log "  ✗ self-improve.log not updated in ${hours_since_log}h — flywheel not running"
    ISSUES_FOUND+=("Flywheel log stale: ${hours_since_log}h since last run")
    open_ticket "kai" "Doctor: flywheel not running — log is ${hours_since_log}h old. Check kai-autonomous.sh schedule." "P1"
    ESCALATIONS+=("Flywheel stopped: log ${hours_since_log}h old — check 08:00 MT dispatch in kai-autonomous.sh")
  else
    log "  ✓ Flywheel log updated ${hours_since_log}h ago"
  fi
}

# ─── Check 7: WAI — Weakness Aging Index ─────────────────────────────────────
check_weakness_ages() {
  log_sec "CHECK 7: Weakness aging index (WAI)"
  for agent in "${AGENTS[@]}"; do
    local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
    [[ ! -f "$growth_file" ]] && continue

    python3 - "$growth_file" "$agent" "$TODAY" \
      "$MAX_WEAKNESS_AGE_P0" "$MAX_WEAKNESS_AGE_P1" "$MAX_WEAKNESS_AGE_P2" \
      "$TICKET_SH" "$HYO_ROOT" << 'PYEOF'
import sys, re, json, subprocess
from datetime import datetime, date

growth_file, agent, today_str, max_p0, max_p1, max_p2, ticket_sh, hyo_root = sys.argv[1:9]
max_ages = {'P0': int(max_p0), 'P1': int(max_p1), 'P2': int(max_p2)}
today = date.fromisoformat(today_str)

content = open(growth_file).read()
# Find all W/E items with their severity and auto-created date
pattern = r'### ([WE]\d+): (.+?)\n.*?\*\*Severity:\*\*\s*(\w+).*?\*\*Status:\*\*\s*(.*?)(?=\n)'
blocks = re.findall(pattern, content, re.DOTALL)

# Also look for items by splitting on ### headers
sections = re.split(r'\n(?=### [WE]\d+:)', content)
for section in sections:
    wid_match = re.match(r'### ([WE]\d+): (.+)', section)
    if not wid_match:
        continue
    wid, title = wid_match.group(1), wid_match.group(2)

    # Skip resolved
    if re.search(r'\*\*Status:\*\*.*RESOLVED', section, re.IGNORECASE):
        continue

    sev_match = re.search(r'\*\*Severity:\*\*\s*(\w+)', section)
    severity = sev_match.group(1) if sev_match else 'P2'

    # Try to find creation date from auto-generated status line
    date_match = re.search(r'(?:active|auto-identified|auto-created|injected)[^\d]*(\d{4}-\d{2}-\d{2})', section)
    if not date_match:
        continue  # can't compute age without creation date

    created = date.fromisoformat(date_match.group(1))
    age_days = (today - created).days
    threshold = max_ages.get(severity, 30)

    if age_days > threshold:
        print(f"  WAI ALERT: {agent}/{wid} ({severity}) is {age_days}d old (threshold {threshold}d)")
        # Auto-create ticket
        if ticket_sh and agent:
            subprocess.run([
                "bash", ticket_sh, "create",
                "--agent", agent,
                "--title", f"WAI: {agent}/{wid} ({severity}) stuck for {age_days}d — investigate or rewrite",
                "--priority", "P1" if severity in ('P0','P1') else "P2",
                "--type", "improvement",
                "--created-by", "flywheel-doctor"
            ], env={"HYO_ROOT": hyo_root, "PATH": "/usr/bin:/bin:/usr/local/bin"},
               capture_output=True)
    else:
        print(f"  ✓ {agent}/{wid}: {age_days}d (threshold {threshold}d)")
PYEOF
  done
}

# ─── Kai-specific SICQ (5 role-compliance checks × 20 pts = 100) ─────────────
# Replaces generic flywheel SICQ for Kai — checks executive operating protocol
# Research: Bain DQ, APQC KM, ISG OODA, CLEAR framework, Applied-AI Trust
compute_kai_sicq() {
  local score=0

  # Component 1: Hydration Compliance (HC) — KAI_BRIEF.md modified within 24h
  # Proxy for "Kai read all hydration files this session"
  local brief_age_h
  brief_age_h=$(python3 -c "
import os, time
try:
    age = (time.time() - os.path.getmtime('$HYO_ROOT/KAI_BRIEF.md')) / 3600
    print(int(age))
except:
    print(9999)
" 2>/dev/null || echo "9999")
  if [[ "$brief_age_h" -lt 24 ]]; then
    score=$((score + 20))
    log "  ✓ Kai SICQ HC: KAI_BRIEF.md updated ${brief_age_h}h ago (+20)"
  else
    log "  ✗ Kai SICQ HC: KAI_BRIEF.md stale (${brief_age_h}h) — hydration may be incomplete (+0)"
  fi

  # Component 2: Research Depth Compliance (RDC) — Kai's improvement research has ≥6 external URLs
  local state_file="$HYO_ROOT/agents/kai/self-improve-state.json"
  local kai_weakness="W1"
  [[ -f "$state_file" ]] && kai_weakness=$(python3 -c "import json; print(json.load(open('$state_file')).get('current_weakness','W1'))" 2>/dev/null || echo "W1")
  local kai_research="$HYO_ROOT/agents/kai/research/improvements/${kai_weakness}-${TODAY}.md"
  if [[ -f "$kai_research" ]]; then
    local ext_url_count
    ext_url_count=$(grep -oE 'https?://[^ ]+' "$kai_research" 2>/dev/null | grep -v "hyo\.world" | sort -u | wc -l | tr -d ' ')
    if [[ "$ext_url_count" -ge 6 ]]; then
      score=$((score + 20))
      log "  ✓ Kai SICQ RDC: research has $ext_url_count external URLs (+20)"
    else
      log "  ✗ Kai SICQ RDC: research has $ext_url_count external URLs (need ≥6) (+0)"
    fi
  else
    log "  ✗ Kai SICQ RDC: no research file for $kai_weakness today (+0)"
  fi

  # Component 3: Queue Gate Compliance (QGC) — no copy-paste errors in session-errors.jsonl past 7 days
  local copy_paste_errors=0
  if [[ -f "$HYO_ROOT/kai/ledger/session-errors.jsonl" ]]; then
    copy_paste_errors=$(python3 -c "
import json
from datetime import datetime, timezone, timedelta
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
count = 0
for line in open('$HYO_ROOT/kai/ledger/session-errors.jsonl'):
    try:
        d = json.loads(line.strip())
        cat = d.get('category', '')
        ts = d.get('ts', '')[:10]
        if cat in ('copy-paste', 'skip-verification', 'wrong-path'):
            dt = datetime.fromisoformat(ts).replace(tzinfo=timezone.utc)
            if dt >= cutoff: count += 1
    except: pass
print(count)
" 2>/dev/null || echo "0")
  fi
  if [[ "$copy_paste_errors" -eq 0 ]]; then
    score=$((score + 20))
    log "  ✓ Kai SICQ QGC: 0 queue-violation errors in past 7 days (+20)"
  else
    log "  ✗ Kai SICQ QGC: $copy_paste_errors queue-violation errors in past 7 days (+0)"
  fi

  # Component 4: Dual Memory Write (DMW) — KNOWLEDGE.md modified within 7 days AND KAI_TASKS within 24h
  local knowledge_age_d tasks_age_h
  knowledge_age_d=$(python3 -c "
import os, time
try:
    age = (time.time() - os.path.getmtime('$KNOWLEDGE_MD')) / 86400
    print(int(age))
except:
    print(9999)
" 2>/dev/null || echo "9999")
  tasks_age_h=$(python3 -c "
import os, time
try:
    age = (time.time() - os.path.getmtime('$HYO_ROOT/KAI_TASKS.md')) / 3600
    print(int(age))
except:
    print(9999)
" 2>/dev/null || echo "9999")
  if [[ "$knowledge_age_d" -lt 7 && "$tasks_age_h" -lt 24 ]]; then
    score=$((score + 20))
    log "  ✓ Kai SICQ DMW: KNOWLEDGE.md ${knowledge_age_d}d, KAI_TASKS ${tasks_age_h}h (+20)"
  else
    log "  ✗ Kai SICQ DMW: KNOWLEDGE.md ${knowledge_age_d}d (need <7d), KAI_TASKS ${tasks_age_h}h (need <24h) (+0)"
  fi

  # Component 5: Error Recall Rate (ERR) — no same-category error 3+ times in past 14 days
  local repeated_categories=0
  if [[ -f "$HYO_ROOT/kai/ledger/session-errors.jsonl" ]]; then
    repeated_categories=$(python3 -c "
import json, collections
from datetime import datetime, timezone, timedelta
cutoff = datetime.now(timezone.utc) - timedelta(days=14)
cats = collections.Counter()
for line in open('$HYO_ROOT/kai/ledger/session-errors.jsonl'):
    try:
        d = json.loads(line.strip())
        ts = d.get('ts', '')[:10]
        cat = d.get('category', '')
        if cat:
            dt = datetime.fromisoformat(ts).replace(tzinfo=timezone.utc)
            if dt >= cutoff: cats[cat] += 1
    except: pass
repeated = sum(1 for c, n in cats.items() if n >= 3)
print(repeated)
" 2>/dev/null || echo "0")
  fi
  if [[ "$repeated_categories" -eq 0 ]]; then
    score=$((score + 20))
    log "  ✓ Kai SICQ ERR: no repeated error categories (3+ times) in past 14 days (+20)"
  else
    log "  ✗ Kai SICQ ERR: $repeated_categories error categories repeated 3+ times — no recall (+0)"
  fi

  echo "$score"
}

# ─── Check 8: SICQ quality scoring ───────────────────────────────────────────
compute_sicq() {
  local agent="$1"
  local score=0

  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  [[ ! -f "$state_file" ]] && echo "0" && return

  local weakness_id
  weakness_id=$(python3 -c "import json; print(json.load(open('$state_file')).get('current_weakness','W1'))" 2>/dev/null || echo "W1")

  local research_file="$HYO_ROOT/agents/$agent/research/improvements/${weakness_id}-${TODAY}.md"

  # Component 1: research file written (+20)
  [[ -f "$research_file" ]] && score=$((score + 20))

  # Component 2: research has structured fields (+20)
  if [[ -f "$research_file" ]]; then
    local has_approach has_files has_confidence
    has_approach=$(grep -c "^FIX_APPROACH:" "$research_file" 2>/dev/null || echo "0")
    has_files=$(grep -c "^FILES_TO_CHANGE:" "$research_file" 2>/dev/null || echo "0")
    has_confidence=$(grep -c "^CONFIDENCE: HIGH\|^CONFIDENCE: MEDIUM" "$research_file" 2>/dev/null || echo "0")
    [[ "$has_approach" -gt 0 && "$has_files" -gt 0 && "$has_confidence" -gt 0 ]] && score=$((score + 20))
  fi

  # Component 3: implementation was attempted (state advanced through implement) (+20)
  local cycles
  cycles=$(python3 -c "import json; print(json.load(open('$state_file')).get('cycles',0))" 2>/dev/null || echo "0")
  [[ "$cycles" -gt 0 ]] && score=$((score + 20))

  # Component 4: specific files changed (check FILES_TO_CHANGE vs actual) (+20)
  if [[ -f "$research_file" ]]; then
    local files_changed=0
    local files_to_check
    files_to_check=$(grep "^FILES_TO_CHANGE:" "$research_file" | sed 's/FILES_TO_CHANGE: //' | tr ',' '\n' | sed 's/^ *//;s/ *$//')
    if [[ -n "$files_to_check" ]]; then
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local full_path="$HYO_ROOT/$f"
        [[ -f "$full_path" && "$full_path" -nt "$state_file" ]] && files_changed=$((files_changed + 1))
      done <<< "$files_to_check"
      [[ "$files_changed" -gt 0 ]] && score=$((score + 20))
    fi
  fi

  # Component 5: KNOWLEDGE.md has entry for this weakness today (+20)
  local knowledge_updated
  knowledge_updated=$(grep -c "$weakness_id" "$KNOWLEDGE_MD" 2>/dev/null || echo "0")
  [[ "$knowledge_updated" -gt 0 ]] && score=$((score + 20))

  echo "$score"
}

check_sicq_scores() {
  log_sec "CHECK 8: SICQ quality scores"
  local sicq_report_path="$HYO_ROOT/kai/ledger/sicq-latest.json"
  local scores_json="{"

  for agent in "${AGENTS[@]}"; do
    local score
    # Kai uses role-specific SICQ; all other agents use generic flywheel SICQ
    if [[ "$agent" == "kai" ]]; then
      score=$(compute_kai_sicq)
      log "  SICQ kai (exec-compliance): $score/100"
    else
      score=$(compute_sicq "$agent")
      log "  SICQ $agent: $score/100"
    fi

    if [[ "$score" -le "$SICQ_LOW_THRESHOLD" ]]; then
      ISSUES_FOUND+=("$agent SICQ critically low: $score/100")
      open_ticket "$agent" "Doctor: SICQ critically low for $agent ($score/100) — self-improve cycle degraded" "P1"
    elif [[ "$score" -le "$SICQ_WARN_THRESHOLD" ]]; then
      log "  WARN: $agent SICQ below warning threshold ($score < $SICQ_WARN_THRESHOLD)"
    fi

    scores_json+="\"$agent\":$score,"
  done

  scores_json="${scores_json%,}}"
  python3 - "$sicq_report_path" "$scores_json" "$NOW_MT" "$TODAY" << 'PYEOF'
import json, sys
path, scores_str, ts, today = sys.argv[1:5]
scores = json.loads(scores_str)
# Load existing history
existing = {}
try:
    existing = json.load(open(path))
except:
    pass
history = existing.get('history', [])
history.append({"date": today, "scores": scores})
history = history[-30:]  # keep 30 days rolling
report = {"last_computed": ts, "today": today, "scores": scores, "history": history}
json.dump(report, open(path, 'w'), indent=2)
print(f"SICQ report written: {path}")
PYEOF

  # ── Write scores into feed.json agents block (both paths) ─────────────────
  # This is what populates the per-agent score cards on HQ site daily.
  python3 - "$HYO_ROOT" "$scores_json" "$NOW_MT" << 'SCORE_PYEOF'
import json, sys, os

root, scores_str, ts = sys.argv[1:4]
sicq_scores = json.loads(scores_str)

# Load OMP scores if available
omp_scores = {}
omp_path = os.path.join(root, 'kai/ledger/omp-summary.json')
if os.path.exists(omp_path):
    try:
        omp_data = json.load(open(omp_path)).get('agents', {})
        for a, d in omp_data.items():
            omp_scores[a] = int(d.get('overall', 0))
    except Exception:
        pass

sicq_labels = {100:'Excellent',80:'Good',60:'Fair',40:'Low',0:'Critical'}
def slabel(s): return next(sicq_labels[k] for k in sorted(sicq_labels.keys(), reverse=True) if s >= k)
omp_labels = {80:'Excellent',70:'Good',60:'Adequate',40:'Needs Improvement',0:'Critical'}
def olabel(s): return next(omp_labels[k] for k in sorted(omp_labels.keys(), reverse=True) if s >= k)

paths = [
    os.path.join(root, 'agents/sam/website/data/feed.json'),
    os.path.join(root, 'website/data/feed.json'),
]
for feed_path in paths:
    if not os.path.exists(feed_path): continue
    try:
        with open(feed_path) as f:
            feed = json.load(f)
        updated = 0
        for agent_id, agent_data in feed.get('agents', {}).items():
            scores = {}
            if agent_id in sicq_scores:
                s = int(sicq_scores[agent_id])
                scores['sicq'] = {'score': s, 'label': slabel(s), 'min': 60,
                                  'status': 'critical' if s <= 40 else ('warn' if s <= 60 else 'ok')}
            if agent_id in omp_scores:
                s = int(omp_scores[agent_id])
                scores['omp'] = {'score': s, 'label': olabel(s), 'min': 70,
                                 'status': 'critical' if s <= 40 else ('warn' if s <= 70 else 'ok')}
            if scores:
                agent_data['scores'] = scores
                updated += 1
        feed['agents'] = feed.get('agents', {})
        with open(feed_path, 'w') as f:
            json.dump(feed, f, indent=2)
        print(f"Updated {updated} agent score cards in {feed_path}")
    except Exception as e:
        print(f"ERROR updating {feed_path}: {e}", file=sys.stderr)
SCORE_PYEOF
}

# ─── Check 10b: OMP score threshold enforcement (#80) ────────────────────────
# When any agent OMP < 70 → P1 ticket. Below 50 → P0 + Hyo inbox.
# This is the structural gate: low OMP blocks "healthy" status in the report.
OMP_WARN_THRESHOLD=70
OMP_CRITICAL_THRESHOLD=50

check_omp_scores() {
  log_sec "CHECK 10b: OMP score threshold enforcement"
  local omp_path="$HYO_ROOT/kai/ledger/omp-summary.json"

  if [[ ! -f "$omp_path" ]]; then
    log "  WARN: omp-summary.json not found — skipping OMP threshold check"
    return
  fi

  python3 - "$omp_path" "$OMP_WARN_THRESHOLD" "$OMP_CRITICAL_THRESHOLD" << 'PYEOF'
import json, sys

omp_path, warn_t, crit_t = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    data = json.load(open(omp_path))
    agents = data.get('agents', {})
except Exception as e:
    print(f"ERROR reading omp-summary.json: {e}")
    sys.exit(0)

for agent, d in agents.items():
    score = int(d.get('overall', 0))
    if score < crit_t:
        print(f"CRITICAL:{agent}:{score}")
    elif score < warn_t:
        print(f"WARN:{agent}:{score}")
    else:
        print(f"OK:{agent}:{score}")
PYEOF

  local omp_output
  omp_output=$(python3 - "$omp_path" "$OMP_WARN_THRESHOLD" "$OMP_CRITICAL_THRESHOLD" << 'PYEOF'
import json, sys
omp_path, warn_t, crit_t = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    data = json.load(open(omp_path))
    agents = data.get('agents', {})
except Exception as e:
    sys.exit(0)
for agent, d in agents.items():
    score = int(d.get('overall', 0))
    if score < crit_t:
        print(f"CRITICAL:{agent}:{score}")
    elif score < warn_t:
        print(f"WARN:{agent}:{score}")
PYEOF
  )

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local level agent score
    level=$(echo "$line" | cut -d: -f1)
    agent=$(echo "$line" | cut -d: -f2)
    score=$(echo "$line" | cut -d: -f3)

    if [[ "$level" == "CRITICAL" ]]; then
      ISSUES_FOUND+=("$agent OMP critically low: $score/100 (min $OMP_CRITICAL_THRESHOLD)")
      ESCALATIONS+=("$agent OMP=$score — below critical threshold ($OMP_CRITICAL_THRESHOLD). Output quality severely degraded.")
      open_ticket "$agent" "Doctor: OMP critically low for $agent ($score/100, min $OMP_WARN_THRESHOLD) — output quality degraded" "P0"
      notify_hyo "OMP Critical: $agent ($score/100)" \
        "$agent OMP score is $score — below critical threshold ($OMP_CRITICAL_THRESHOLD). Output quality is severely degraded. Review $agent runner and improvement cycle immediately."
      log "  CRITICAL: $agent OMP=$score — P0 ticket opened, Hyo notified"
    elif [[ "$level" == "WARN" ]]; then
      ISSUES_FOUND+=("$agent OMP below minimum: $score/100 (min $OMP_WARN_THRESHOLD)")
      open_ticket "$agent" "Doctor: OMP below minimum for $agent ($score/100, min $OMP_WARN_THRESHOLD) — improve output quality" "P1"
      log "  WARN: $agent OMP=$score — P1 ticket opened"
    fi
  done <<< "$omp_output"

  if [[ -z "$omp_output" ]]; then
    log "  ✓ All agent OMP scores above thresholds"
  fi
}

# ─── Check 11: Protocol/JSON alignment for all HQ published products ──────────
check_protocol_json_alignment() {
  log_sec "CHECK 11: Protocol/JSON alignment (schema registry)"

  local SCHEMA_DIR="$HYO_ROOT/kai/schemas"
  local REGISTRY="$SCHEMA_DIR/registry.json"

  if [[ ! -f "$REGISTRY" ]]; then
    ISSUES_FOUND+=("Schema registry missing: $REGISTRY — create kai/schemas/ and registry.json")
    return
  fi

  python3 - "$HYO_ROOT" "$SCHEMA_DIR" "$REGISTRY" << 'PYEOF'
import json, os, sys

root, schema_dir, registry_path = sys.argv[1:4]

with open(registry_path) as f:
    registry = json.load(f)

registered_types = set(registry.get("types", {}).keys())
issues = []
fixes = []

# 1. Check every registered type has a schema file AND a protocol
for rtype, protocol_path in registry.get("types", {}).items():
    schema_file = os.path.join(schema_dir, rtype.replace("-", "_") + ".schema.json")
    if not os.path.exists(schema_file):
        issues.append(f"Schema file missing for '{rtype}': {schema_file}")
    full_protocol = os.path.join(root, protocol_path)
    if not os.path.exists(full_protocol):
        issues.append(f"Protocol file missing for '{rtype}': {protocol_path}")

# 2. Check feed.json for types NOT in registry
feed_path = os.path.join(root, "agents/sam/website/data/feed.json")
if os.path.exists(feed_path):
    with open(feed_path) as f:
        feed = json.load(f)
    feed_types = set(r.get("type") for r in feed.get("reports", []) if r.get("type"))
    unregistered = feed_types - registered_types
    if unregistered:
        issues.append(f"Feed types without schema/protocol: {', '.join(sorted(unregistered))}")

# 3. Check each agent has self-improve-state.json
for agent in ["nel", "sam", "ra", "aether", "dex", "ant", "kai"]:
    state_path = os.path.join(root, f"agents/{agent}/self-improve-state.json")
    if not os.path.exists(state_path):
        issues.append(f"Missing self-improve-state.json for agent: {agent}")

# 4. Check each agent has GROWTH.md
for agent in ["nel", "sam", "ra", "aether", "dex", "ant", "kai"]:
    growth_path = os.path.join(root, f"agents/{agent}/GROWTH.md")
    if not os.path.exists(growth_path):
        issues.append(f"Missing GROWTH.md for agent: {agent}")

if issues:
    print(f"ISSUES:{len(issues)}")
    for i in issues:
        print(f"  - {i}")
else:
    print("OK:all types have protocol+schema, all agents have state+growth")
PYEOF

  local RESULT
  RESULT=$(python3 - "$HYO_ROOT" "$SCHEMA_DIR" "$REGISTRY" << 'PYEOF'
import json, os, sys
root, schema_dir, registry_path = sys.argv[1:4]
with open(registry_path) as f:
    registry = json.load(f)
registered_types = set(registry.get("types", {}).keys())
issues = []
for rtype, protocol_path in registry.get("types", {}).items():
    schema_file = os.path.join(schema_dir, rtype.replace("-", "_") + ".schema.json")
    if not os.path.exists(schema_file): issues.append(f"Schema missing: {rtype}")
    if not os.path.exists(os.path.join(root, protocol_path)): issues.append(f"Protocol missing: {rtype}")
feed_path = os.path.join(root, "agents/sam/website/data/feed.json")
if os.path.exists(feed_path):
    with open(feed_path) as f:
        feed = json.load(f)
    unregistered = set(r.get("type") for r in feed.get("reports", []) if r.get("type")) - registered_types
    if unregistered: issues.append(f"Unregistered types in feed: {','.join(sorted(unregistered))}")
for agent in ["nel","sam","ra","aether","dex","ant"]:
    if not os.path.exists(os.path.join(root, f"agents/{agent}/self-improve-state.json")):
        issues.append(f"Missing state: {agent}")
    if not os.path.exists(os.path.join(root, f"agents/{agent}/GROWTH.md")):
        issues.append(f"Missing GROWTH.md: {agent}")
print(len(issues))
for i in issues: print(i)
PYEOF
  2>/dev/null)

  local N_ISSUES
  N_ISSUES=$(echo "$RESULT" | head -1)
  if [[ "$N_ISSUES" -gt 0 ]] 2>/dev/null; then
    while IFS= read -r issue_line; do
      [[ -z "$issue_line" ]] && continue
      ISSUES_FOUND+=("Protocol/JSON: $issue_line")
      open_ticket "kai" "Protocol/JSON alignment: $issue_line" "P1"
    done <<< "$(echo "$RESULT" | tail -n +2)"
    log "  ✗ CHECK 11: $N_ISSUES alignment issues found"
  else
    log "  ✓ CHECK 11: All types have protocol+schema, all agents have state+growth"
  fi
}

# ─── Check 9: No resolutions in N days ───────────────────────────────────────
check_resolution_stagnation() {
  log_sec "CHECK 9: Resolution stagnation (${NO_RESOLVE_DAYS}d window)"

  # Check evolution.jsonl files for recent resolutions
  local any_resolved=0
  for agent in "${AGENTS[@]}"; do
    local evo_file="$HYO_ROOT/agents/$agent/evolution.jsonl"
    [[ ! -f "$evo_file" ]] && continue

    local recent_resolve
    recent_resolve=$(python3 - "$evo_file" "$NO_RESOLVE_DAYS" << 'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
evo_file, days_str = sys.argv[1:3]
cutoff = datetime.now(timezone.utc) - timedelta(days=int(days_str))
count = 0
for line in open(evo_file):
    try:
        e = json.loads(line.strip())
        if e.get('type') == 'weakness_resolved':
            import re
            ts = e.get('ts', '')
            ts = re.sub(r'(\+|-)(\d{2})(\d{2})$', r'\1\2:\3', ts)
            dt = datetime.fromisoformat(ts)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            if dt > cutoff:
                count += 1
    except:
        pass
print(count)
PYEOF
)
    [[ "$recent_resolve" -gt 0 ]] && any_resolved=$((any_resolved + recent_resolve))
  done

  if [[ "$any_resolved" -eq 0 ]]; then
    log "  ✗ No weaknesses resolved in ${NO_RESOLVE_DAYS} days across any agent"
    ISSUES_FOUND+=("No weaknesses resolved in ${NO_RESOLVE_DAYS}d — flywheel not completing cycles")
    open_ticket "kai" "Doctor: flywheel has not resolved any weakness in ${NO_RESOLVE_DAYS}d — check verify and implement stages" "P1"
    ESCALATIONS+=("Flywheel stagnation: 0 resolutions in ${NO_RESOLVE_DAYS}d")
  else
    log "  ✓ $any_resolved resolution(s) in the last ${NO_RESOLVE_DAYS} days"
  fi
}

# ─── Generate final report + escalate if needed ───────────────────────────────
generate_report_and_escalate() {
  log_sec "DOCTOR REPORT"
  log "  Issues found: ${#ISSUES_FOUND[@]}"
  log "  Fixes applied: ${#FIXES_APPLIED[@]}"
  log "  Escalations: ${#ESCALATIONS[@]}"

  # Write machine-readable report
  python3 - "$REPORT" "$NOW_MT" "$TODAY" << PYEOF
import json, sys
path, ts, today = sys.argv[1:4]
report = {
    "ts": ts,
    "date": today,
    "issues_found": $(python3 -c "import json; print(json.dumps(${ISSUES_FOUND[@]+\"${ISSUES_FOUND[@]}\"}))" 2>/dev/null || echo "[]"),
    "fixes_applied": $(python3 -c "import json; print(json.dumps(${FIXES_APPLIED[@]+\"${FIXES_APPLIED[@]}\"}))" 2>/dev/null || echo "[]"),
    "escalations": $(python3 -c "import json; print(json.dumps(${ESCALATIONS[@]+\"${ESCALATIONS[@]}\"}))" 2>/dev/null || echo "[]"),
    "status": "clean" if not $(echo "${ISSUES_FOUND[@]+${#ISSUES_FOUND[@]}}" | tr -d ' ') else "issues_detected"
}
json.dump(report, open(path, 'w'), indent=2)
PYEOF

  # Build report using bash arrays directly (avoid embedding bash arrays in python heredoc)
  python3 << REPORT_PYEOF
import json

issues = $(printf '%s\n' "${ISSUES_FOUND[@]+"${ISSUES_FOUND[@]}"}" | python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" 2>/dev/null || echo "[]")
fixes  = $(printf '%s\n' "${FIXES_APPLIED[@]+"${FIXES_APPLIED[@]}"}" | python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" 2>/dev/null || echo "[]")
escs   = $(printf '%s\n' "${ESCALATIONS[@]+"${ESCALATIONS[@]}"}" | python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" 2>/dev/null || echo "[]")

score_issues = [i for i in issues if 'SICQ' in i or 'OMP' in i]
if score_issues:
    status = "score_degraded"   # hard block: report cannot claim "healthy"
elif issues:
    status = "issues_detected"
else:
    status = "clean"

report = {
    "ts": "$NOW_MT",
    "date": "$TODAY",
    "issues_found": issues,
    "fixes_applied": fixes,
    "escalations": escs,
    "status": status,
    "score_gate": "FAILED" if score_issues else "PASSED",
    "score_issues": score_issues
}
with open("$REPORT", "w") as f:
    json.dump(report, f, indent=2)
print(f"Doctor report written — status: {status}")
REPORT_PYEOF

  # Dispatch report to Kai
  if [[ -f "$DISPATCH_SH" ]]; then
    local summary_msg="Doctor ran: ${#ISSUES_FOUND[@]} issues, ${#FIXES_APPLIED[@]} fixes, ${#ESCALATIONS[@]} escalations"
    bash "$DISPATCH_SH" report "flywheel-doctor-${TODAY}" "completed" "$summary_msg" 2>/dev/null || true
  fi

  # If escalations exist, write to Hyo inbox (Kai cannot handle these alone)
  if [[ "${#ESCALATIONS[@]}" -gt 0 ]]; then
    local esc_body="Flywheel doctor found issues requiring attention:$(printf '\n- %s' "${ESCALATIONS[@]}")"
    notify_hyo "Flywheel Doctor: ${#ESCALATIONS[@]} issue(s) need review" "$esc_body"
    log "  → Wrote ${#ESCALATIONS[@]} escalation(s) to Hyo inbox"
  fi
}

# ─── Run all checks ───────────────────────────────────────────────────────────
log_sec "FLYWHEEL DOCTOR START — $TODAY"
log "  Checking ${#AGENTS[@]} agents: ${AGENTS[*]}"

check_state_integrity
check_growth_md
check_stuck_weakness
check_research_implement_mismatch
check_knowledge_stagnation
check_flywheel_running
check_weakness_ages
check_sicq_scores
check_omp_scores
check_resolution_stagnation
check_protocol_json_alignment
generate_report_and_escalate

log_sec "FLYWHEEL DOCTOR COMPLETE"
log "  Issues: ${#ISSUES_FOUND[@]} | Fixes: ${#FIXES_APPLIED[@]} | Escalations: ${#ESCALATIONS[@]}"
exit 0
