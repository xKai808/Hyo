#!/usr/bin/env bash
# bin/generate-morning-report.sh — Standalone morning report generator
#
# Generates website/data/morning-report.json from agent logs, ledgers,
# and simulation outcomes. Runs WITHOUT a Kai/Cowork session.
#
# Called by:
#   - com.hyo.morning-report launchd plist (05:00 MT daily)
#   - healthcheck.sh auto-remediation (when morning report is stale)
#   - nel-qa-cycle.sh Phase 7.5 auto-remediation (when stale detected)
#   - dispatch.sh simulation Phase 6 auto-remediation
#
# After generating JSON, commits and pushes so Vercel picks it up.
#
# Usage: bash bin/generate-morning-report.sh
#        HYO_ROOT=/path/to/Hyo bash bin/generate-morning-report.sh

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
OUTPUT="$ROOT/website/data/morning-report.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
LOG_TAG="[morning-report]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

log "Generating morning report for $TODAY"

# ── Gather agent data ──

# Helper: read last N lines of a log file, extract key info
read_agent_log() {
  local agent="$1"
  local log_dir="$ROOT/agents/$agent/logs"
  local today_log=""

  # Find today's log (try common naming patterns)
  for pattern in "${agent}-${TODAY}" "${agent}_${TODAY}" "${TODAY}"; do
    today_log=$(ls "$log_dir"/*"$pattern"* 2>/dev/null | head -1)
    [[ -n "$today_log" ]] && break
  done

  if [[ -n "$today_log" ]] && [[ -f "$today_log" ]]; then
    # Return last 50 lines as summary material
    tail -50 "$today_log" 2>/dev/null
  else
    echo "No log found for $TODAY"
  fi
}

# Read simulation outcome
SIM_SUMMARY="No simulation data"
SIM_FILE="$ROOT/kai/ledger/simulation-outcomes.jsonl"
if [[ -f "$SIM_FILE" ]]; then
  LAST_SIM=$(tail -1 "$SIM_FILE" 2>/dev/null)
  if [[ -n "$LAST_SIM" ]]; then
    SIM_SUMMARY=$(python3 -c "
import json
s = json.loads('$LAST_SIM'.replace(\"'\", \"\"))
print(f\"{s.get('passed',0)} pass / {s.get('failed',0)} fail\")
" 2>/dev/null || echo "Parse error")
  fi
fi

# Read healthcheck
HC_SUMMARY="No healthcheck data"
HC_FILE="$ROOT/kai/queue/healthcheck-latest.json"
if [[ -f "$HC_FILE" ]]; then
  HC_SUMMARY=$(python3 -c "
import json
with open('$HC_FILE') as f:
  h = json.load(f)
print(f\"{h.get('status','?')}: {h.get('issues',0)} issues, {h.get('warnings',0)} warnings\")
" 2>/dev/null || echo "Parse error")
fi

# Read each agent's status from their ACTIVE.md or evolution.jsonl
get_agent_status() {
  local agent="$1"
  local active="$ROOT/agents/$agent/ledger/ACTIVE.md"
  local evo="$ROOT/agents/$agent/evolution.jsonl"

  local task_count=0
  if [[ -f "$active" ]]; then
    task_count=$(grep -c "^\- \*\*" "$active" 2>/dev/null || echo "0")
  fi

  local last_score=""
  if [[ -f "$evo" ]]; then
    last_score=$(python3 -c "
import json
last = None
with open('$evo') as f:
  for line in f:
    line = line.strip()
    if not line: continue
    try: last = json.loads(line)
    except: pass
if last and 'metrics' in last:
  print(last['metrics'].get('improvement_score', '?'))
elif last and 'assessment' in last:
  print(last['assessment'][:60])
else:
  print('no data')
" 2>/dev/null || echo "?")
  fi

  echo "${task_count} active tasks, score: ${last_score:-?}"
}

# Read Aether trading data
AETHER_SUMMARY="No trading data"
AETHER_JSON="$ROOT/website/data/aether-metrics.json"
if [[ -f "$AETHER_JSON" ]]; then
  AETHER_SUMMARY=$(python3 -c "
import json
with open('$AETHER_JSON') as f:
  d = json.load(f)
cw = d.get('currentWeek', d.get('currentPeriod', {}))
bal = cw.get('currentBalance', '?')
trades = cw.get('totalTrades', '?')
wr = cw.get('winRate', '?')
strats = len(cw.get('strategies', []))
print(f'Balance: \${bal}, Trades: {trades}, Win rate: {wr}, Strategies: {strats}')
" 2>/dev/null || echo "Parse error")
fi

# Read known issues count
KNOWN_ISSUES_COUNT=0
KI_FILE="$ROOT/kai/ledger/known-issues.jsonl"
if [[ -f "$KI_FILE" ]]; then
  KNOWN_ISSUES_COUNT=$(grep -c '"status":"active"' "$KI_FILE" 2>/dev/null || echo "0")
fi

# Check newsletter status
NEWSLETTER_STATUS="not produced"
for nl in "$ROOT/agents/ra/output/"*"$TODAY"*; do
  if [[ -f "$nl" ]]; then
    NEWSLETTER_STATUS="produced"
    break
  fi
done

# ── Build the JSON ──

python3 - "$OUTPUT" "$TODAY" "$NOW_MT" "$SIM_SUMMARY" "$HC_SUMMARY" "$AETHER_SUMMARY" "$KNOWN_ISSUES_COUNT" "$NEWSLETTER_STATUS" <<'PYEOF'
import json, sys, os, glob
from datetime import datetime

output_path = sys.argv[1]
today = sys.argv[2]
now_mt = sys.argv[3]
sim_summary = sys.argv[4]
hc_summary = sys.argv[5]
aether_summary = sys.argv[6]
known_issues = int(sys.argv[7])
newsletter_status = sys.argv[8]

root = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))

def get_agent_summary(agent):
    """Build a summary for one agent from their ledger and logs."""
    active_file = os.path.join(root, "agents", agent, "ledger", "ACTIVE.md")
    evo_file = os.path.join(root, "agents", agent, "evolution.jsonl")

    tasks = 0
    status_lines = []
    if os.path.exists(active_file):
        with open(active_file) as f:
            for line in f:
                if line.startswith("- **"):
                    tasks += 1
                    # Extract task name
                    clean = line.strip("- *\n")[:80]
                    status_lines.append(clean)

    score = "?"
    assessment = ""
    if os.path.exists(evo_file):
        last = None
        with open(evo_file) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    last = json.loads(line)
                except:
                    pass
        if last:
            if "metrics" in last:
                score = last["metrics"].get("improvement_score", "?")
            assessment = last.get("assessment", "")[:100]

    return {
        "agent": agent,
        "activeTasks": tasks,
        "score": score,
        "assessment": assessment,
        "topTasks": status_lines[:3]
    }

# Build agent reports
agents = ["nel", "ra", "sam", "aether"]
agent_reports = []
for a in agents:
    agent_dir = os.path.join(root, "agents", a)
    if os.path.isdir(agent_dir):
        agent_reports.append(get_agent_summary(a))

# Determine what went well vs needs attention
went_well = []
needs_attention = []

if "HEALTHY" in hc_summary:
    went_well.append("System healthcheck passing clean")
else:
    needs_attention.append(f"Healthcheck: {hc_summary}")

if "0 fail" in sim_summary:
    went_well.append(f"Nightly simulation: {sim_summary}")
else:
    needs_attention.append(f"Simulation: {sim_summary}")

if newsletter_status == "produced":
    went_well.append("Newsletter produced on schedule")
else:
    needs_attention.append("Newsletter not produced today")

if known_issues > 10:
    needs_attention.append(f"{known_issues} active known issues — review needed")

# Build final report
report = {
    "date": today,
    "generatedAt": now_mt,
    "generatedBy": "bin/generate-morning-report.sh",
    "executiveSummary": f"Morning report for {today}. Simulation: {sim_summary}. Health: {hc_summary}. Trading: {aether_summary}.",
    "agentReports": agent_reports,
    "kaiReport": {
        "simulation": sim_summary,
        "healthcheck": hc_summary,
        "knownIssues": known_issues,
        "newsletter": newsletter_status
    },
    "systemHealth": {
        "queueWorker": "check healthcheck-latest.json",
        "simulation": sim_summary,
        "healthcheck": hc_summary
    },
    "trading": {
        "summary": aether_summary
    },
    "wentWell": went_well,
    "needsAttention": needs_attention,
    "improvements": [
        "Review and close stale known issues",
        "Check agent evolution scores for regressions"
    ]
}

with open(output_path, "w") as f:
    json.dump(report, f, indent=2)

print(f"Morning report written: {output_path}")
print(f"  Agents: {len(agent_reports)}")
print(f"  Went well: {len(went_well)} | Needs attention: {len(needs_attention)}")
PYEOF

if [[ $? -ne 0 ]]; then
  log "ERROR: Failed to generate morning report JSON"
  exit 1
fi

# ── Copy to sam/website mirror if it exists ──
SAM_MIRROR="$ROOT/agents/sam/website/data/morning-report.json"
if [[ -d "$(dirname "$SAM_MIRROR")" ]]; then
  cp "$OUTPUT" "$SAM_MIRROR"
  log "Copied to sam/website mirror"
fi

# ── Commit and push ──
cd "$ROOT" || exit 1
if git diff --quiet "$OUTPUT" 2>/dev/null; then
  log "No changes to commit (report unchanged)"
else
  git add "$OUTPUT" "$SAM_MIRROR" 2>/dev/null
  git commit -m "morning-report: auto-generated for $TODAY" 2>/dev/null
  git push origin main 2>/dev/null && log "Pushed to origin" || log "Push failed (will retry next cycle)"
fi

log "Done"
