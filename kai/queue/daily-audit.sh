#!/usr/bin/env bash
# kai/queue/daily-audit.sh — Daily bottleneck audit
#
# Kai reviews every agent's operational health daily.
# Deeper than the 2-hour health check — catches systemic bottlenecks,
# stale automation, and missed optimizations.
#
# Usage: bash kai/queue/daily-audit.sh
# Scheduled: daily at 22:00 MT via Cowork or launchd

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DATE=$(date +%Y-%m-%d)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AUDIT_FILE="$ROOT/kai/ledger/daily-audit-${DATE}.md"
DISPATCH="$ROOT/bin/dispatch.sh"

AGENTS=(nel sam ra aether dex)
ISSUES=0
WARNINGS=0
ACTIONS=""
BOTTLENECKS=""
AUTOMATION_GAPS=""

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

add_action() {
  ACTIONS="${ACTIONS}\n- $1"
}

add_bottleneck() {
  BOTTLENECKS="${BOTTLENECKS}\n- $1"
  WARNINGS=$((WARNINGS + 1))
}

add_gap() {
  AUTOMATION_GAPS="${AUTOMATION_GAPS}\n- $1"
}

# ── Agent Health Status ──
declare -A AGENT_STATUS

for agent in "${AGENTS[@]}"; do
  status="OK"

  # Check ACTIVE.md freshness
  active="$ROOT/agents/$agent/ledger/ACTIVE.md"
  if [[ -f "$active" ]]; then
    # Check if updated in last 48h
    if [[ "$(uname)" == "Darwin" ]]; then
      mtime=$(stat -f %m "$active" 2>/dev/null || echo 0)
    else
      mtime=$(stat -c %Y "$active" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    age_h=$(( (now - mtime) / 3600 ))
    if [[ $age_h -gt 48 ]]; then
      status="WARN"
      add_bottleneck "$agent: ACTIVE.md not updated in ${age_h}h (>48h threshold)"
    fi
  else
    status="FAIL"
    add_bottleneck "$agent: ACTIVE.md missing"
    ISSUES=$((ISSUES + 1))
  fi

  # Check ledger log freshness
  log_file="$ROOT/agents/$agent/ledger/log.jsonl"
  if [[ -f "$log_file" ]]; then
    last_entry=$(tail -1 "$log_file" 2>/dev/null)
    if [[ -z "$last_entry" ]]; then
      if [[ "$status" != "FAIL" ]]; then status="WARN"; fi
      add_bottleneck "$agent: ledger log.jsonl is empty"
    fi
  fi

  # Check today's runner output
  runner_log="$ROOT/agents/$agent/logs/${agent}-${DATE}.md"
  alt_log="$ROOT/agents/nel/logs/${agent}-${DATE}.md"
  if [[ ! -f "$runner_log" ]] && [[ ! -f "$alt_log" ]]; then
    # Only flag for agents that should run daily
    case "$agent" in
      nel|dex|aether)
        if [[ "$status" != "FAIL" ]]; then status="WARN"; fi
        add_bottleneck "$agent: no runner output for today ($DATE)"
        ;;
    esac
  fi

  # Check launchd daemons (via log file freshness as proxy)
  daemon_log="/tmp/hyo-${agent}.log"
  if [[ -f "$daemon_log" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      dmtime=$(stat -f %m "$daemon_log" 2>/dev/null || echo 0)
    else
      dmtime=$(stat -c %Y "$daemon_log" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    daemon_age_h=$(( (now - dmtime) / 3600 ))
    case "$agent" in
      aether)
        # Should run every 15 min
        if [[ $daemon_age_h -gt 1 ]]; then
          status="FAIL"
          add_bottleneck "$agent: daemon log stale (${daemon_age_h}h, expected <1h)"
          ISSUES=$((ISSUES + 1))
        fi
        ;;
      dex)
        # Should run daily
        if [[ $daemon_age_h -gt 25 ]]; then
          status="WARN"
          add_bottleneck "$agent: daemon log stale (${daemon_age_h}h, expected <25h)"
        fi
        ;;
    esac
  fi

  AGENT_STATUS[$agent]="$status"
done

# ── Queue Health ──
PENDING_COUNT=0
FAILED_COUNT=0
COMPLETED_COUNT=0

pending_dir="$ROOT/kai/queue/pending"
completed_dir="$ROOT/kai/queue/completed"
failed_dir="$ROOT/kai/queue/failed"

[[ -d "$pending_dir" ]] && PENDING_COUNT=$(find "$pending_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
[[ -d "$completed_dir" ]] && COMPLETED_COUNT=$(find "$completed_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
[[ -d "$failed_dir" ]] && FAILED_COUNT=$(find "$failed_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

# Check for stale pending items (>6h)
if [[ -d "$pending_dir" ]]; then
  for f in "$pending_dir"/*.json; do
    [[ -f "$f" ]] || continue
    if [[ "$(uname)" == "Darwin" ]]; then
      fmtime=$(stat -f %m "$f" 2>/dev/null || echo 0)
    else
      fmtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    age_h=$(( (now - fmtime) / 3600 ))
    if [[ $age_h -gt 6 ]]; then
      add_bottleneck "Queue: pending item $(basename "$f") stale for ${age_h}h"
    fi
  done
fi

# ── KAI_TASKS.md Analysis ──
TASKS_FILE="$ROOT/KAI_TASKS.md"
AUTOMATE_STALE=0
if [[ -f "$TASKS_FILE" ]]; then
  # Count [AUTOMATE] items (these should be prioritized)
  AUTOMATE_STALE=$(grep -c '\[AUTOMATE\]' "$TASKS_FILE" 2>/dev/null || echo 0)
  if [[ $AUTOMATE_STALE -gt 5 ]]; then
    add_gap "KAI_TASKS has $AUTOMATE_STALE [AUTOMATE] items — review for quick wins"
  fi
fi

# ── Automation Coverage Check ──
expected_plists=(
  "agents/nel/consolidation/com.hyo.consolidation.plist"
  "agents/nel/consolidation/com.hyo.simulation.plist"
  "agents/dex/com.hyo.dex.plist"
  "agents/aether/com.hyo.aether.plist"
  "agents/ra/com.hyo.aurora.plist"
  "kai/queue/com.hyo.queue-worker.plist"
)
for plist in "${expected_plists[@]}"; do
  if [[ ! -f "$ROOT/$plist" ]]; then
    add_gap "Missing launchd plist: $plist"
  fi
done

# ── Protocol Staleness Prevention ──
for agent in "${AGENTS[@]}"; do
  # Check PLAYBOOK.md freshness
  playbook="$ROOT/agents/$agent/PLAYBOOK.md"
  if [[ -f "$playbook" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      pb_mtime=$(stat -f %m "$playbook" 2>/dev/null || echo 0)
    else
      pb_mtime=$(stat -c %Y "$playbook" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    pb_age_d=$(( (now - pb_mtime) / 86400 ))
    if [[ $pb_age_d -gt 14 ]]; then
      add_bottleneck "$agent: PLAYBOOK.md stale for ${pb_age_d}d (>14d = P1)"
      ISSUES=$((ISSUES + 1))
    elif [[ $pb_age_d -gt 7 ]]; then
      add_bottleneck "$agent: PLAYBOOK.md aging (${pb_age_d}d, >7d threshold)"
    fi
  else
    add_gap "$agent: missing PLAYBOOK.md"
  fi

  # Check evolution.jsonl freshness
  evo="$ROOT/agents/$agent/evolution.jsonl"
  if [[ -f "$evo" ]] && [[ -s "$evo" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      evo_mtime=$(stat -f %m "$evo" 2>/dev/null || echo 0)
    else
      evo_mtime=$(stat -c %Y "$evo" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    evo_age_h=$(( (now - evo_mtime) / 3600 ))
    if [[ $evo_age_h -gt 48 ]]; then
      add_bottleneck "$agent: evolution.jsonl not written in ${evo_age_h}h (agent may be inactive)"
      ISSUES=$((ISSUES + 1))
    fi
  fi

  # Check PRIORITIES.md freshness
  priorities="$ROOT/agents/$agent/PRIORITIES.md"
  if [[ -f "$priorities" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      pr_mtime=$(stat -f %m "$priorities" 2>/dev/null || echo 0)
    else
      pr_mtime=$(stat -c %Y "$priorities" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    pr_age_d=$(( (now - pr_mtime) / 86400 ))
    if [[ $pr_age_d -gt 14 ]]; then
      add_bottleneck "$agent: PRIORITIES.md stale for ${pr_age_d}d"
    fi
  fi
done

# Check AGENT_ALGORITHMS.md (constitution) freshness
algo="$ROOT/kai/AGENT_ALGORITHMS.md"
if [[ -f "$algo" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    algo_mtime=$(stat -f %m "$algo" 2>/dev/null || echo 0)
  else
    algo_mtime=$(stat -c %Y "$algo" 2>/dev/null || echo 0)
  fi
  now=$(date +%s)
  algo_age_d=$(( (now - algo_mtime) / 86400 ))
  if [[ $algo_age_d -gt 14 ]]; then
    add_bottleneck "AGENT_ALGORITHMS.md (constitution) not reviewed in ${algo_age_d}d — Kai self-flag"
    ISSUES=$((ISSUES + 1))
  fi
fi

# ── Dispatch P0/P1 if found ──
if [[ $ISSUES -gt 0 ]] && [[ -x "$DISPATCH" ]]; then
  bash "$DISPATCH" flag kai P1 "Daily audit: $ISSUES critical issues found" 2>/dev/null || true
  add_action "Dispatched P1 flag for $ISSUES critical issues"
fi

# ── Write Audit Report ──
mkdir -p "$(dirname "$AUDIT_FILE")"
cat > "$AUDIT_FILE" <<EOF
# Daily Bottleneck Audit — $DATE

**Generated:** $NOW_ISO
**Issues:** $ISSUES | **Warnings:** $WARNINGS

## Agent Health

| Agent  | Status |
|--------|--------|
| nel    | ${AGENT_STATUS[nel]:-UNKNOWN} |
| sam    | ${AGENT_STATUS[sam]:-UNKNOWN} |
| ra     | ${AGENT_STATUS[ra]:-UNKNOWN} |
| aether | ${AGENT_STATUS[aether]:-UNKNOWN} |
| dex    | ${AGENT_STATUS[dex]:-UNKNOWN} |

## Queue

- Pending: $PENDING_COUNT
- Failed: $FAILED_COUNT
- Completed: $COMPLETED_COUNT

## Bottlenecks Found

$(if [[ -n "$BOTTLENECKS" ]]; then echo -e "$BOTTLENECKS"; else echo "None"; fi)

## Actions Taken

$(if [[ -n "$ACTIONS" ]]; then echo -e "$ACTIONS"; else echo "None"; fi)

## Automation Gaps

$(if [[ -n "$AUTOMATION_GAPS" ]]; then echo -e "$AUTOMATION_GAPS"; else echo "None"; fi)

---

*Next audit: $(date -d "+1 day" +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d 2>/dev/null || echo "tomorrow")*
EOF

log "Daily audit complete: $ISSUES issues, $WARNINGS warnings"
log "Report: $AUDIT_FILE"

if [[ $ISSUES -gt 0 ]]; then
  exit 1
else
  exit 0
fi
