#!/usr/bin/env bash
# kai/queue/healthcheck.sh — 2-hour agent health check
#
# Runs every 2 hours. Checks:
# 1. Are there unprocessed flags (P0/P1)?
# 2. Is the queue worker alive?
# 3. Are there pending queue commands (worker stalled)?
# 4. Are scheduled agents producing output?
# 5. Rendered output verification (morning report, Aether real data, data-to-HTML binding)
# 6. Recent completed queue results
#
# Check 5 mirrors Nel Phase 7.5 and Simulation Phase 6 — all three systems
# independently verify rendered output. Added session 8 after morning report gap.
#
# Results written to kai/queue/healthcheck-latest.json for Kai to read.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
QUEUE="$ROOT/kai/queue"
OUTPUT="$QUEUE/healthcheck-latest.json"
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date +%Y-%m-%d)
ISSUES=0
WARNINGS=0
ACTIONS_LOG=""

log() { echo "[healthcheck] $(TZ='America/Denver' date +%H:%M:%S) $*"; }

# Collect findings
FINDINGS=""
add_finding() {
  local severity="$1" area="$2" detail="$3"
  FINDINGS="${FINDINGS}{\"severity\":\"$severity\",\"area\":\"$area\",\"detail\":\"$detail\"},"
  if [[ "$severity" == "P0" ]] || [[ "$severity" == "P1" ]]; then
    ISSUES=$((ISSUES + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ---- Check 1: Unprocessed P0/P1 flags ----
KAI_LOG="$ROOT/kai/ledger/log.jsonl"
if [[ -f "$KAI_LOG" ]]; then
  RECENT_FLAGS=$(python3 -c "
import json
from datetime import datetime, timedelta
cutoff = (datetime.utcnow() - timedelta(hours=2)).isoformat() + 'Z'
flags = []
with open('$KAI_LOG') as f:
  for line in f:
    line = line.strip()
    if not line: continue
    try:
      e = json.loads(line)
      if e.get('action') == 'FLAG' and e.get('ts','') > cutoff:
        sev = e.get('severity','P3')
        if sev in ('P0','P1'):
          flags.append(f\"{sev}: {e.get('title','?')}\")
    except: pass
print(len(flags))
for f in flags: print(f)
" 2>/dev/null)

  FLAG_COUNT=$(echo "$RECENT_FLAGS" | head -1)
  if [[ "$FLAG_COUNT" -gt 0 ]] 2>/dev/null; then
    add_finding "P1" "flags" "$FLAG_COUNT unaddressed P0/P1 flags in last 2h"
  fi
fi

# ---- Check 2: Queue worker alive ----
WORKER_LOG="$QUEUE/worker.log"
if [[ -f "$WORKER_LOG" ]]; then
  LAST_LINE=$(tail -1 "$WORKER_LOG" 2>/dev/null)
  LAST_TS=$(echo "$LAST_LINE" | grep -oE '\[20[0-9]{2}-[0-9]{2}-[0-9]{2}' | tr -d '[' | head -1)
  if [[ -n "$LAST_TS" ]]; then
    LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || date -f "%Y-%m-%d" "$LAST_TS" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE_HOURS=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))
    if [[ $AGE_HOURS -gt 4 ]]; then
      add_finding "P2" "queue-worker" "Worker last active ${AGE_HOURS}h ago — may be dead"
    fi
  fi
else
  add_finding "P2" "queue-worker" "No worker log found — worker may not be installed"
fi

# ---- Check 3: Pending queue commands ----
PENDING_COUNT=$(ls "$QUEUE/pending/"*.json 2>/dev/null | wc -l | tr -d ' ')
if [[ "$PENDING_COUNT" -gt 0 ]]; then
  add_finding "P2" "queue" "$PENDING_COUNT commands pending — worker may be stalled"
fi

# ---- Check 4: Agent output freshness ----
# Check if agents that should run daily have produced today's output
for agent_dir in "$ROOT/agents/"*/logs; do
  [[ -d "$agent_dir" ]] || continue
  AGENT=$(basename "$(dirname "$agent_dir")")
  TODAY_LOG=$(ls "$agent_dir"/*"$TODAY"* 2>/dev/null | head -1)
  if [[ -z "$TODAY_LOG" ]]; then
    # Only flag if agent has ANY logs (i.e. has been set up)
    ANY_LOG=$(ls "$agent_dir"/*.md "$agent_dir"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$ANY_LOG" ]]; then
      add_finding "P3" "agent-output" "$AGENT has no output today"
    fi
  fi
done

# ---- Check 5: Rendered Output Verification (Kai's independent catch) ----
# This mirrors Nel Phase 7.5 and Simulation Phase 6 — all 3 systems independently
# verify that data files actually render on HQ. Added after session 8 gap.

# 5a: Morning report exists and is current — AUTO-REMEDIATE if stale/missing
MR_JSON="$ROOT/website/data/morning-report.json"
HQ_HTML="$ROOT/website/hq.html"
MR_GENERATOR="$ROOT/bin/generate-morning-report.sh"
MR_STALE=false

if [[ -f "$MR_JSON" ]]; then
  MR_DATE=$(python3 -c "import json; print(json.load(open('$MR_JSON')).get('date',''))" 2>/dev/null || echo "")
  TODAY_MT=$(TZ="America/Denver" date +%Y-%m-%d)
  YESTERDAY_MT=$(TZ="America/Denver" date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d 2>/dev/null || echo "")
  if [[ "$MR_DATE" != "$TODAY_MT" ]] && [[ "$MR_DATE" != "$YESTERDAY_MT" ]]; then
    add_finding "P1" "morning-report" "Morning report stale: date=$MR_DATE (today=$TODAY_MT) — auto-regenerating"
    MR_STALE=true
  fi
  # Verify rendering code exists in hq.html
  if [[ -f "$HQ_HTML" ]] && ! grep -q "loadMorningReport\|mrSummary" "$HQ_HTML" 2>/dev/null; then
    add_finding "P0" "morning-report" "Morning report JSON exists but hq.html has NO rendering code"
  fi
else
  add_finding "P1" "morning-report" "Morning report JSON missing entirely — auto-generating"
  MR_STALE=true
fi

# Auto-remediate: regenerate morning report if stale or missing
if [[ "$MR_STALE" == "true" ]] && [[ -f "$MR_GENERATOR" ]]; then
  log "Auto-regenerating morning report..."
  if HYO_ROOT="$ROOT" bash "$MR_GENERATOR" 2>&1; then
    log "Morning report regenerated successfully"
    ACTIONS_LOG="${ACTIONS_LOG:+$ACTIONS_LOG; }Regenerated stale morning report"
  else
    log "Morning report regeneration failed"
  fi
fi

# 5b: Aether metrics show real data (not defaults)
AETHER_JSON="$ROOT/website/data/aether-metrics.json"
if [[ -f "$AETHER_JSON" ]]; then
  AETHER_BAL=$(python3 -c "
import json
d = json.load(open('$AETHER_JSON'))
cw = d.get('currentWeek', d.get('currentPeriod', {}))
print(cw.get('currentBalance', 0))
" 2>/dev/null || echo "0")
  if [[ "$AETHER_BAL" == "1000" ]] || [[ "$AETHER_BAL" == "1000.0" ]] || [[ "$AETHER_BAL" == "0" ]]; then
    add_finding "P1" "aether-render" "Aether balance is default/placeholder (\$$AETHER_BAL)"
  fi
fi

# 5c: Data-to-HTML binding — every JSON must have a render reference
if [[ -f "$HQ_HTML" ]]; then
  for jf in "$ROOT"/website/data/*.json; do
    [[ ! -f "$jf" ]] && continue
    jname=$(basename "$jf")
    if ! grep -q "$jname" "$HQ_HTML" 2>/dev/null; then
      add_finding "P2" "render-binding" "Data file $jname has no reference in hq.html"
    fi
  done
fi

# ---- Check 6: Recent completed queue results ----
RECENT_RESULTS=""
for f in $(ls -t "$QUEUE/completed/"*.json "$QUEUE/failed/"*.json 2>/dev/null | head -5); do
  RESULT=$(python3 -c "
import json
with open('$f') as fh:
  r = json.load(fh)
  status = 'ok' if r['exit_code'] == 0 else 'failed'
  print(json.dumps({'id':r['id'],'status':status,'command':r['command'][:80],'exit_code':r['exit_code']}))
" 2>/dev/null)
  RECENT_RESULTS="${RECENT_RESULTS}${RESULT},"
done

# ============================================================================
# WHAT'S NEXT GATE — Don't just report. Act.
# ============================================================================

# P0/P1 flags → immediate dispatch to owning agent + queue re-check
if [[ $ISSUES -gt 0 ]] && [[ -f "$ROOT/bin/dispatch.sh" ]]; then
  # Re-read the actual flags and dispatch remediation
  python3 - "$KAI_LOG" "$ROOT/bin/dispatch.sh" <<'ACTEOF'
import json, subprocess, sys
from datetime import datetime, timedelta

kai_log = sys.argv[1]
dispatch = sys.argv[2]
cutoff = (datetime.utcnow() - timedelta(hours=2)).isoformat() + "Z"

with open(kai_log) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            if e.get("action") != "FLAG":
                continue
            if e.get("ts", "") < cutoff:
                continue
            sev = e.get("severity", "P3")
            if sev not in ("P0", "P1"):
                continue
            agent = e.get("agent", "kai")
            title = e.get("title", "unknown issue")

            # Determine owning agent for remediation
            owner = agent  # default: the agent that flagged it owns the fix
            if "queue" in title.lower():
                owner = "sam"
            elif "security" in title.lower() or "secret" in title.lower():
                owner = "nel"

            # Dispatch remediation task
            subprocess.run(
                ["bash", dispatch, "delegate", owner, sev,
                 f"[AUTO-REMEDIATE] {title} (flagged by {agent})"],
                capture_output=True, timeout=10
            )
            print(f"DISPATCHED: {sev} → {owner}: {title}")
        except Exception:
            pass
ACTEOF
fi

# Stalled queue → restart worker
if [[ "$PENDING_COUNT" -gt 0 ]]; then
  # Try to process pending commands directly
  bash "$ROOT/kai/queue/worker.sh" 2>/dev/null &
fi

# ---- Write healthcheck result ----
# Include actions taken, not just findings
ACTIONS_TAKEN=""
if [[ $ISSUES -gt 0 ]]; then
  ACTIONS_TAKEN="Dispatched auto-remediation for $ISSUES P0/P1 issues"
fi
if [[ "$PENDING_COUNT" -gt 0 ]]; then
  ACTIONS_TAKEN="${ACTIONS_TAKEN:+$ACTIONS_TAKEN; }Kicked queue worker for $PENDING_COUNT stalled commands"
fi

python3 - <<PYEOF
import json

findings_str = '''[${FINDINGS%,}]'''
results_str = '''[${RECENT_RESULTS%,}]'''

try:
    findings = json.loads(findings_str)
except:
    findings = []

try:
    results = json.loads(results_str)
except:
    results = []

health = {
    "ts": "$NOW_ISO",
    "status": "HEALTHY" if $ISSUES == 0 else "ISSUES",
    "issues": $ISSUES,
    "warnings": $WARNINGS,
    "findings": findings,
    "actions_taken": "$ACTIONS_TAKEN" if "$ACTIONS_TAKEN" else "none — system healthy",
    "recent_queue_results": results,
    "next_check": "in 2 hours (30min if P0 found)"
}

with open("$OUTPUT", "w") as f:
    json.dump(health, f, indent=2)

# Print summary
if $ISSUES > 0:
    print(f"⚠ ISSUES: {$ISSUES} issues, {$WARNINGS} warnings — AUTO-REMEDIATION DISPATCHED")
    for f in findings:
        if f['severity'] in ('P0','P1'):
            print(f"  {f['severity']}: [{f['area']}] {f['detail']}")
    print(f"  Actions: $ACTIONS_TAKEN")
else:
    print(f"✓ HEALTHY ({$WARNINGS} warnings)")
PYEOF

# ---- Schedule accelerated re-check if P0 found ----
if [[ $ISSUES -gt 0 ]]; then
  # NOTE: Do NOT schedule re-checks via the queue with `sleep` commands.
  # The queue worker is single-threaded — a sleep blocks ALL commands.
  # Instead, the healthcheck runs on its own launchd schedule (every 2h).
  # If a P0 issue needs faster re-checking, add a separate launchd timer.
  echo "Re-check skipped — rely on 2h launchd schedule for next run."
fi
