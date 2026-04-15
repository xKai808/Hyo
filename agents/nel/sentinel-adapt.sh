#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/agents/nel/sentinel-adapt.sh
#
# sentinel-adapt.sh — Adaptive escalation and diagnostic system for Nel's sentinel.
# When a check fails N consecutive times, automatically runs deeper diagnostics
# specific to that check type to help identify root cause.
#
# Input: sentinel.state.json (state from previous sentinel run)
# Input: findings from current sentinel run (passed via stdin or args)
# Output: sentinel-diagnostics-YYYY-MM-DD.md with investigation results
# Output: updates sentinel-state.json with escalation levels
# Output: JSON with escalation actions taken (printed to stdout)

set -euo pipefail

# ---- Setup ------------------------------------------------------------------
# Try multiple paths for ROOT to handle different deployment contexts
# Priority: HYO_ROOT env var, then /mnt path, then Documents/Projects
if [[ -n "${HYO_ROOT:-}" && -d "${HYO_ROOT}" && -f "${HYO_ROOT}/agents/nel/memory/sentinel.state.json" ]]; then
  ROOT="$HYO_ROOT"
elif [[ -f "/sessions/sharp-gracious-franklin/mnt/Hyo/agents/nel/memory/sentinel.state.json" ]]; then
  ROOT="/sessions/sharp-gracious-franklin/mnt/Hyo"
elif [[ -d "$HOME/mnt/Hyo" && -f "$HOME/mnt/Hyo/agents/nel/memory/sentinel.state.json" ]]; then
  ROOT="$HOME/mnt/Hyo"
elif [[ -f "$HOME/Documents/Projects/Hyo/agents/nel/memory/sentinel.state.json" ]]; then
  ROOT="$HOME/Documents/Projects/Hyo"
else
  ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
fi

LOGS="$ROOT/agents/nel/logs"
MEMORY="$ROOT/agents/nel/memory"
STATE="$MEMORY/sentinel.state.json"
TODAY=$(date +%Y-%m-%d)
NOW_ISO=$(date -u +%FT%TZ)
DIAGNOSTICS="$LOGS/sentinel-diagnostics-$TODAY.md"
ESCALATION_STATE="$MEMORY/sentinel-escalation.json"

mkdir -p "$LOGS" "$MEMORY"

# ---- Escalation State Initialization ----------------------------------------
if [[ ! -f "$ESCALATION_STATE" ]]; then
  cat > "$ESCALATION_STATE" <<'JSON'
{
  "schema": "hyo.sentinel.escalation.v1",
  "lastUpdated": null,
  "checks": {}
}
JSON
fi

# ---- Helper: Parse check results from sentinel.state.json -------------------
# This function reads the current state and determines which checks are failing
# and how many consecutive times they've failed
get_consecutive_failures() {
  local check_id="$1"
  python3 - "$STATE" "$check_id" <<'PYEOF'
import json, sys
try:
  with open(sys.argv[1]) as f:
    state = json.load(f)
  check_id = sys.argv[2]
  # Find all issues matching this check_id
  for issue_id, issue_data in state.get("knownIssues", {}).items():
    if issue_data.get("check_id") == check_id and issue_data.get("status") == "open":
      print(issue_data.get("daysFailing", 1))
      sys.exit(0)
  print("0")
  sys.exit(0)
except Exception as e:
  print("0", file=sys.stderr)
  sys.exit(1)
PYEOF
}

# ---- Helper: Determine escalation level based on consecutive failures --------
get_escalation_level() {
  local consecutive_fails="$1"
  if [[ $consecutive_fails -le 2 ]]; then
    echo "0"
  elif [[ $consecutive_fails -le 4 ]]; then
    echo "1"
  elif [[ $consecutive_fails -le 9 ]]; then
    echo "2"
  else
    echo "3"
  fi
}

# ---- Diagnostics: api-health-green ------------------------------------------
diagnose_api_health() {
  local endpoint="https://www.hyo.world/api/health"
  echo "### API Health Diagnostics" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
  echo "**Endpoint:** \`$endpoint\`" >> "$DIAGNOSTICS"
  echo "**Run time:** $NOW_ISO" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"

  # Test 1: Basic connectivity and SSL
  echo "#### Test 1: SSL Certificate and Connectivity" >> "$DIAGNOSTICS"
  if timeout 10 curl -sI --cacert /dev/null "$endpoint" 2>&1 | head -20 >> "$DIAGNOSTICS" 2>&1; then
    echo "✓ SSL handshake succeeded" >> "$DIAGNOSTICS"
  else
    echo "✗ SSL handshake failed — check certificate validity" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 2: Verbose curl with full headers
  echo "#### Test 2: Full Request/Response (Verbose)" >> "$DIAGNOSTICS"
  if timeout 10 curl -v "$endpoint" 2>&1 | head -50 >> "$DIAGNOSTICS" 2>&1; then
    echo "Request completed" >> "$DIAGNOSTICS"
  else
    echo "Request timed out or failed" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 3: Response time measurement
  echo "#### Test 3: Response Time" >> "$DIAGNOSTICS"
  if command -v time >/dev/null 2>&1; then
    (time timeout 10 curl -sf "$endpoint" >/dev/null) 2>&1 | grep -E 'real|user|sys' >> "$DIAGNOSTICS" 2>&1 || echo "Timing failed" >> "$DIAGNOSTICS"
  else
    echo "time command not available" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 4: Check for founder token in environment/config
  echo "#### Test 4: Founder Token Status" >> "$DIAGNOSTICS"
  if [[ -f "$ROOT/.secrets/founder.token" ]]; then
    echo "✓ Founder token file exists at \`$ROOT/.secrets/founder.token\`" >> "$DIAGNOSTICS"
    echo "Token file mode: $(stat -c %a "$ROOT/.secrets/founder.token" 2>/dev/null || stat -f %Lp "$ROOT/.secrets/founder.token" 2>/dev/null || echo 'unknown')" >> "$DIAGNOSTICS"
    if grep -q "^sk-" "$ROOT/.secrets/founder.token" 2>/dev/null; then
      echo "✓ Token appears to be a real API key (starts with sk-)" >> "$DIAGNOSTICS"
    else
      echo "⚠ Token does not appear to be a real API key format" >> "$DIAGNOSTICS"
    fi
  else
    echo "✗ Founder token file NOT FOUND at \`$ROOT/.secrets/founder.token\`" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 5: Check Vercel env vars
  echo "#### Test 5: Vercel Environment Check" >> "$DIAGNOSTICS"
  if [[ -n "${HYO_FOUNDER_TOKEN:-}" ]]; then
    echo "✓ HYO_FOUNDER_TOKEN is set in environment" >> "$DIAGNOSTICS"
  else
    echo "✗ HYO_FOUNDER_TOKEN is NOT set in environment" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"
}

# ---- Diagnostics: aurora-ran-today ------------------------------------------
diagnose_aurora_ran_today() {
  echo "### Aurora Ran Today Diagnostics" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
  echo "**Expected newsletter:** \`$ROOT/newsletters/$TODAY.md\`" >> "$DIAGNOSTICS"
  echo "**Run time:** $NOW_ISO" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"

  # Test 1: Newsletter output file
  echo "#### Test 1: Newsletter Output File" >> "$DIAGNOSTICS"
  if [[ -f "$ROOT/newsletters/$TODAY.md" ]]; then
    SIZE=$(wc -c < "$ROOT/newsletters/$TODAY.md" | tr -d ' ')
    echo "✓ File exists, size: $SIZE bytes" >> "$DIAGNOSTICS"
    if [[ $SIZE -gt 500 ]]; then
      echo "✓ File size > 500 bytes (passes sentinel threshold)" >> "$DIAGNOSTICS"
    else
      echo "⚠ File size <= 500 bytes (fails sentinel threshold)" >> "$DIAGNOSTICS"
    fi
    echo "" >> "$DIAGNOSTICS"
    echo "**First 30 lines:**" >> "$DIAGNOSTICS"
    head -30 "$ROOT/newsletters/$TODAY.md" >> "$DIAGNOSTICS" 2>&1 || echo "(could not read)" >> "$DIAGNOSTICS"
  else
    echo "✗ Newsletter file does NOT exist" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 2: Aurora daemon status (if launchd available)
  echo "#### Test 2: Aurora Daemon Status" >> "$DIAGNOSTICS"
  if command -v launchctl >/dev/null 2>&1; then
    if launchctl list 2>/dev/null | grep -q "hyo.aurora"; then
      echo "✓ Aurora daemon is registered (com.hyo.aurora or similar)" >> "$DIAGNOSTICS"
      launchctl list 2>/dev/null | grep "hyo.aurora" >> "$DIAGNOSTICS" 2>&1 || true
    else
      echo "✗ Aurora daemon is NOT registered in launchctl" >> "$DIAGNOSTICS"
    fi
  else
    echo "⚠ launchctl not available (non-macOS?)" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 3: Most recent aurora log
  echo "#### Test 3: Most Recent Aurora Log" >> "$DIAGNOSTICS"
  LAST_AURORA=$(find "$LOGS" -name "aurora-*.log" -o -name "aurora-*.md" 2>/dev/null | sort -r | head -1)
  if [[ -n "$LAST_AURORA" ]]; then
    echo "Latest log: \`$(basename "$LAST_AURORA")\`" >> "$DIAGNOSTICS"
    AGE_SEC=$(( $(date +%s) - $(stat -c %Y "$LAST_AURORA" 2>/dev/null || stat -f %m "$LAST_AURORA" 2>/dev/null || echo 0) ))
    HOURS=$(( AGE_SEC / 3600 ))
    echo "Age: $HOURS hours" >> "$DIAGNOSTICS"
    echo "" >> "$DIAGNOSTICS"
    echo "**Last 20 lines of log:**" >> "$DIAGNOSTICS"
    tail -20 "$LAST_AURORA" >> "$DIAGNOSTICS" 2>&1 || echo "(could not read)" >> "$DIAGNOSTICS"
  else
    echo "✗ No aurora logs found" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 4: Check gather.py last run
  echo "#### Test 4: Gather Phase (Data Collection)" >> "$DIAGNOSTICS"
  GATHER_PY="$ROOT/agents/ra/pipeline/gather.py"
  if [[ -f "$GATHER_PY" ]]; then
    echo "✓ gather.py exists" >> "$DIAGNOSTICS"
    GATHER_MTIME=$(stat -c %Y "$GATHER_PY" 2>/dev/null || stat -f %m "$GATHER_PY" 2>/dev/null || echo 0)
    GATHER_AGE=$(( $(date +%s) - GATHER_MTIME ))
    echo "Last modified: $GATHER_AGE seconds ago" >> "$DIAGNOSTICS"
  else
    echo "✗ gather.py NOT FOUND at \`$GATHER_PY\`" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 5: Pipeline directory health
  echo "#### Test 5: Pipeline Directory" >> "$DIAGNOSTICS"
  PIPELINE_DIR="$ROOT/agents/ra/pipeline"
  if [[ -d "$PIPELINE_DIR" ]]; then
    echo "✓ Pipeline directory exists" >> "$DIAGNOSTICS"
    echo "Contents:" >> "$DIAGNOSTICS"
    ls -lah "$PIPELINE_DIR" 2>/dev/null | tail -10 >> "$DIAGNOSTICS" || echo "(could not list)" >> "$DIAGNOSTICS"
  else
    echo "✗ Pipeline directory NOT FOUND at \`$PIPELINE_DIR\`" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"
}

# ---- Diagnostics: scheduled-tasks-fired -------------------------------------
diagnose_scheduled_tasks() {
  echo "### Scheduled Tasks Diagnostics" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
  echo "**Run time:** $NOW_ISO" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"

  # Test 1: launchd daemon list
  echo "#### Test 1: Registered Hyo Daemons" >> "$DIAGNOSTICS"
  if command -v launchctl >/dev/null 2>&1; then
    echo "Hyo daemons currently registered:" >> "$DIAGNOSTICS"
    launchctl list 2>/dev/null | grep "hyo\." >> "$DIAGNOSTICS" 2>&1 || echo "(none found)" >> "$DIAGNOSTICS"
  else
    echo "⚠ launchctl not available (non-macOS?)" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 2: Last few launchd log entries (if available)
  echo "#### Test 2: Recent Launchd Activity" >> "$DIAGNOSTICS"
  LAUNCHD_LOG="/var/log/system.log"
  if [[ -r "$LAUNCHD_LOG" ]]; then
    echo "Last 5 hyo-related entries in /var/log/system.log:" >> "$DIAGNOSTICS"
    grep "hyo" "$LAUNCHD_LOG" 2>/dev/null | tail -5 >> "$DIAGNOSTICS" || echo "(none found)" >> "$DIAGNOSTICS"
  else
    echo "⚠ System log not readable" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 3: Most recent nei logs
  echo "#### Test 3: Nel Log Timeline" >> "$DIAGNOSTICS"
  echo "Most recent nel logs (by date):" >> "$DIAGNOSTICS"
  ls -1t "$LOGS"/nel-*.md 2>/dev/null | head -5 | while read log; do
    echo "- $(basename "$log")" >> "$DIAGNOSTICS"
  done || echo "(no nel logs)" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"

  # Test 4: Check if queue is processing
  echo "#### Test 4: Queue Worker Status" >> "$DIAGNOSTICS"
  QUEUE_DIR="$ROOT/kai/queue"
  if [[ -d "$QUEUE_DIR" ]]; then
    PENDING_COUNT=$(ls -1 "$QUEUE_DIR/pending/" 2>/dev/null | wc -l)
    COMPLETED_COUNT=$(ls -1 "$QUEUE_DIR/completed/" 2>/dev/null | wc -l)
    echo "Pending tasks: $PENDING_COUNT" >> "$DIAGNOSTICS"
    echo "Completed tasks: $COMPLETED_COUNT" >> "$DIAGNOSTICS"
  else
    echo "⚠ Queue directory not found" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"
}

# ---- Diagnostics: task-queue-size -------------------------------------------
diagnose_task_queue() {
  echo "### Task Queue Diagnostics" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
  echo "**Run time:** $NOW_ISO" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"

  # Test 1: Current P0 task count
  echo "#### Test 1: P0 Task Count" >> "$DIAGNOSTICS"
  if [[ -f "$ROOT/KAI_TASKS.md" ]]; then
    P0_COUNT=$(awk '/^## P0/,/^## P1/' "$ROOT/KAI_TASKS.md" 2>/dev/null | grep -c '^- \[ \]' || echo "0")
    echo "Current P0 open tasks: $P0_COUNT" >> "$DIAGNOSTICS"
    echo "Threshold: 5 (escalates at >5)" >> "$DIAGNOSTICS"
    if [[ $P0_COUNT -gt 5 ]]; then
      echo "⚠ OVERLOAD: Task count exceeds threshold" >> "$DIAGNOSTICS"
    fi
  else
    echo "✗ KAI_TASKS.md not found" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 2: Task age (oldest and newest) — limit output
  echo "#### Test 2: Task Age Distribution" >> "$DIAGNOSTICS"
  if [[ -f "$ROOT/KAI_TASKS.md" ]]; then
    echo "First 3 open P0 tasks:" >> "$DIAGNOSTICS"
    awk '/^## P0/,/^## P1/' "$ROOT/KAI_TASKS.md" | grep '^- \[ \]' | head -3 >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 3: Queue worker activity
  echo "#### Test 3: Queue Worker Recent Activity" >> "$DIAGNOSTICS"
  QUEUE_LOG="$ROOT/kai/queue/worker.log"
  if [[ -f "$QUEUE_LOG" ]]; then
    echo "Last 5 entries from worker.log:" >> "$DIAGNOSTICS"
    tail -5 "$QUEUE_LOG" >> "$DIAGNOSTICS" 2>&1 || echo "(could not read)" >> "$DIAGNOSTICS"
  else
    echo "⚠ Queue worker log not found" >> "$DIAGNOSTICS"
  fi
  echo "" >> "$DIAGNOSTICS"

  # Test 4: Delegation completion rates (sample only)
  echo "#### Test 4: Recent Task Completion" >> "$DIAGNOSTICS"
  echo "Most recently completed P0 tasks (sample, last 3):" >> "$DIAGNOSTICS"
  awk '/^## Done/,0' "$ROOT/KAI_TASKS.md" 2>/dev/null | grep "^\- \[x\]" | tail -3 >> "$DIAGNOSTICS" || echo "(none)" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
}

# ---- Build escalation state based on sentinel state --------------------------
build_escalation_state() {
  python3 - "$STATE" "$ESCALATION_STATE" "$NOW_ISO" <<'PYEOF'
import json, sys
from datetime import datetime

state_path = sys.argv[1]
escalation_path = sys.argv[2]
now_iso = sys.argv[3]

sentinel_state = {}
escalation_state = {"schema": "hyo.sentinel.escalation.v1", "lastUpdated": now_iso, "checks": {}}

try:
  with open(state_path) as f:
    sentinel_state = json.load(f)
except Exception as e:
  print(f"Warning: Could not read sentinel state: {e}", file=sys.stderr)

try:
  with open(escalation_path) as f:
    escalation_state = json.load(f)
except Exception as e:
  pass

escalation_state["lastUpdated"] = now_iso

# Scan known issues for chronic failures
checks_to_escalate = {}
for issue_id, issue_data in sentinel_state.get("knownIssues", {}).items():
  if issue_data.get("status") != "open":
    continue

  check_id = issue_data.get("check_id")
  consecutive = issue_data.get("daysFailing", 1)

  if check_id not in checks_to_escalate:
    checks_to_escalate[check_id] = {
      "consecutive_failures": consecutive,
      "last_status": "fail",
      "last_seen": issue_data.get("lastSeen"),
      "severity": issue_data.get("severity"),
      "escalation_level": 0
    }

  # Determine escalation level
  if consecutive <= 2:
    level = 0
  elif consecutive <= 4:
    level = 1
  elif consecutive <= 9:
    level = 2
  else:
    level = 3

  checks_to_escalate[check_id]["escalation_level"] = max(checks_to_escalate[check_id]["escalation_level"], level)

escalation_state["checks"] = checks_to_escalate

with open(escalation_path, "w") as f:
  json.dump(escalation_state, f, indent=2)

print(json.dumps({"checks_to_escalate": len(checks_to_escalate), "escalation_levels": {k: v["escalation_level"] for k, v in checks_to_escalate.items()}}, indent=2))
PYEOF
}

# ---- Main execution ---------------------------------------------------------
main() {
  cat > "$DIAGNOSTICS" <<EOF
# Sentinel Adaptive Diagnostics — $TODAY

**Generated:** $NOW_ISO
**Agent:** sentinel.hyo adaptive extension

---

## Overview

This report contains deep-dive diagnostics for checks that have failed 3+ consecutive times.
Escalation levels are assigned based on failure duration and used to trigger investigation protocols.

**Escalation thresholds:**
- Level 0: 1-2 failures (normal, watch)
- Level 1: 3-4 failures (warning — "needs attention")
- Level 2: 5-9 failures (chronic — trigger deeper diagnostics)
- Level 3: 10+ failures (critical — suggest disable/replace, auto-create P0)

---

EOF

  echo "Analyzing sentinel state..." >&2

  # Build escalation state from current sentinel failures
  build_escalation_state

  # Read escalation state to determine which checks need diagnostics
  python3 - "$ESCALATION_STATE" <<'PYEOF'
import json, sys
try:
  with open(sys.argv[1]) as f:
    esc_state = json.load(f)
  for check_id, check_data in esc_state.get("checks", {}).items():
    level = check_data.get("escalation_level", 0)
    consecutive = check_data.get("consecutive_failures", 0)
    if level >= 2:
      print(f"{check_id}:{level}:{consecutive}")
except Exception as e:
  print(f"Error: {e}", file=sys.stderr)
  sys.exit(1)
PYEOF

  local checks_to_diagnose=()
  while IFS=: read -r check_id level consecutive; do
    checks_to_diagnose+=("$check_id:$level:$consecutive")
  done < <(python3 - "$ESCALATION_STATE" <<'PYEOF'
import json, sys
try:
  with open(sys.argv[1]) as f:
    esc_state = json.load(f)
  for check_id, check_data in esc_state.get("checks", {}).items():
    level = check_data.get("escalation_level", 0)
    consecutive = check_data.get("consecutive_failures", 0)
    if level >= 2:
      print(f"{check_id}:{level}:{consecutive}")
except Exception as e:
  pass
PYEOF
  )

  if [[ ${#checks_to_diagnose[@]} -eq 0 ]]; then
    echo "## No Escalations" >> "$DIAGNOSTICS"
    echo "" >> "$DIAGNOSTICS"
    echo "No checks are currently at escalation level 2 or higher." >> "$DIAGNOSTICS"
    echo "Current system is healthy relative to chronic failure thresholds." >> "$DIAGNOSTICS"
  else
    # Run diagnostics for each check at level 2+
    for check_spec in "${checks_to_diagnose[@]}"; do
      IFS=: read -r check_id level consecutive <<< "$check_spec"
      echo "Running diagnostics for: $check_id (level $level, $consecutive consecutive failures)" >&2

      case "$check_id" in
        api-health-green)
          diagnose_api_health
          ;;
        aurora-ran-today)
          diagnose_aurora_ran_today
          ;;
        scheduled-tasks-fired)
          diagnose_scheduled_tasks
          ;;
        task-queue-size)
          diagnose_task_queue
          ;;
        *)
          echo "### Diagnostics for $check_id" >> "$DIAGNOSTICS"
          echo "No specialized diagnostic for this check type. Manual review recommended." >> "$DIAGNOSTICS"
          echo "" >> "$DIAGNOSTICS"
          ;;
      esac
    done
  fi

  # Append escalation summary
  echo "---" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
  echo "## Escalation Summary" >> "$DIAGNOSTICS"
  echo "" >> "$DIAGNOSTICS"
  python3 - "$ESCALATION_STATE" "$DIAGNOSTICS" <<'PYEOF'
import json, sys
esc_state_path = sys.argv[1]
diag_path = sys.argv[2]

try:
  with open(esc_state_path) as f:
    esc_state = json.load(f)

  summary_lines = []
  for check_id, check_data in sorted(esc_state.get("checks", {}).items()):
    level = check_data.get("escalation_level", 0)
    consecutive = check_data.get("consecutive_failures", 0)
    severity = check_data.get("severity", "P2")

    level_name = {0: "Normal", 1: "Warning", 2: "Chronic", 3: "Critical"}.get(level, "Unknown")
    summary_lines.append(f"- **{check_id}** ({severity}): Level {level} ({level_name}) — {consecutive} consecutive failures")

  with open(diag_path, "a") as f:
    if summary_lines:
      f.write("\n".join(summary_lines) + "\n")
    else:
      f.write("All checks healthy (no escalations).\n")
except Exception as e:
  pass
PYEOF

  # Output summary as JSON to stdout
  echo ""
  python3 - "$ESCALATION_STATE" <<'PYEOF'
import json, sys
try:
  with open(sys.argv[1]) as f:
    esc_state = json.load(f)

  summary = {
    "timestamp": esc_state.get("lastUpdated"),
    "total_checks_tracked": len(esc_state.get("checks", {})),
    "escalated_to_level_2": len([c for c in esc_state.get("checks", {}).values() if c.get("escalation_level", 0) >= 2]),
    "escalated_to_level_3": len([c for c in esc_state.get("checks", {}).values() if c.get("escalation_level", 0) >= 3]),
    "checks": esc_state.get("checks", {})
  }

  print(json.dumps(summary, indent=2))
except Exception as e:
  print(json.dumps({"error": str(e)}, indent=2))
  sys.exit(1)
PYEOF

  echo ""
  echo "Diagnostics written to: $DIAGNOSTICS" >&2
}

main "$@"
