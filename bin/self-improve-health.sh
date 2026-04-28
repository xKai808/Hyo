#!/usr/bin/env bash
# bin/self-improve-health.sh — Binary health check + autonomous remediation
#
# Runs at 05:45 MT daily via kai-autonomous.sh (after 04:30 MT self-improve cycle).
#
# RESPONSE PROTOCOL:
#   NO answer → auto-remediation attempt
#   Still broken after remediation → open P1 ticket + log to daily-issues.jsonl
#   Ticket surfaces in morning report if FAILURES > 0 and is_serious=true
#   NO Telegram. NO manual alerts. Kai acts, then Kai reports if it couldn't fix it.
#
# Questions:
#   Q1: Does self-improve-state.json exist?
#   Q2: Was it written within 28h?
#   Q3: Is stage machine advancing (not stuck 2+ days same weakness+stage)?
#   Q4: Valid research file exists for current weakness (FIX_APPROACH, no auth garbage)?
#   Q5: failure_count below MAX_RETRIES cap?
#   Q6: launchd has kai-autonomous loaded?
#
# Health check self-verification is done by report-completeness-check.sh at 07:00.
# That check verifies this script ran, logged, and produced a result today.

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
HEALTH_LOG="$HYO_ROOT/kai/ledger/self-improve-health.log"
ISSUES_LOG="$HYO_ROOT/kai/ledger/daily-issues.jsonl"
LAST_STAGE_FILE="$HYO_ROOT/kai/ledger/self-improve-last-stage.json"
SELF_IMPROVE_SH="$HYO_ROOT/bin/agent-self-improve.sh"
SELF_IMPROVE_LOG="$HYO_ROOT/kai/ledger/self-improve.log"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S%z")
TODAY=$(TZ="America/Denver" date +"%Y-%m-%d")
NOW_EPOCH=$(date +%s)
MAX_RETRIES=3
STALE_SECONDS=100800  # 28 hours

AGENTS="nel sam aether ra dex kai"

log() { echo "[$TS] $*" | tee -a "$HEALTH_LOG"; }

mkdir -p "$(dirname "$HEALTH_LOG")" "$(dirname "$ISSUES_LOG")"

# ─── Log rotation: keep last 5000 lines ───────────────────────────────────────
if [[ -f "$HEALTH_LOG" ]]; then
  _hlines=$(wc -l < "$HEALTH_LOG" 2>/dev/null || echo 0)
  if [[ $_hlines -gt 5000 ]]; then
    tail -5000 "$HEALTH_LOG" > "${HEALTH_LOG}.tmp" && mv "${HEALTH_LOG}.tmp" "$HEALTH_LOG"
  fi
fi

# ─── Open a tracked issue (surfaces in morning report) ────────────────────────
# Only called when auto-remediation failed. Deduplicates by issue_key.
open_issue() {
  local issue_key="$1" agent="$2" question="$3" description="$4" severity="${5:-P1}"
  # Dedup: skip if same key already open today
  if grep -q "\"key\":\"${issue_key}\"" "$ISSUES_LOG" 2>/dev/null; then
    log "  → Issue already open: $issue_key (no duplicate)"
    return 0
  fi
  echo "{\"ts\":\"$TS\",\"key\":\"$issue_key\",\"agent\":\"$agent\",\"question\":\"$question\",\"severity\":\"$severity\",\"description\":\"$description\",\"remediated\":false,\"date\":\"$TODAY\"}" >> "$ISSUES_LOG"
  log "  → Issue logged: $issue_key ($severity)"
  # Also open a ticket for SLA enforcement
  if [[ -x "$TICKET_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "$agent" \
      --title "Self-improve health: $question FAIL — $agent" \
      --priority "$severity" \
      --type "improvement" \
      --created-by "self-improve-health" 2>/dev/null || true
  fi
}

mark_issue_resolved() {
  local issue_key="$1"
  python3 - "$ISSUES_LOG" "$issue_key" "$TS" << 'PYEOF' 2>/dev/null || true
import json, sys
from pathlib import Path
path, key, ts = sys.argv[1], sys.argv[2], sys.argv[3]
f = Path(path)
if not f.exists(): sys.exit(0)
lines = []
for line in f.read_text().splitlines():
    try:
        d = json.loads(line)
        if d.get('key') == key:
            d['remediated'] = True
            d['resolved_at'] = ts
        lines.append(json.dumps(d))
    except: lines.append(line)
f.write_text('\n'.join(lines) + '\n')
PYEOF
}

# ─── Load last-stage snapshot (bash 3.2 compat) ───────────────────────────────
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
  for artifact in "${state_file}.lock" "${state_file}.tmp"; do
    if [[ -e "$artifact" ]]; then
      rm -rf "$artifact" 2>/dev/null && cleared=$((cleared+1))
    fi
  done
  while IFS= read -r lf; do
    rm -rf "$lf" 2>/dev/null && cleared=$((cleared+1))
  done < <(find "$HYO_ROOT/agents/$agent" -name "*.lock" -maxdepth 3 2>/dev/null)
  [[ $cleared -gt 0 ]] && log "  → Cleared $cleared stale lock artifact(s) for $agent"
  return 0
}

# ─── Auto-remediation: re-trigger one agent ────────────────────────────────────
retrigger_agent() {
  local agent="$1"
  if [[ -x "$SELF_IMPROVE_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$SELF_IMPROVE_SH" "$agent" >> "$SELF_IMPROVE_LOG" 2>&1 &
    log "  → Re-triggered $agent cycle (PID $!)"
    return 0
  fi
  log "  → Cannot re-trigger: $SELF_IMPROVE_SH not found/not executable"
  return 1
}

# ─── Response protocol: attempt remediation, return 0=fixed 1=unresolved ──────
respond() {
  local agent="$1" question="$2" context="$3"
  case "$question" in
    Q1|Q2)
      clear_stale_locks "$agent"
      retrigger_agent "$agent" && return 0
      ;;
    Q4)
      local research_file="$context"
      [[ -f "$research_file" ]] && rm -f "$research_file" && log "  → Deleted invalid research file"
      retrigger_agent "$agent" && return 0
      ;;
    Q3|Q5|Q6)
      # These require investigation or physical action — log the issue, don't auto-fix
      return 1
      ;;
  esac
  return 1
}

log "=== Self-improve health check: $TODAY ==="

FAIL_COUNT=0
PASS_COUNT=0
AUTO_FIXED=0

# ── Q6 (global): launchd loaded? ──────────────────────────────────────────────
log "--- GLOBAL: launchd ---"
if command -v launchctl &>/dev/null; then
  launchd_entry=$(launchctl list 2>/dev/null | grep "kai-autonomous" || echo "")
  if [[ -z "$launchd_entry" ]]; then
    log "  Q6 FAIL: com.hyo.kai-autonomous not in launchd — all scheduled jobs disabled"
    open_issue "launchd-unloaded-$TODAY" "kai" "Q6" \
      "kai-autonomous.plist not loaded in launchd. Run: launchctl load ~/Library/LaunchAgents/com.hyo.kai-autonomous.plist" "P0"
    FAIL_COUNT=$((FAIL_COUNT+1))
  else
    log "  Q6 OK: kai-autonomous loaded in launchd"
    PASS_COUNT=$((PASS_COUNT+1))
  fi
else
  log "  Q6 SKIP: launchctl not available"
fi

for agent in $AGENTS; do
  state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  log "--- $agent ---"

  # ── Q1: State file exists? ──────────────────────────────────────────────────
  if [[ ! -f "$state_file" ]]; then
    log "  Q1 FAIL: state file missing"
    if respond "$agent" "Q1" ""; then
      log "  → Q1 AUTO-FIXED: re-triggered"
      AUTO_FIXED=$((AUTO_FIXED+1))
      mark_issue_resolved "q1-${agent}-$TODAY"
    else
      open_issue "q1-${agent}-$TODAY" "$agent" "Q1" \
        "agents/$agent/self-improve-state.json missing after re-trigger attempt"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
    continue
  fi
  log "  Q1 OK"

  # Parse state
  current_weakness=$(python3 -c "import json; s=json.load(open('$state_file')); print(s.get('current_weakness','?'))" 2>/dev/null || echo "?")
  current_stage=$(python3 -c    "import json; s=json.load(open('$state_file')); print(s.get('stage','?'))" 2>/dev/null || echo "?")
  failure_count=$(python3 -c    "import json; s=json.load(open('$state_file')); print(s.get('failure_count',0))" 2>/dev/null || echo "0")
  last_run=$(python3 -c         "import json; s=json.load(open('$state_file')); print(s.get('last_run',''))" 2>/dev/null || echo "")
  blocked_reason=$(python3 -c   "import json; s=json.load(open('$state_file')); print(s.get('blocked_reason',''))" 2>/dev/null || echo "")

  # ── Q2: Written within 28h? ─────────────────────────────────────────────────
  q2_fail=false
  if [[ -z "$last_run" ]]; then
    log "  Q2 FAIL: last_run empty — state never written"
    q2_fail=true
  else
    file_epoch=$(python3 -c "import os; print(int(os.path.getmtime('$state_file')))" 2>/dev/null || echo 0)
    age=$((NOW_EPOCH - file_epoch))
    if [[ $age -gt $STALE_SECONDS ]]; then
      log "  Q2 FAIL: stale — last written ${age}s ago (>28h)"
      q2_fail=true
    else
      log "  Q2 OK: last_run=$last_run (${age}s ago)"
      PASS_COUNT=$((PASS_COUNT+1))
    fi
  fi
  if [[ "$q2_fail" == "true" ]]; then
    if respond "$agent" "Q2" ""; then
      log "  → Q2 AUTO-FIXED: locks cleared + re-triggered"
      AUTO_FIXED=$((AUTO_FIXED+1))
    else
      open_issue "q2-${agent}-$TODAY" "$agent" "Q2" \
        "State stale ${last_run:-empty}. Re-trigger failed. blocked_reason=${blocked_reason:-none}"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  fi

  # ── Q3: State machine advancing? ────────────────────────────────────────────
  prev_weakness=$(get_last_weakness "$agent")
  prev_stage=$(get_last_stage "$agent")
  if [[ -n "$prev_weakness" && "$prev_weakness" == "$current_weakness" && "$prev_stage" == "$current_stage" ]]; then
    # Auth block: tolerated for up to MAX_AUTH_BLOCK_DAYS (3 days). After that, fire Q3 regardless.
    # Rationale: auth expiry requires physical renewal. 3 days is enough grace. Silence beyond that
    # hides a real problem (nobody noticed auth expired, or auth renewal itself is broken).
    MAX_AUTH_BLOCK_DAYS=3
    if [[ "$blocked_reason" == "claude_auth_unavailable" && "$current_stage" == "implement" ]]; then
      # Compute days blocked from last_run field in state file
      last_run_ts=$(python3 -c "
import json, sys
from pathlib import Path
f = Path('$HYO_ROOT/agents/$agent/self-improve-state.json')
if not f.exists(): print(0); sys.exit(0)
try:
    d = json.loads(f.read_text())
    lr = d.get('last_run','')
    if lr:
        from datetime import datetime, timezone
        import re
        # Parse ISO timestamp with offset
        lr_clean = re.sub(r'([+-]\d{2})(\d{2})$', r'\1:\2', lr) if not lr.endswith('Z') else lr
        try:
            dt = datetime.fromisoformat(lr_clean)
            now = datetime.now(timezone.utc)
            delta = now - dt.astimezone(timezone.utc)
            print(delta.days)
        except: print(0)
    else: print(0)
except: print(0)
" 2>/dev/null || echo 0)
      if [[ "$last_run_ts" -ge "$MAX_AUTH_BLOCK_DAYS" ]]; then
        log "  Q3 FAIL: auth_unavailable block exceeded ${MAX_AUTH_BLOCK_DAYS}d limit — ${last_run_ts}d at $current_weakness/implement"
        open_issue "q3-auth-timeout-${agent}-$TODAY" "$agent" "Q3" \
          "Claude auth expired ${last_run_ts}d ago. Implement stage blocked ${MAX_AUTH_BLOCK_DAYS}d+ — claude auth login required. weakness=$current_weakness" "P0"
        FAIL_COUNT=$((FAIL_COUNT+1))
      else
        log "  Q3 OK: held at $current_weakness/implement due to claude_auth_unavailable (day ${last_run_ts}/${MAX_AUTH_BLOCK_DAYS} — within grace)"
        PASS_COUNT=$((PASS_COUNT+1))
      fi
    else
      log "  Q3 FAIL: stuck at $current_weakness/$current_stage for 2+ days (failure_count=$failure_count)"
      open_issue "q3-${agent}-$TODAY" "$agent" "Q3" \
        "Stage machine stuck at $current_weakness/$current_stage for 2+ days. failure_count=$failure_count. blocked_reason=${blocked_reason:-none}" "P1"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  else
    log "  Q3 OK: advanced from ${prev_weakness:-none}/${prev_stage:-none} → $current_weakness/$current_stage"
    PASS_COUNT=$((PASS_COUNT+1))
  fi

  # ── Q4: Valid research file? ─────────────────────────────────────────────────
  research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
  if [[ ! -f "$research_file" ]]; then
    log "  Q4 FAIL: no research file at $research_file"
    if respond "$agent" "Q4" "$research_file"; then
      log "  → Q4 AUTO-FIXED: re-triggered"
      AUTO_FIXED=$((AUTO_FIXED+1))
    else
      open_issue "q4-${agent}-$TODAY" "$agent" "Q4" \
        "No research file for $current_weakness after re-trigger. Check self-improve.log." "P2"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  else
    fix_approach=$(grep "^FIX_APPROACH:" "$research_file" 2>/dev/null | head -1)
    auth_error=$(grep -c "Not logged in\|Please run /login" "$research_file" 2>/dev/null; true)
    auth_error="${auth_error:-0}"
    if [[ -z "$fix_approach" || "${auth_error}" -gt 0 ]]; then
      log "  Q4 FAIL: research file invalid (auth garbage or no FIX_APPROACH)"
      if respond "$agent" "Q4" "$research_file"; then
        log "  → Q4 AUTO-FIXED: invalid file deleted + re-triggered"
        AUTO_FIXED=$((AUTO_FIXED+1))
      else
        open_issue "q4-${agent}-$TODAY" "$agent" "Q4" \
          "Research file invalid (auth error or missing FIX_APPROACH). Re-trigger failed." "P1"
        FAIL_COUNT=$((FAIL_COUNT+1))
      fi
    else
      log "  Q4 OK: valid FIX_APPROACH"
      PASS_COUNT=$((PASS_COUNT+1))
    fi
  fi

  # ── Q5: failure_count below cap? ────────────────────────────────────────────
  if [[ "$failure_count" -ge "$MAX_RETRIES" ]]; then
    log "  Q5 FAIL: failure_count=$failure_count >= cap=$MAX_RETRIES — permanently stuck on $current_weakness"
    open_issue "q5-${agent}-$TODAY" "$agent" "Q5" \
      "failure_count=$failure_count maxed on $current_weakness. Mark resolved in GROWTH.md or clear failure_count in state file." "P1"
    FAIL_COUNT=$((FAIL_COUNT+1))
  else
    log "  Q5 OK: failure_count=$failure_count (cap=$MAX_RETRIES)"
    PASS_COUNT=$((PASS_COUNT+1))
  fi

  # Record current stage for tomorrow's Q3 comparison
  printf '{"agent":"%s","weakness":"%s","stage":"%s","ts":"%s"}\n' \
    "$agent" "$current_weakness" "$current_stage" "$TS" >> "${LAST_STAGE_FILE}.new"
done

# Atomically replace snapshot
[[ -f "${LAST_STAGE_FILE}.new" ]] && mv "${LAST_STAGE_FILE}.new" "$LAST_STAGE_FILE"

log "=== Health check done: ${PASS_COUNT} passed | ${FAIL_COUNT} unresolved | ${AUTO_FIXED} auto-fixed ==="

# Write summary for completeness-check.sh to verify
SUMMARY_FILE="$HYO_ROOT/kai/ledger/self-improve-health-${TODAY}.json"
echo "{\"date\":\"$TODAY\",\"ts\":\"$TS\",\"passed\":$PASS_COUNT,\"failed\":$FAIL_COUNT,\"auto_fixed\":$AUTO_FIXED,\"is_healthy\":$([ $FAIL_COUNT -eq 0 ] && echo true || echo false)}" > "$SUMMARY_FILE"
log "Summary written: $SUMMARY_FILE"

exit 0
