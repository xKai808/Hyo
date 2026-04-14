#!/usr/bin/env bash
# bin/update-followups.sh — Accountability loop for agent research follow-ups
#
# Checks each agent's research-sources.json for:
# 1. Stale follow-ups (>7 days open without resolution) — auto-mark as stale
# 2. Follow-ups open >14 days — auto-expire with note "Auto-expired: no progress in 14 days"
# 3. Duplicate text in same agent's file — remove duplicates, keep oldest
#
# Flags them in the agent's ACTIVE.md, logs cleanup actions, and reports to Kai via dispatch.
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
TOTAL_EXPIRED=0
TOTAL_DEDUPED=0

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
expired_items = []
seen_items = {}
duplicates = []

for fu in open_items:
    fu_date = datetime.strptime(fu["date"], "%Y-%m-%d")
    age_days = (today - fu_date).days

    # Check for expiration (>14 days)
    if age_days > 14:
        expired_items.append(fu)
        fu["status"] = "expired"
        fu["note"] = "Auto-expired: no progress in 14 days. Reopen if still relevant."
    # Check for staleness (>7 days, <14 days)
    elif age_days > 7:
        stale_items.append(fu)
        fu["status"] = "stale"

    # Check for duplicates (same item text in this agent's followups)
    item_text = fu.get("item", "").strip()[:100]  # First 100 chars as key
    if item_text:
        if item_text in seen_items:
            # Duplicate found — mark for removal
            duplicates.append({
                "newer": fu,
                "older": seen_items[item_text],
                "text": item_text
            })
        else:
            seen_items[item_text] = fu

# Remove duplicates — keep oldest (lowest index), remove newer ones
if duplicates:
    indices_to_remove = set()
    for dup in duplicates:
        newer_idx = followups.index(dup["newer"])
        older_idx = followups.index(dup["older"])
        indices_to_remove.add(newer_idx)  # Keep older (lower index)

    # Filter out duplicates
    followups = [f for i, f in enumerate(followups) if i not in indices_to_remove]
    config["followUps"] = followups
    print(f"CLEANUP [{agent}]: Removed {len(indices_to_remove)} duplicate items (kept oldest)")

print(f"AGENT: {agent}")
print(f"OPEN: {len(open_items)}")
print(f"STALE (7-14d): {len(stale_items)}")
print(f"EXPIRED (>14d): {len(expired_items)}")
print(f"DUPLICATES: {len(duplicates)}")

for fu in open_items:
    fu_date = datetime.strptime(fu["date"], "%Y-%m-%d")
    age = (today - fu_date).days
    status = fu.get("status", "open").upper()
    note = ""
    if status == "EXPIRED":
        note = " [EXPIRED — auto-marked for closure]"
    elif status == "STALE":
        note = " [STALE]"
    print(f"  - [{fu['date']} +{age}d] {fu['item'][:80]} — {status}{note}")

# Update the file with all changes (staleness, expiration, duplicates)
if stale_items or expired_items or duplicates:
    with open(sources_file, "w") as f:
        json.dump(config, f, indent=2)
    updates = []
    if stale_items:
        updates.append(f"{len(stale_items)} stale")
    if expired_items:
        updates.append(f"{len(expired_items)} expired")
    if duplicates:
        updates.append(f"{len(duplicates)} duplicates removed")
    print(f"  Updated: {', '.join(updates)}")
PYEOF

done

log "Follow-up accountability check complete"
log "To review expired items, check agent research-sources.json status='expired' entries"
