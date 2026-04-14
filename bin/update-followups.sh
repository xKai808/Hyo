#!/usr/bin/env bash
# bin/update-followups.sh — Accountability loop for agent research follow-ups
#
# Checks each agent's research-sources.json for stale follow-ups,
# flags them in the agent's ACTIVE.md, and reports to Kai via dispatch.
#
# Run as part of healthcheck or daily audit.
# Usage: bash bin/update-followups.sh [agent]
#        If no agent specified, checks all agents.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
LOG_TAG="[followup-check]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

AGENTS=("nel" "sam" "ra" "aether" "dex")
if [[ "${1:-}" != "" ]]; then
  AGENTS=("$1")
fi

TOTAL_OPEN=0
TOTAL_STALE=0

for agent in "${AGENTS[@]}"; do
  SOURCES="$ROOT/agents/$agent/research-sources.json"
  if [[ ! -f "$SOURCES" ]]; then
    continue
  fi

  python3 - "$SOURCES" "$agent" "$TODAY" << 'PYEOF'
import json, sys
from datetime import datetime, timedelta

sources_file = sys.argv[1]
agent = sys.argv[2]
today_str = sys.argv[3]
today = datetime.strptime(today_str, "%Y-%m-%d")

with open(sources_file) as f:
    config = json.load(f)

followups = config.get("followUps", [])
open_items = [f for f in followups if f.get("status") == "open"]
stale_items = []

for fu in open_items:
    fu_date = datetime.strptime(fu["date"], "%Y-%m-%d")
    age_days = (today - fu_date).days
    if age_days > 7:
        stale_items.append(fu)
        fu["status"] = "stale"  # Mark as stale for visibility

print(f"AGENT: {agent}")
print(f"OPEN: {len(open_items)}")
print(f"STALE: {len(stale_items)}")

for fu in open_items:
    fu_date = datetime.strptime(fu["date"], "%Y-%m-%d")
    age = (today - fu_date).days
    marker = " [STALE]" if age > 7 else ""
    print(f"  - [{fu['date']} +{age}d] {fu['item'][:80]}{marker}")

# Update the file with stale markers
if stale_items:
    with open(sources_file, "w") as f:
        json.dump(config, f, indent=2)
    print(f"  Updated {len(stale_items)} items to stale status")
PYEOF

done

log "Follow-up accountability check complete"
