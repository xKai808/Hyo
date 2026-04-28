#!/usr/bin/env bash
# bin/self-improve-health.sh — Binary question-based health check for self-improvement cycle
#
# Runs after the 04:30 MT self-improve cycle (scheduled at 06:00 MT via kai-autonomous.sh).
# Asks 5 yes/no questions per agent. Any NO → P1 alert to hyo-inbox.jsonl.
#
# Questions (each must be YES for the agent to be healthy):
#   Q1: Does self-improve-state.json exist?
#   Q2: Was it written within the last 28 hours?
#   Q3: Is the stage machine NOT stuck (same weakness+stage for 2+ consecutive days)?
#   Q4: Does a valid research file exist for current weakness (has FIX_APPROACH field)?
#   Q5: Is failure_count below the MAX_RETRIES cap (not permanently stuck)?
#
# Root cause this check was built for:
#   lock files (files, not dirs) blocked save_state() for 6 consecutive days.
#   No alert fired. Cycle reported "complete" while writing nothing.
#   This check would have caught it on day 1.

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
HEALTH_LOG="$HYO_ROOT/kai/ledger/self-improve-health.log"
LAST_STAGE_FILE="$HYO_ROOT/kai/ledger/self-improve-last-stage.json"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S-06:00")
TODAY=$(TZ="America/Denver" date +"%Y-%m-%d")
NOW_EPOCH=$(date +%s)
MAX_RETRIES=3
STALE_SECONDS=100800  # 28 hours

AGENTS="nel sam aether ra dex kai"

log() { echo "[$TS] $*" | tee -a "$HEALTH_LOG"; }

mkdir -p "$(dirname "$HEALTH_LOG")"

log "=== Self-improve health check: $TODAY ==="

# Load last-stage snapshot via Python (bash 3.2 compat — no declare -A)
get_last_weakness() { python3 -c "
import json, sys
from pathlib import Path
f = Path('$LAST_STAGE_FILE')
if not f.exists(): print(''); sys.exit(0)
for line in f.read_text().splitlines():
    try:
        d = json.loads(line)
        if d.get('agent') == sys.argv[1]: print(d.get('weakness','')); sys.exit(0)
    except: pass
print('')
" "$1" 2>/dev/null; }

get_last_stage() { python3 -c "
import json, sys
from pathlib import Path
f = Path('$LAST_STAGE_FILE')
if not f.exists(): print(''); sys.exit(0)
for line in f.read_text().splitlines():
    try:
        d = json.loads(line)
        if d.get('agent') == sys.argv[1]: print(d.get('stage','')); sys.exit(0)
    except: pass
print('')
" "$1" 2>/dev/null; }

FAIL_COUNT=0
PASS_COUNT=0
NEW_STAGE_ENTRIES=""

for agent in $AGENTS; do
    state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
    log "--- $agent ---"

    # ── Q1: State file exists? ────────────────────────────────────────────────
    if [[ ! -f "$state_file" ]]; then
        log "  Q1 NO: self-improve-state.json missing for $agent"
        printf '{"ts":"%s","from":"self-improve-health","priority":"P1","status":"unread","subject":"Self-improve MISSING state file: %s","body":"Q1 FAIL: agents/%s/self-improve-state.json does not exist. Cycle may not have run. Check self-improve.log."}\n' \
            "$TS" "$agent" "$agent" >> "$INBOX"
        FAIL_COUNT=$((FAIL_COUNT+1))
        continue
    fi
    log "  Q1 YES: state file exists"

    # Parse state
    current_weakness=$(python3 -c "import json; s=json.load(open('$state_file')); print(s.get('current_weakness','?'))" 2>/dev/null || echo "?")
    current_stage=$(python3 -c    "import json; s=json.load(open('$state_file')); print(s.get('stage','?'))" 2>/dev/null || echo "?")
    failure_count=$(python3 -c    "import json; s=json.load(open('$state_file')); print(s.get('failure_count',0))" 2>/dev/null || echo "0")
    last_run=$(python3 -c         "import json; s=json.load(open('$state_file')); print(s.get('last_run',''))" 2>/dev/null || echo "")

    # ── Q2: Written within 28h? ───────────────────────────────────────────────
    if [[ -z "$last_run" ]]; then
        log "  Q2 NO: last_run is empty — cycle has never run or state was never saved"
        printf '{"ts":"%s","from":"self-improve-health","priority":"P1","status":"unread","subject":"Self-improve NEVER RAN for %s","body":"Q2 FAIL: last_run is empty. The cycle fired but save_state() never succeeded, or it has never been triggered. Check for stale .lock files: find ~/Documents/Projects/Hyo/agents/%s -name *.lock"}\n' \
            "$TS" "$agent" "$agent" >> "$INBOX"
        FAIL_COUNT=$((FAIL_COUNT+1))
    else
        file_epoch=$(python3 -c "import os; print(int(os.path.getmtime('$state_file')))" 2>/dev/null || echo 0)
        age=$((NOW_EPOCH - file_epoch))
        if [[ $age -gt $STALE_SECONDS ]]; then
            log "  Q2 NO: last_run=${last_run}, file age=${age}s (>28h) — cycle missed"
            printf '{"ts":"%s","from":"self-improve-health","priority":"P1","status":"unread","subject":"Self-improve STALE for %s — %dh since last run","body":"Q2 FAIL: self-improve-state.json last written %ds ago (threshold: 28h). Cycle at 04:30 MT may have failed silently. Check: tail -50 kai/ledger/self-improve.log"}\n' \
                "$TS" "$agent" "$((age/3600))" "$age" >> "$INBOX"
            FAIL_COUNT=$((FAIL_COUNT+1))
        else
            log "  Q2 YES: last_run=${last_run} (${age}s ago)"
            PASS_COUNT=$((PASS_COUNT+1))
        fi
    fi

    # ── Q3: State machine advanced (not same weakness+stage 2 consecutive days)? ──
    prev_weakness=$(get_last_weakness "$agent")
    prev_stage=$(get_last_stage "$agent")
    if [[ -n "$prev_weakness" && "$prev_weakness" == "$current_weakness" && "$prev_stage" == "$current_stage" ]]; then
        log "  Q3 NO: stuck at $current_weakness/$current_stage (same as yesterday)"
        printf '{"ts":"%s","from":"self-improve-health","priority":"P1","status":"unread","subject":"Self-improve STUCK for %s — %s/%s unchanged","body":"Q3 FAIL: %s has been at weakness=%s stage=%s for 2+ consecutive days. State machine is not advancing. Check failure_count and research file content."}\n' \
            "$TS" "$agent" "$current_weakness" "$current_stage" "$agent" "$current_weakness" "$current_stage" >> "$INBOX"
        FAIL_COUNT=$((FAIL_COUNT+1))
    else
        log "  Q3 YES: advanced (was ${prev_weakness:-none}/${prev_stage:-none} → now ${current_weakness}/${current_stage})"
        PASS_COUNT=$((PASS_COUNT+1))
    fi

    # ── Q4: Valid research file for current weakness? ─────────────────────────
    research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
    if [[ ! -f "$research_file" ]]; then
        log "  Q4 NO: no research file at $research_file"
        printf '{"ts":"%s","from":"self-improve-health","priority":"P2","status":"unread","subject":"Self-improve NO research file for %s/%s","body":"Q4 FAIL: expected %s but file is missing. Research phase may have failed. Check self-improve.log for GATE messages."}\n' \
            "$TS" "$agent" "$current_weakness" "$research_file" >> "$INBOX"
        FAIL_COUNT=$((FAIL_COUNT+1))
    else
        fix_approach=$(grep "^FIX_APPROACH:" "$research_file" 2>/dev/null | head -1)
        auth_error=$(grep -c "Not logged in\|Please run /login" "$research_file" 2>/dev/null; true)
        auth_error="${auth_error:-0}"
        if [[ -z "$fix_approach" || "${auth_error}" -gt 0 ]]; then
            log "  Q4 NO: research file exists but content is invalid (fix_approach empty or auth garbage)"
            printf '{"ts":"%s","from":"self-improve-health","priority":"P1","status":"unread","subject":"Self-improve INVALID research content for %s/%s","body":"Q4 FAIL: %s exists but lacks FIX_APPROACH field or contains auth error text. Python fallback may have failed."}\n' \
                "$TS" "$agent" "$current_weakness" "$research_file" >> "$INBOX"
            FAIL_COUNT=$((FAIL_COUNT+1))
        else
            log "  Q4 YES: valid research file with FIX_APPROACH"
            PASS_COUNT=$((PASS_COUNT+1))
        fi
    fi

    # ── Q5: failure_count below cap? ──────────────────────────────────────────
    if [[ "$failure_count" -ge "$MAX_RETRIES" ]]; then
        log "  Q5 NO: failure_count=${failure_count} >= MAX_RETRIES=${MAX_RETRIES} — permanently stuck"
        printf '{"ts":"%s","from":"self-improve-health","priority":"P1","status":"unread","subject":"Self-improve MAXED failures for %s/%s","body":"Q5 FAIL: failure_count=%d has hit the cap. The agent gave up on this weakness. Hyo must manually update GROWTH.md to mark %s resolved or clear failure_count in the state file."}\n' \
            "$TS" "$agent" "$current_weakness" "$failure_count" "$current_weakness" >> "$INBOX"
        FAIL_COUNT=$((FAIL_COUNT+1))
    else
        log "  Q5 YES: failure_count=${failure_count} (cap: ${MAX_RETRIES})"
        PASS_COUNT=$((PASS_COUNT+1))
    fi

    # Record current stage for tomorrow's Q3 check
    printf '{"agent":"%s","weakness":"%s","stage":"%s","ts":"%s"}\n' \
        "$agent" "$current_weakness" "$current_stage" "$TS" >> "${LAST_STAGE_FILE}.new"
done

# Atomically replace last-stage snapshot
[[ -f "${LAST_STAGE_FILE}.new" ]] && mv "${LAST_STAGE_FILE}.new" "$LAST_STAGE_FILE"

log "=== Health check complete: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="

if [[ $FAIL_COUNT -eq 0 ]]; then
    log "✓ All agents healthy"
else
    log "✗ ${FAIL_COUNT} question(s) answered NO — alerts sent to hyo-inbox.jsonl"
fi
