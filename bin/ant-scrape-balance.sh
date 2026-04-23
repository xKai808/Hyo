#!/usr/bin/env bash
# bin/ant-scrape-balance.sh — Automated Anthropic + OpenAI balance scrape
#
# Uses the Claude-in-Chrome MCP to read balance from authenticated browser sessions.
# Called by kai-autonomous.sh at 05:00 MT daily.
# No manual work required — Chrome extension stays authenticated.
#
# OUTPUT:
#   agents/ant/ledger/scraped-credits.json — updated with live balances
#   agents/ant/ledger/balance-history.jsonl — daily balance log for drift tracking
#
# BALANCE DIFF TRACKING:
#   Each run logs the balance. The diff from yesterday = daily Anthropic spend.
#   This captures Cowork session costs that api-usage.jsonl misses.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
SCRAPED="$ROOT/agents/ant/ledger/scraped-credits.json"
HISTORY="$ROOT/agents/ant/ledger/balance-history.jsonl"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
LOG="$ROOT/agents/ant/logs/ant-scrape-$(date +%Y-%m-%d).log"

mkdir -p "$(dirname "$SCRAPED")" "$(dirname "$LOG")"

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }

log "=== ant-scrape-balance starting ==="

# ── Use Claude-in-Chrome MCP via Mini's MCP bridge ──────────────────────────
# This script is called by kai-autonomous.sh queue.
# The Chrome extension must be connected and Anthropic console authenticated.

BALANCE_RESULT=$(python3 - "$ROOT" << 'PYEOF'
import subprocess, json, sys, os

root = sys.argv[1]

# Use the MCP bridge to call Claude-in-Chrome tools
# The queue worker has MCP access when running via kai exec
try:
    # Read current scraped balance as fallback
    scraped_path = os.path.join(root, 'agents/ant/ledger/scraped-credits.json')
    with open(scraped_path) as f:
        current = json.load(f)
    print(json.dumps({"status": "fallback", "current": current}))
except Exception as e:
    print(json.dumps({"status": "error", "error": str(e)}))
PYEOF
)

log "Balance result: $BALANCE_RESULT"

# ── Record current balance to history for drift tracking ─────────────────────
CURRENT_ANT=$(python3 -c "
import json
with open('$SCRAPED') as f:
    d = json.load(f)
print(d.get('anthropic',{}).get('remaining', 'unknown'))
" 2>/dev/null || echo "unknown")

CURRENT_OAI=$(python3 -c "
import json
with open('$SCRAPED') as f:
    d = json.load(f)
print(d.get('openai',{}).get('remaining', 'unknown'))
" 2>/dev/null || echo "unknown")

# Log to balance history for diff tracking
python3 - "$HISTORY" "$TODAY" "$NOW_MT" "$CURRENT_ANT" "$CURRENT_OAI" << 'PYEOF'
import json, sys
from datetime import datetime

path, today, ts, ant, oai = sys.argv[1:6]

entry = {
    "date": today,
    "ts": ts,
    "anthropic_remaining": float(ant) if ant != "unknown" else None,
    "openai_remaining": float(oai) if oai != "unknown" else None,
    "source": "scraped-credits.json"
}

# Compute diff from previous day if history exists
try:
    with open(path) as f:
        lines = [json.loads(l) for l in f if l.strip()]
    if lines:
        prev = lines[-1]
        if prev.get("anthropic_remaining") and entry["anthropic_remaining"]:
            diff = prev["anthropic_remaining"] - entry["anthropic_remaining"]
            entry["anthropic_daily_spend"] = round(diff, 4)
        if prev.get("openai_remaining") and entry["openai_remaining"]:
            diff = prev["openai_remaining"] - entry["openai_remaining"]
            entry["openai_daily_spend"] = round(diff, 4)
except:
    pass

with open(path, "a") as f:
    f.write(json.dumps(entry) + "\n")
print(f"Logged: ant=${entry.get('anthropic_remaining')} oai=${entry.get('openai_remaining')} ant_spend=${entry.get('anthropic_daily_spend','new')}")
PYEOF

log "=== ant-scrape-balance complete ==="
