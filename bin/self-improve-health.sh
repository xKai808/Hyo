#!/usr/bin/env bash
# bin/self-improve-health.sh — Binary question-based health check + auto-remediation
#
# Runs after the 04:30 MT self-improve cycle (scheduled at 05:45 MT via kai-autonomous.sh).
# Asks 5 yes/no questions per agent. Any NO → auto-remediation attempt → P1 alert if unresolved.
#
# RESPONSE PROTOCOL (not just a check):
#   NO → classify failure type
#         → known pattern? auto-remediate (clear stale locks, re-trigger cycle, delete bad file)
#         → still failing? escalate via Telegram + hyo-inbox.jsonl P1
#         → log remediation outcome to health.log
#
# Questions (each must be YES for the agent to be healthy):
#   Q1: Does self-improve-state.json exist?
#   Q2: Was it written within the last 28 hours?
#   Q3: Is the stage machine NOT stuck (same weakness+stage for 2+ consecutive days)?
#   Q4: Does a valid research file exist for current weakness (has FIX_APPROACH field)?
#   Q5: Is failure_count below the MAX_RETRIES cap (not permanently stuck)?
#   Q6 (global): Is launchd running com.hyo.kai-autonomous (the trigger for everything)?
#
# Root cause this check was built for:
#   lock files (files, not dirs) blocked save_state() for 6 consecutive days.
#   No alert fired. Cycle reported "complete" while writing nothing.
#   This check would have caught it on day 1 — and auto-remediated the lock files.

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
HEALTH_LOG="$HYO_ROOT/kai/ledger/self-improve-health.log"
LAST_STAGE_FILE="$HYO_ROOT/kai/ledger/self-improve-last-stage.json"
SELF_IMPROVE_SH="$HYO_ROOT/bin/agent-self-improve.sh"
SELF_IMPROVE_LOG="$HYO_ROOT/kai/ledger/self-improve.log"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S%z")
TODAY=$(TZ="America/Denver" date +"%Y-%m-%d")
NOW_EPOCH=$(date +%s)
MAX_RETRIES=3
STALE_SECONDS=100800  # 28 hours

AGENTS="nel sam aether ra dex kai"

log() { echo "[$TS] $*" | tee -a "$HEALTH_LOG"; }

mkdir -p "$(dirname "$HEALTH_LOG")"

# ─── Log rotation: keep last 5000 lines ──────────────────────────────────────
if [[ -f "$HEALTH_LOG" ]]; then
  _hlines=$(wc -l < "$HEALTH_LOG" 2>/dev/null || echo 0)
  if [[ $_hlines -gt 5000 ]]; then
    tail -5000 "$HEALTH_LOG" > "${HEALTH_LOG}.tmp" && mv "${HEALTH_LOG}.tmp" "$HEALTH_LOG"
  fi
fi

# ─── Telegram alert ────────────────────────────────────────────────────────────
send_telegram() {
  local msg="$1"
  local token chat_id
  token=$(cat "$HYO_ROOT/agents/nel/security/.telegram_token" 2>/dev/null || echo "")
  chat_id=$(cat "$HYO_ROOT/agents/nel/security/.telegram_chat_id" 2>/dev/null || echo "")
  if [[ -n "$token" && -n "$chat_id" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
      -d "chat_id=${chat_id}" -d "text=${msg}" >/dev/null 2>&1 || true
  fi
}

# ─── Write P1 inbox entry ─────────────────────────────────────────────────────
alert_inbox() {
  local subject="$1" body="$2" priority="${3:-P1}"
  printf '{"ts":"%s","from":"self-improve-health","priority":"%s","status":"unread","subject":"%s","body":"%s"}\n' \
    "$TS" "$priority" "$subject" "$body" >> "$INBOX"
}

# ─── Load last-stage snapshot via Python (bash 3.2 compat — no declare -A) ────
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

# ─── Auto-remediation: clear stale lock files ─────────────────────────────────
clear_stale_locks() {
  local agent="$1"
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  local cleared=0
  for lock in "${state_file}.lock" "${state_file}.tmp"; do
    if [[ -e "$lock" ]]; then
      rm -rf "$lock" 2>/dev/null && log "  → REMEDIATED: removed stale $lock" && cleared=$((cleared+1))
    fi
  done
  # Also scan for any .lock files in the agent directory
  while IFS= read -r lf; do
    rm -rf "$lf" 2>/dev/null && log "  → REMEDIATED: removed $lf" && cleared=$((cleared+1))
  done < <(find "$HYO_ROOT/agents/$agent" -name "*.lock" -maxdepth 3 2>/dev/null)
  return $((cleared > 0 ? 0 : 1))
}

# ─── Auto-remediation: re-trigger self-improve for one agent ──────────────────
retrigger_agent() {
  local agent="$1"
  if [[ -x "$SELF_IMPROVE_SH" ]]; then
    log "  → REMEDIATION: re-triggering $agent cycle in background"
    HYO_ROOT="$HYO_ROOT" bash "$SELF_IMPROVE_SH" "$agent" >> "$SELF_IMPROVE_LOG" 2>&1 &
    log "  → Cycle re-triggered (PID $!)"
    return 0
  else
    log "  → Cannot re-trigger: $SELF_IMPROVE_SH not found"
    return 1
  fi
}

# ─── RESPONSE PROTOCOL ────────────────────────────────────────────────────────
# Called when a Q-answer is NO. Tries auto-remediation before alerting.
# Returns 0 if remediated (no alert needed), 1 if unresolved (alert fires).
respond_to_failure() {
  local agent="$1" question="$2" context="$3"
  local remediated=0

  case "$question" in
    Q1)
      # State file missing — clear locks and re-trigger
      clear_stale_locks "$agent" && remediated=$((remediated+1))
      if retrigger_agent "$agent"; then
        log "  → Q1 REMEDIATED: re-triggered $agent (state file will be created)"
        return 0
      fi
      ;;
    Q2)
      # Stale — check for lock files first, then re-trigger
      local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
      if clear_stale_locks "$agent"; then
        remediated=$((remediated+1))
        log "  → Q2 PARTIAL: stale locks cleared — cycle may have been blocked"
      fi
      if retrigger_agent "$agent"; then
        log "  → Q2 REMEDIATED: $agent cycle re-triggered (state will update within 10min)"
        return 0  # Re-triggered — alert deferred (next run will re-check)
      fi
      ;;
    Q3)
      # Stuck state machine — not an auto-fixable pattern; alert immediately
      log "  → Q3 NO AUTO-REMEDIATION: state machine stuck requires investigation"
      ;;
    Q4)
      # Invalid/missing research file — delete and re-trigger
      local research_file="$context"
      if [[ -f "$research_file" ]]; then
        rm -f "$research_file" && log "  → Q4 REMEDIATED: deleted invalid research file, re-triggering"
      fi
      if retrigger_agent "$agent"; then
        log "  → Q4 REMEDIATED: research will be regenerated"
        return 0
      fi
      ;;
    Q5)
      # failure_count maxed — cannot auto-fix; requires Hyo to clear state
      log "  → Q5 NO AUTO-REMEDIATION: failure_count maxed, manual GROWTH.md update required"
      ;;
  esac

  return 1  # Unresolved — caller fires alert
}

log "=== Self-improve health check + remediation: $TODAY ==="

# ─── Q6 (GLOBAL): Is launchd running the autonomous daemon? ──────────────────
log "--- GLOBAL: launchd check ---"
LAUNCHD_OK=true
if command -v launchctl &>/dev/null; then
  launchd_status=$(launchctl list 2>/dev/null | grep "kai-autonomous" | head -1 || echo "")
  if [[ -z "$launchd_status" ]]; then
    log "  Q6 NO: com.hyo.kai-autonomous NOT in launchd — entire cascade (self-improve + health check) will NOT fire autonomously"
    alert_inbox \
      "CRITICAL: kai-autonomous.plist NOT loaded — autonomous ops disabled" \
      "Q6 FAIL: launchctl list shows no kai-autonomous entry. All scheduled jobs (self-improve 04:30, health check 05:45, morning report, etc.) will not run until reloaded. Run: launchctl load ~/Library/LaunchAgents/com.hyo.kai-autonomous.plist"
    send_telegram "🚨 Kai Health P0: kai-autonomous.plist NOT loaded in launchd. ALL scheduled autonomous jobs are disabled. Hyo must reload: launchctl load ~/Library/LaunchAgents/com.hyo.kai-autonomous.plist"
    LAUNCHD_OK=false
  else
    # Check if it has a PID (running) vs just loaded
    launchd_pid=$(echo "$launchd_status" | awk '{print $1}')
    if [[ "$launchd_pid" == "-" ]]; then
      log "  Q6 WARN: kai-autonomous loaded but not currently running (expected — it's a periodic job, not a daemon)"
    else
      log "  Q6 YES: kai-autonomous loaded (pid=$launchd_pid)"
    fi
  fi
else
  log "  Q6 SKIP: launchctl not available (not macOS or not in PATH)"
fi

FAIL_COUNT=0
PASS_COUNT=0
REMEDIATED_COUNT=0
NEW_STAGE_ENTRIES=""

for agent in $AGENTS; do
    state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
    log "--- $agent ---"

    # ── Q1: State file exists? ────────────────────────────────────────────────
    if [[ ! -f "$state_file" ]]; then
        log "  Q1 NO: self-improve-state.json missing for $agent"
        if respond_to_failure "$agent" "Q1" ""; then
          log "  Q1 AUTO-REMEDIATED"
          REMEDIATED_COUNT=$((REMEDIATED_COUNT+1))
        else
          alert_inbox \
            "Self-improve MISSING state file: $agent" \
            "Q1 FAIL: agents/$agent/self-improve-state.json does not exist. Cycle may not have run. Check self-improve.log."
          send_telegram "⚠️ Kai Health P1 [$agent]: Q1 FAIL — state file missing. Attempted re-trigger."
          FAIL_COUNT=$((FAIL_COUNT+1))
        fi
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
        if respond_to_failure "$agent" "Q2" ""; then
          log "  Q2 AUTO-REMEDIATED: stale locks cleared and cycle re-triggered"
          REMEDIATED_COUNT=$((REMEDIATED_COUNT+1))
        else
          alert_inbox \
            "Self-improve NEVER RAN for $agent" \
            "Q2 FAIL: last_run is empty. save_state() never succeeded. Check for stale .lock files: find ~/Documents/Projects/Hyo/agents/$agent -name *.lock"
          send_telegram "⚠️ Kai Health P1 [$agent]: Q2 FAIL — last_run empty. Re-trigger attempted."
          FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    else
        file_epoch=$(python3 -c "import os; print(int(os.path.getmtime('$state_file')))" 2>/dev/null || echo 0)
        age=$((NOW_EPOCH - file_epoch))
        if [[ $age -gt $STALE_SECONDS ]]; then
            log "  Q2 NO: last_run=${last_run}, file age=${age}s (>28h) — cycle missed"
            if respond_to_failure "$agent" "Q2" ""; then
              log "  Q2 AUTO-REMEDIATED: cycle re-triggered for $agent"
              REMEDIATED_COUNT=$((REMEDIATED_COUNT+1))
            else
              alert_inbox \
                "Self-improve STALE for $agent — $((age/3600))h since last run" \
                "Q2 FAIL: self-improve-state.json last written ${age}s ago (threshold: 28h). Re-trigger attempted but failed. Check: tail -50 kai/ledger/self-improve.log"
              send_telegram "🚨 Kai Health P1 [$agent]: Q2 FAIL — stale $((age/3600))h. Re-trigger attempted."
              FAIL_COUNT=$((FAIL_COUNT+1))
            fi
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
        respond_to_failure "$agent" "Q3" "" || true  # No auto-fix; alert always fires
        alert_inbox \
          "Self-improve STUCK for $agent — $current_weakness/$current_stage unchanged" \
          "Q3 FAIL: $agent has been at weakness=$current_weakness stage=$current_stage for 2+ consecutive days. State machine not advancing. Check failure_count ($failure_count) and research file content."
        send_telegram "⚠️ Kai Health P1 [$agent]: Q3 FAIL — stuck at $current_weakness/$current_stage for 2+ days. failure_count=$failure_count"
        FAIL_COUNT=$((FAIL_COUNT+1))
    else
        log "  Q3 YES: advanced (was ${prev_weakness:-none}/${prev_stage:-none} → now ${current_weakness}/${current_stage})"
        PASS_COUNT=$((PASS_COUNT+1))
    fi

    # ── Q4: Valid research file for current weakness? ─────────────────────────
    research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
    if [[ ! -f "$research_file" ]]; then
        log "  Q4 NO: no research file at $research_file"
        if respond_to_failure "$agent" "Q4" "$research_file"; then
          log "  Q4 AUTO-REMEDIATED: research will be regenerated"
          REMEDIATED_COUNT=$((REMEDIATED_COUNT+1))
        else
          alert_inbox \
            "Self-improve NO research file for $agent/$current_weakness" \
            "Q4 FAIL: expected $research_file but file is missing. Research phase may have failed. Re-trigger attempted." \
            "P2"
          FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    else
        fix_approach=$(grep "^FIX_APPROACH:" "$research_file" 2>/dev/null | head -1)
        auth_error=$(grep -c "Not logged in\|Please run /login" "$research_file" 2>/dev/null; true)
        auth_error="${auth_error:-0}"
        if [[ -z "$fix_approach" || "${auth_error}" -gt 0 ]]; then
            log "  Q4 NO: research file exists but content is invalid (fix_approach empty or auth garbage)"
            if respond_to_failure "$agent" "Q4" "$research_file"; then
              log "  Q4 AUTO-REMEDIATED: invalid research file deleted, cycle re-triggered"
              REMEDIATED_COUNT=$((REMEDIATED_COUNT+1))
            else
              alert_inbox \
                "Self-improve INVALID research content for $agent/$current_weakness" \
                "Q4 FAIL: $research_file lacks FIX_APPROACH or contains auth error. Deletion and re-trigger attempted."
              send_telegram "⚠️ Kai Health P1 [$agent]: Q4 FAIL — research file invalid (auth garbage or missing FIX_APPROACH). Auto-remediation attempted."
              FAIL_COUNT=$((FAIL_COUNT+1))
            fi
        else
            log "  Q4 YES: valid research file with FIX_APPROACH"
            PASS_COUNT=$((PASS_COUNT+1))
        fi
    fi

    # ── Q5: failure_count below cap? ──────────────────────────────────────────
    if [[ "$failure_count" -ge "$MAX_RETRIES" ]]; then
        log "  Q5 NO: failure_count=${failure_count} >= MAX_RETRIES=${MAX_RETRIES} — permanently stuck"
        respond_to_failure "$agent" "Q5" "" || true  # No auto-fix
        alert_inbox \
          "Self-improve MAXED failures for $agent/$current_weakness" \
          "Q5 FAIL: failure_count=$failure_count hit the cap. Agent gave up on this weakness. Hyo must update GROWTH.md to mark $current_weakness resolved or clear failure_count in state file."
        send_telegram "⚠️ Kai Health P1 [$agent]: Q5 FAIL — failure_count=$failure_count maxed. Manual GROWTH.md update required to unblock."
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

log "=== Health check complete: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${REMEDIATED_COUNT} auto-remediated ==="

if [[ $FAIL_COUNT -eq 0 && $REMEDIATED_COUNT -eq 0 ]]; then
    log "✓ All agents healthy"
elif [[ $FAIL_COUNT -eq 0 ]]; then
    log "✓ All failures remediated automatically (${REMEDIATED_COUNT} fixes applied)"
    send_telegram "✅ Kai Health: ${REMEDIATED_COUNT} issue(s) detected and AUTO-REMEDIATED. No unresolved failures. Check self-improve-health.log for details."
else
    log "✗ ${FAIL_COUNT} failure(s) unresolved — alerts sent, ${REMEDIATED_COUNT} auto-remediated"
fi
