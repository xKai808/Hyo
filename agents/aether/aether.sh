#!/usr/bin/env bash
# agents/aether/aether.sh — Aether metrics collector + HQ uploader
#
# Runs on a schedule (every 15 min via launchd/cron). Does three things:
#   1. Reads trade data from the configured exchange/source
#   2. Updates website/data/aether-metrics.json (consumed by HQ dashboard)
#   3. Pushes summary to HQ API (so live dashboard updates without redeploy)
#
# Monday reset: at 00:00 MT on Monday, current week → last week, current resets.
#
# Usage:
#   bash aether.sh              # normal metrics update
#   bash aether.sh --reset      # force Monday reset (manual)
#   bash aether.sh --record-trade '{"side":"buy","pair":"BTC/USD","price":67500,"qty":0.01,"pnl":12.50}'
#
# Env vars:
#   HYO_ROOT           — project root (default: ~/Documents/Projects/Hyo)
#   AETHER_SOURCE   — data source: "file" (default), "ccxt", "manual"
#   AETHER_EXCHANGE  — exchange for ccxt mode (e.g., "binance", "coinbase")
#   AETHER_API_KEY   — exchange API key (read-only!)
#   AETHER_API_SECRET — exchange API secret

set -uo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
METRICS="$ROOT/website/data/aether-metrics.json"
TRADES_LOG="$ROOT/agents/aether/ledger/trades.jsonl"
LOGS="$ROOT/agents/aether/logs"
SECRETS="$ROOT/agents/nel/security"

mkdir -p "$LOGS" "$(dirname "$TRADES_LOG")"

LOG="$LOGS/aether-$(date +%Y-%m-%d).log"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S-06:00")

log() { echo "[$TS] $*" | tee -a "$LOG"; }

# ─── Monday Reset ─────────────────────────────────────────────────────────────
check_monday_reset() {
  local dow
  dow=$(TZ="America/Denver" date +%u)  # 1=Monday
  local hour
  hour=$(TZ="America/Denver" date +%H)

  if [[ "$dow" == "1" && "$hour" == "00" ]] || [[ "${1:-}" == "--reset" ]]; then
    log "Monday reset triggered"
    python3 - "$METRICS" <<'PYEOF'
import json, sys
from datetime import datetime, timedelta

f = sys.argv[1]
with open(f) as fh:
    data = json.load(fh)

# Move current → last
cw = data["currentWeek"]
data["lastWeek"] = {
    "start": cw["start"],
    "end": cw["end"],
    "startingBalance": cw["startingBalance"],
    "endingBalance": cw["currentBalance"],
    "pnl": cw["pnl"],
    "pnlPercent": cw["pnlPercent"],
    "trades": cw["trades"],
    "wins": cw["wins"],
    "losses": cw["losses"],
    "winRate": cw["winRate"],
    "stoplossTriggers": cw["stoplossTriggers"],
    "harvestEvents": cw["harvestEvents"],
    "bestStrategy": max(cw.get("strategies", [{"name":"—","pnl":0}]), key=lambda s: s["pnl"])["name"] if cw.get("strategies") else "—",
    "worstStrategy": min(cw.get("strategies", [{"name":"—","pnl":0}]), key=lambda s: s["pnl"])["name"] if cw.get("strategies") else "—",
}

# Add to weekly history
data["allTimeStats"]["weeklyHistory"].append({
    "start": cw["start"],
    "end": cw["end"],
    "pnl": cw["pnl"],
    "trades": cw["trades"],
    "winRate": cw["winRate"],
})
data["allTimeStats"]["totalPnl"] += cw["pnl"]
data["allTimeStats"]["totalTrades"] += cw["trades"]

# Reset current week
from datetime import datetime, timedelta
now = datetime.now()
# Find this Monday
monday = now - timedelta(days=now.weekday())
sunday = monday + timedelta(days=6)
carry_balance = cw["currentBalance"]

data["currentWeek"] = {
    "start": monday.strftime("%Y-%m-%d"),
    "end": sunday.strftime("%Y-%m-%d"),
    "startingBalance": carry_balance,
    "currentBalance": carry_balance,
    "pnl": 0.0,
    "pnlPercent": 0.0,
    "trades": 0,
    "wins": 0,
    "losses": 0,
    "winRate": 0.0,
    "stoplossTriggers": 0,
    "harvestEvents": 0,
    "strategies": [{"name": s["name"], "status": s["status"], "pnl": 0.0, "trades": 0, "winRate": 0.0, "lastAction": s["lastAction"]} for s in cw.get("strategies", [])],
    "dailyPnl": [{"date": (monday + timedelta(days=i)).strftime("%Y-%m-%d"), "pnl": 0.0, "balance": carry_balance, "trades": 0} for i in range(7)],
    "recentTrades": [],
}

with open(f, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("Reset complete")
PYEOF
    log "Monday reset: current week archived, new week started"
  fi
}

# ─── Record Trade ─────────────────────────────────────────────────────────────
record_trade() {
  local trade_json="$1"
  log "Recording trade: $trade_json"

  # Append to trades JSONL ledger
  echo "$trade_json" >> "$TRADES_LOG"

  # Update metrics JSON
  python3 - "$METRICS" "$trade_json" <<'PYEOF'
import json, sys
from datetime import datetime

metrics_file = sys.argv[1]
trade = json.loads(sys.argv[2])

with open(metrics_file) as f:
    data = json.load(f)

cw = data["currentWeek"]
pnl = float(trade.get("pnl", 0))
is_win = pnl > 0

# Update totals
cw["trades"] += 1
cw["pnl"] = round(cw["pnl"] + pnl, 2)
cw["currentBalance"] = round(cw["startingBalance"] + cw["pnl"], 2)
cw["pnlPercent"] = round((cw["pnl"] / cw["startingBalance"]) * 100, 2) if cw["startingBalance"] else 0

if is_win:
    cw["wins"] += 1
else:
    cw["losses"] += 1
cw["winRate"] = round((cw["wins"] / cw["trades"]) * 100, 1) if cw["trades"] else 0

# Stoploss / harvest events
if trade.get("type") == "stoploss":
    cw["stoplossTriggers"] += 1
if trade.get("type") == "harvest":
    cw["harvestEvents"] += 1

# Update daily PNL for today
today = datetime.now().strftime("%Y-%m-%d")
for day in cw["dailyPnl"]:
    if day["date"] == today:
        day["pnl"] = round(day["pnl"] + pnl, 2)
        day["balance"] = cw["currentBalance"]
        day["trades"] += 1
        break

# Update strategy
strategy_name = trade.get("strategy", "")
for s in cw["strategies"]:
    if s["name"].lower() == strategy_name.lower():
        s["pnl"] = round(s["pnl"] + pnl, 2)
        s["trades"] += 1
        s_wins = s.get("_wins", 0) + (1 if is_win else 0)
        s["_wins"] = s_wins
        s["winRate"] = round((s_wins / s["trades"]) * 100, 1)
        s["lastAction"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")
        if pnl > 0:
            s["status"] = "active"
        break

# Add to recent trades (keep last 50)
cw["recentTrades"].insert(0, {
    "ts": datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00"),
    "side": trade.get("side", "—"),
    "pair": trade.get("pair", "—"),
    "price": trade.get("price", 0),
    "qty": trade.get("qty", 0),
    "pnl": pnl,
    "strategy": strategy_name,
    "type": trade.get("type", "market"),
})
if len(cw["recentTrades"]) > 50:
    cw["recentTrades"] = cw["recentTrades"][:50]

data["updatedAt"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")

with open(metrics_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Trade recorded: {trade.get('pair','')} {trade.get('side','')} PNL={pnl}")
PYEOF
}

# ─── GPT Fact-Check ──────────────────────────────────────────────────────────
# Aether owns all GPT/OpenAI API calls for trade verification.
# Kai does NOT call GPT. If something needs external LLM validation,
# it routes through Aether.
#
# Usage: fact_check "Is BTC/USD above the 200-day MA?" → returns GPT's answer
# Usage: fact_check_trade '{"pair":"BTC/USD","side":"buy","pnl":12.50}' → validates trade logic
#
fact_check() {
  local question="$1"
  local api_key_file="$SECRETS/openai.key"

  if [[ ! -f "$api_key_file" ]]; then
    log "WARN: no OpenAI API key at $api_key_file — fact-check skipped"
    echo '{"status":"skipped","reason":"no API key"}'
    return 0
  fi

  local api_key
  api_key=$(cat "$api_key_file" | tr -d '[:space:]')

  local response
  response=$(curl -sf -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $api_key" \
    -d "$(python3 -c "
import json
print(json.dumps({
    'model': 'gpt-4o-mini',
    'messages': [
        {'role': 'system', 'content': 'You are a trading fact-checker for a portfolio intelligence system called Aether. Give concise, data-driven answers. If you cannot verify something, say so clearly. Always include confidence level (high/medium/low).'},
        {'role': 'user', 'content': '''$question'''}
    ],
    'max_tokens': 500,
    'temperature': 0.2
}))
")" 2>> "$LOG")

  if [[ -z "$response" ]]; then
    log "WARN: GPT fact-check failed (empty response)"
    echo '{"status":"error","reason":"empty response"}'
    return 1
  fi

  local answer
  answer=$(echo "$response" | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin)
    print(r['choices'][0]['message']['content'])
except Exception as e:
    print(f'Parse error: {e}')
")

  log "Fact-check result: ${answer:0:200}"
  echo "$answer"
}

# Validate a trade against market conditions before recording
fact_check_trade() {
  local trade_json="$1"
  local pair side pnl strategy
  pair=$(echo "$trade_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('pair','unknown'))")
  side=$(echo "$trade_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('side','unknown'))")
  pnl=$(echo "$trade_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('pnl',0))")
  strategy=$(echo "$trade_json" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('strategy','unknown'))")

  fact_check "Trade validation request: $pair $side with PNL \$$pnl using $strategy strategy. Does this trade make sense given current market conditions? Flag any concerns about size, direction, or timing."
}

# ─── Push to HQ API ──────────────────────────────────────────────────────────
push_to_hq() {
  local token_file="$SECRETS/founder.token"
  if [[ ! -f "$token_file" ]]; then
    log "WARN: no founder token — skipping HQ push"
    return 0
  fi
  local token
  token=$(cat "$token_file" | tr -d '[:space:]')

  # Read current metrics
  local balance pnl trades winrate
  balance=$(python3 -c "import json; d=json.load(open('$METRICS')); print(d['currentWeek']['currentBalance'])")
  pnl=$(python3 -c "import json; d=json.load(open('$METRICS')); print(d['currentWeek']['pnl'])")
  trades=$(python3 -c "import json; d=json.load(open('$METRICS')); print(d['currentWeek']['trades'])")
  winrate=$(python3 -c "import json; d=json.load(open('$METRICS')); print(d['currentWeek']['winRate'])")

  local payload
  payload=$(python3 -c "
import json
print(json.dumps({
    'agent': 'aether',
    'event': 'metrics update',
    'data': {
        'balance': $balance,
        'pnl': '$pnl',
        'totalTrades': $trades,
        'winRate': '$winrate',
        'state': 'active' if $trades > 0 else 'standby',
        'decisions': $trades,
    }
}))
")

  curl -sf -X POST "https://www.hyo.world/api/hq?action=push" \
    -H "Content-Type: application/json" \
    -H "X-Founder-Token: $token" \
    -d "$payload" \
    >> "$LOG" 2>&1 && log "HQ push: ok" || log "HQ push: failed"
}

# ─── Verify Dashboard Data ─────────────────────────────────────────────────────
verify_dashboard() {
  local api_response dashboard_ts local_ts

  # GET metrics from API to verify data landed
  api_response=$(curl -sf "https://www.hyo.world/api/aether?action=metrics" 2>> "$LOG")

  if [[ -z "$api_response" ]]; then
    log "WARN: Dashboard verification failed (empty API response)"
    local dispatch_bin="$ROOT/bin/dispatch.sh"
    if [[ -x "$dispatch_bin" ]]; then
      bash "$dispatch_bin" flag aether P2 "dashboard data verification failed: empty API response" 2>> "$LOG" || true
    fi
    return 1
  fi

  # Parse API response for updatedAt timestamp
  dashboard_ts=$(echo "$api_response" | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin)
    print(r.get('updatedAt', ''))
except Exception as e:
    print(f'')
" 2>/dev/null)

  # Parse local metrics file for updatedAt timestamp
  local_ts=$(python3 -c "import json; d=json.load(open('$METRICS')); print(d.get('updatedAt', ''))" 2>/dev/null)

  # Compare timestamps
  if [[ "$dashboard_ts" == "$local_ts" && -n "$local_ts" ]]; then
    log "Dashboard verified: data in sync (ts: $local_ts)"
    return 0
  else
    log "WARN: Dashboard out of sync — local: $local_ts, API: $dashboard_ts"
    local dispatch_bin="$ROOT/bin/dispatch.sh"
    if [[ -x "$dispatch_bin" ]]; then
      bash "$dispatch_bin" flag aether P2 "dashboard data mismatch: local ts $local_ts != API ts $dashboard_ts" 2>> "$LOG" || true
    fi
    return 1
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "=== Aether metrics run ==="

  # Init metrics file if missing
  if [[ ! -f "$METRICS" ]]; then
    log "Creating initial metrics file"
    python3 -c "
import json
from datetime import datetime, timedelta
now = datetime.now()
monday = now - timedelta(days=now.weekday())
sunday = monday + timedelta(days=6)
d = {
  'currentWeek': {
    'start': monday.strftime('%Y-%m-%d'),
    'end': sunday.strftime('%Y-%m-%d'),
    'startingBalance': 1000.0, 'currentBalance': 1000.0,
    'pnl': 0.0, 'pnlPercent': 0.0,
    'trades': 0, 'wins': 0, 'losses': 0, 'winRate': 0.0,
    'stoplossTriggers': 0, 'harvestEvents': 0,
    'strategies': [{'name': 'Grid Bot', 'status': 'standby', 'pnl': 0.0, 'trades': 0, 'winRate': 0.0, 'lastAction': now.strftime('%Y-%m-%dT%H:%M:%S-06:00')}],
    'dailyPnl': [{'date': (monday + timedelta(days=i)).strftime('%Y-%m-%d'), 'pnl': 0.0, 'balance': 1000.0, 'trades': 0} for i in range(7)],
    'recentTrades': [],
  },
  'lastWeek': {'start': '', 'end': '', 'startingBalance': 0, 'endingBalance': 0, 'pnl': 0, 'pnlPercent': 0, 'trades': 0, 'wins': 0, 'losses': 0, 'winRate': 0, 'stoplossTriggers': 0, 'harvestEvents': 0, 'bestStrategy': '—', 'worstStrategy': '—'},
  'allTimeStats': {'totalPnl': 0.0, 'totalTrades': 0, 'weeklyHistory': []},
  'updatedAt': now.strftime('%Y-%m-%dT%H:%M:%S-06:00'),
}
with open('$METRICS', 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
  fi

  # Check for Monday reset
  check_monday_reset "$@"

  # Handle --fact-check (standalone query to GPT)
  if [[ "${1:-}" == "--fact-check" ]]; then
    fact_check "${2:-'What are the current market conditions?'}"
    return 0
  fi

  # Handle --record-trade (optional: add --verify flag to fact-check before recording)
  if [[ "${1:-}" == "--record-trade" ]]; then
    local trade_data="${2:-'{}'}"

    # If --verify flag is present, fact-check before recording
    if [[ "${3:-}" == "--verify" ]]; then
      log "Pre-trade fact-check requested"
      local check_result
      check_result=$(fact_check_trade "$trade_data")
      log "Fact-check: $check_result"
      # Log the verification but always record — Aether doesn't block trades,
      # it annotates them with intelligence
      echo "$check_result"
    fi

    record_trade "$trade_data"
    push_to_hq
    return 0
  fi

  # Normal run: update timestamp + push to HQ
  python3 -c "
import json
from datetime import datetime
with open('$METRICS') as f: d = json.load(f)
d['updatedAt'] = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-06:00')
with open('$METRICS', 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
  push_to_hq
  verify_dashboard

  # ─── Dispatch reporting (closed-loop) ──────────────────────────────────────
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    local trade_count pnl_total dashboard_status
    trade_count=$(python3 -c "import json; print(json.load(open('$METRICS'))['currentWeek']['trades'])" 2>/dev/null || echo "0")
    pnl_total=$(python3 -c "import json; print(json.load(open('$METRICS'))['currentWeek']['pnl'])" 2>/dev/null || echo "0")
    if verify_dashboard >/dev/null 2>&1; then
      dashboard_status="synced"
    else
      dashboard_status="out-of-sync"
    fi
    bash "$dispatch_bin" report aether "cycle complete: ${trade_count} trades, PNL=\$${pnl_total}, dashboard: ${dashboard_status}" 2>> "$LOG" || true
  fi

  log "Metrics cycle complete"
}

# ─── Error trap for dispatch flagging ────────────────────────────────────────
trap_error() {
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    bash "$dispatch_bin" flag aether P2 "aether.sh exited with error" 2>/dev/null || true
  fi
}
trap trap_error ERR

main "$@"
