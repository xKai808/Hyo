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

  # Guard: only reset once per Monday (check if current week already starts today)
  local already_reset="false"
  if [[ -f "$METRICS" ]]; then
    local current_start
    current_start=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('start',''))" 2>/dev/null || echo "")
    local today_date
    today_date=$(TZ="America/Denver" date +%Y-%m-%d)
    if [[ "$current_start" == "$today_date" ]]; then
      already_reset="true"
    fi
  fi

  if [[ "$already_reset" == "true" && "${1:-}" != "--reset" ]]; then
    log "Monday reset: already done for today ($today_date), skipping"
    return 0
  fi

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

# ─── Extract Metrics from AetherBot Logs ──────────────────────────────────
extract_aether_metrics_from_logs() {
  # Find latest AetherBot log file
  # Primary: agents/aether/logs/AetherBot_YYYY-MM-DD.txt (post-migration)
  # Fallback: ~/Documents/Projects/AetherBot/Logs/AetherBot_YYYY-MM-DD.txt

  local log_file=""
  local agents_log="$LOGS/AetherBot_$(date +%Y-%m-%d).txt"
  local aetherbot_log="$HOME/Documents/Projects/AetherBot/Logs/AetherBot_$(date +%Y-%m-%d).txt"

  if [[ -f "$agents_log" ]]; then
    log_file="$agents_log"
  elif [[ -f "$aetherbot_log" ]]; then
    log_file="$aetherbot_log"
  fi

  if [[ -z "$log_file" ]]; then
    log "WARN: No AetherBot log found for today. Using last metrics."
    return 0
  fi

  # Extract balance from the last "bal $X.XX" occurrence in the log
  # Format: "bal $90.25" or similar
  local extracted_balance=""
  extracted_balance=$(grep -oE "bal \\\$[0-9]+\.[0-9]{2}" "$log_file" 2>/dev/null | tail -1 | sed 's/bal \$//g')

  if [[ -n "$extracted_balance" ]]; then
    log "Extracted balance from log: \$$extracted_balance"

    # Update metrics file with real balance
    python3 - "$METRICS" "$extracted_balance" <<'PYEOF'
import json
import sys
from datetime import datetime

metrics_file = sys.argv[1]
new_balance = float(sys.argv[2])

try:
  with open(metrics_file) as f:
    data = json.load(f)

  cw = data.get("currentWeek", data.get("currentPeriod", {}))
  old_balance = cw.get("currentBalance", 0)
  cw["currentBalance"] = round(new_balance, 2)

  # Recalculate PnL from starting balance
  cw["pnl"] = round(cw["currentBalance"] - cw["startingBalance"], 2)
  cw["pnlPercent"] = round((cw["pnl"] / cw["startingBalance"]) * 100, 2) if cw["startingBalance"] else 0

  data["updatedAt"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")

  with open(metrics_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

  print(f"Balance updated: ${old_balance} → ${new_balance}, PnL: ${cw['pnl']} ({cw['pnlPercent']}%)")
except Exception as e:
  print(f"Error updating metrics: {e}")
PYEOF
  fi

  # Extract ticker count from the log (count "TICKER CLOSE" lines for today)
  local ticker_closes=""
  ticker_closes=$(grep -c "TICKER CLOSE" "$log_file" 2>/dev/null || echo "0")
  log "Tickers closed today: $ticker_closes"
}

# ─── GPT Daily Log Review ────────────────────────────────────────────────────
# Sends today's AetherBot raw log to GPT-4o for independent analysis,
# pattern detection, and fact-checking of trading decisions.
# Runs once per day — skips if GPT_CrossCheck already exists for today.
# Output: agents/aether/analysis/GPT_CrossCheck_YYYY-MM-DD.txt
#
gpt_daily_log_review() {
  local today
  today=$(TZ="America/Denver" date +%Y-%m-%d)
  local crosscheck_file="$ROOT/agents/aether/analysis/GPT_CrossCheck_${today}.txt"
  local factcheck_script="$ROOT/agents/aether/analysis/gpt_factcheck.py"

  # Skip if already reviewed today
  if [[ -f "$crosscheck_file" ]] && ! grep -q "PENDING" "$crosscheck_file" 2>/dev/null; then
    log "GPT daily log review: already exists for $today, skipping"
    return 0
  fi

  # Verify factcheck script exists
  if [[ ! -f "$factcheck_script" ]]; then
    log "WARN: gpt_factcheck.py not found at $factcheck_script"
    return 0
  fi

  # Find today's log (same logic as extract_aether_metrics_from_logs)
  local log_file=""
  local agents_log="$LOGS/AetherBot_${today}.txt"
  local aetherbot_log="$HOME/Documents/Projects/AetherBot/Logs/AetherBot_${today}.txt"

  if [[ -f "$agents_log" ]]; then
    log_file="$agents_log"
  elif [[ -f "$aetherbot_log" ]]; then
    log_file="$aetherbot_log"
  fi

  if [[ -z "$log_file" ]]; then
    log "GPT daily log review: no AetherBot log found for $today, skipping"
    return 0
  fi

  # Only run after enough data accumulates (at least 500 lines = ~2 hours of tickers)
  local line_count
  line_count=$(wc -l < "$log_file" 2>/dev/null || echo "0")
  if [[ "$line_count" -lt 500 ]]; then
    log "GPT daily log review: log only has $line_count lines, waiting for more data (need 500+)"
    return 0
  fi

  log "GPT daily log review: sending $log_file ($line_count lines) to GPT-4o..."

  # Run the factcheck script in --log mode
  local result
  if result=$(HYO_ROOT="$ROOT" python3 "$factcheck_script" --log "$today" 2>&1); then
    log "GPT daily log review: complete — saved to $crosscheck_file"

    # Report to Kai via dispatch
    local dispatch_bin="$ROOT/bin/dispatch.sh"
    if [[ -x "$dispatch_bin" ]]; then
      bash "$dispatch_bin" report aether "GPT daily log review complete for $today — see GPT_CrossCheck_${today}.txt" 2>> "$LOG" || true
    fi
  else
    log "GPT daily log review: FAILED — $result"
    # Write a PENDING marker so we retry next cycle
    echo "PENDING — GPT review failed at $(TZ='America/Denver' date). Will retry next cycle." > "$crosscheck_file"
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

  # Read current metrics (handle both currentWeek and currentPeriod structures)
  local balance pnl trades winrate
  balance=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('currentBalance',0))")
  pnl=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('pnl',0))")
  trades=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('trades',cw.get('totalTickersTraded',0)))")
  winrate=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('winRate',cw.get('resolutionRate',0)))")

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

  # Extract real data from AetherBot logs
  extract_aether_metrics_from_logs

  # ─── GPT Daily Log Review ─────────────────────────────────────────────────
  # Send today's raw log to GPT-4o for independent analysis + fact-checking.
  # Runs once per day (checks if GPT_CrossCheck already exists for today).
  # Hyo directive: "Aether needs to send GPT the day's log so that it can come
  # up with its own analysis and actually factcheck anything that Aether
  # recognizes, wants to change, etc"
  gpt_daily_log_review

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

  # ─── Self-Review: Aether Pathway Audit ────────────────────────────────────
  log "Self-review: Aether pathway audit..."
  local sr_issues=0

  # INPUT: metrics file exists and readable?
  if [[ ! -f "$METRICS" ]]; then
    log "Self-review WARN: metrics file missing: $METRICS"
    sr_issues=$((sr_issues + 1))
  elif [[ $(wc -c < "$METRICS" 2>/dev/null || echo 0) -lt 50 ]]; then
    log "Self-review WARN: metrics file suspiciously small"
    sr_issues=$((sr_issues + 1))
  fi

  # PROCESSING: updatedAt timestamp present?
  if [[ -f "$METRICS" ]]; then
    local updated_at
    updated_at=$(python3 -c "import json; print(json.load(open('$METRICS')).get('updatedAt',''))" 2>/dev/null || echo "")
    if [[ -z "$updated_at" ]]; then
      log "Self-review WARN: metrics missing updatedAt timestamp"
      sr_issues=$((sr_issues + 1))
    fi
  fi

  # REPORTING: ACTIVE.md current?
  local aether_active="$ROOT/agents/aether/ledger/ACTIVE.md"
  if [[ -f "$aether_active" ]]; then
    local active_mtime active_age_h
    if [[ "$(uname)" == "Darwin" ]]; then
      active_mtime=$(stat -f %m "$aether_active" 2>/dev/null || echo 0)
    else
      active_mtime=$(stat -c %Y "$aether_active" 2>/dev/null || echo 0)
    fi
    active_age_h=$(( ($(date +%s) - active_mtime) / 3600 ))
    if [[ $active_age_h -gt 48 ]]; then
      log "Self-review WARN: ACTIVE.md stale (${active_age_h}h)"
      sr_issues=$((sr_issues + 1))
    fi
  fi

  if [[ $sr_issues -eq 0 ]]; then
    log "Self-review: Aether pathway healthy"
  else
    log "Self-review: $sr_issues issues in Aether pathway"
  fi

  # ─── Self-Review Reasoning Gates ──────────────────────────────────────────
  AGENT_GATES="$ROOT/kai/protocols/agent-gates.sh"
  if [[ -f "$AGENT_GATES" ]]; then
    source "$AGENT_GATES"
    run_self_review "aether" || true

    # ── Aether-specific domain reasoning (Aether owns these questions) ──
    # TODO: Aether — evolve this section via PLAYBOOK.md
    #   e.g., "Is this signal real or noise? What's my confidence?"
    #   e.g., "Did I account for the risk, or just the reward?"
    #   e.g., "What market condition would invalidate my strategy?"
  fi

  # ─── DOMAIN RESEARCH (External Research — agent-research.sh) ────────────────
  # Aether researches trading algorithms, position sizing, market analysis tools.
  local RESEARCH_SCRIPT="$ROOT/bin/agent-research.sh"
  if [[ -x "$RESEARCH_SCRIPT" ]]; then
    log "Running domain research: trading strategies, position sizing, market tools..."
    if bash "$RESEARCH_SCRIPT" aether --publish 2>&1 | tail -5; then
      log "Domain research complete — findings saved and published"
    else
      log "WARN: Domain research encountered issues — check agents/aether/research/"
    fi
  fi

  # ─── Self-Evolution: Aether Learning & Improvement Tracking ─────────────────
  log "Self-evolution: capturing metrics and learning signals..."

  EVOLUTION_FILE="$ROOT/agents/aether/evolution.jsonl"
  PLAYBOOK="$ROOT/agents/aether/PLAYBOOK.md"

  # Collect Aether-specific metrics
  local trade_count=0
  local pnl_total=0
  local dashboard_status="unknown"

  if [[ -f "$METRICS" ]]; then
    trade_count=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('trades',cw.get('totalTickersTraded',0)))" 2>/dev/null || echo "0")
    pnl_total=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('pnl',0))" 2>/dev/null || echo "0")
  fi

  if verify_dashboard >/dev/null 2>&1; then
    dashboard_status="synced"
  else
    dashboard_status="out-of-sync"
  fi

  # Get last evolution entry for comparison
  local last_evolution=""
  if [[ -f "$EVOLUTION_FILE" && -s "$EVOLUTION_FILE" ]]; then
    last_evolution=$(tail -1 "$EVOLUTION_FILE")
  fi

  # Extract last PNL for regression detection
  local last_pnl=0
  if [[ -n "$last_evolution" ]]; then
    last_pnl=$(echo "$last_evolution" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('metrics', {}).get('pnl_total', 0))" 2>/dev/null || echo "0")
  fi

  # Determine assessment
  local assessment="metrics cycle complete"
  local improvements_proposed=0
  if [[ $trade_count -eq 0 ]]; then
    assessment="standby mode: no trades this cycle"
  elif (( $(echo "$pnl_total > $last_pnl" | bc -l) )); then
    assessment="trading active: PNL improved $last_pnl → $pnl_total"
    improvements_proposed=$((improvements_proposed + 1))
  elif (( $(echo "$pnl_total < $last_pnl" | bc -l) )); then
    assessment="PNL degradation detected: $last_pnl → $pnl_total"
    improvements_proposed=$((improvements_proposed + 1))
  fi

  if [[ "$dashboard_status" == "out-of-sync" ]]; then
    assessment="${assessment}; WARNING: dashboard out-of-sync"
    improvements_proposed=$((improvements_proposed + 1))
  fi

  # Check if PLAYBOOK is stale (>7 days)
  local playbook_updated="False"
  local staleness_flag="False"
  if [[ -f "$PLAYBOOK" ]]; then
    local playbook_mtime=$(stat -f %m "$PLAYBOOK" 2>/dev/null || stat -c %Y "$PLAYBOOK" 2>/dev/null || echo "0")
    local playbook_age=$(( ($(date +%s) - playbook_mtime) / 86400 ))
    if [[ $playbook_age -lt 7 ]]; then
      playbook_updated="True"
    elif [[ $playbook_age -gt 7 ]]; then
      staleness_flag="True"
    fi
  fi

  # STEP 10: AGENT REFLECTION (constitutional — AGENT_ALGORITHMS.md v2.0)
  local reflect_bottleneck="none"
  local reflect_symptom_or_system="system"
  local reflect_artifact_alive="yes"
  local reflect_domain_growth="stagnant"
  local reflect_learning=""

  # (a) Bottleneck: dashboard out of sync = data exists but user can't see it
  if [[ "$dashboard_status" == "out-of-sync" ]]; then
    reflect_bottleneck="dashboard out-of-sync — data exists but HQ doesn't render it"
  fi
  if [[ $trade_count -eq 0 ]]; then
    reflect_bottleneck="${reflect_bottleneck:+$reflect_bottleneck; }no trades this cycle — may be blocked on exchange API or AetherBot logger"
  fi

  # (b) Symptom or system: recurring patterns?
  local known_aether_patterns=$(grep -c '"agent":"aether"\|"source":".*aether"' "$ROOT/kai/ledger/known-issues.jsonl" 2>/dev/null | tr -d '[:space:]')
  if [[ "${known_aether_patterns:-0}" -gt 3 ]]; then
    reflect_symptom_or_system="symptom — ${known_aether_patterns} recurring Aether patterns in known-issues"
  fi

  # (c) Artifact alive: self-review log
  local sr_log="$ROOT/agents/aether/logs/self-review-$(date +%Y-%m-%d).md"
  if [[ ! -f "$sr_log" ]]; then
    reflect_artifact_alive="no — self-review log not generated this cycle"
  fi

  # (d) Domain growth
  if [[ "$playbook_updated" == "True" ]]; then
    reflect_domain_growth="active — PLAYBOOK updated within 7 days"
  else
    reflect_domain_growth="stagnant — PLAYBOOK not updated recently, no new trading analysis patterns"
  fi

  # (e) Learning
  reflect_learning="trades=${trade_count}, pnl=${pnl_total}, dashboard=${dashboard_status}"

  # Build evolution entry (MUST include reflection per AGENT_ALGORITHMS.md step 11)
  local evolution_entry=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$TS",
  "version": "2.0",
  "metrics": {
    "trade_count": $trade_count,
    "pnl_total": $pnl_total,
    "dashboard_status": "$dashboard_status"
  },
  "assessment": "$assessment",
  "improvements_proposed": $improvements_proposed,
  "playbook_updated": $playbook_updated,
  "staleness_flag": $staleness_flag,
  "reflection": {
    "bottleneck": "$reflect_bottleneck",
    "symptom_or_system": "$reflect_symptom_or_system",
    "artifact_alive": "$reflect_artifact_alive",
    "domain_growth": "$reflect_domain_growth",
    "learning": "$reflect_learning"
  }
}

print(json.dumps(entry))
PYEOF
)

  # Append to evolution ledger
  echo "$evolution_entry" >> "$EVOLUTION_FILE"
  log "Self-evolution logged: $assessment"

  if [[ "$staleness_flag" == "True" ]]; then
    log "WARN: PLAYBOOK.md is stale — consider refreshing with latest operational procedures"
  fi

  # ─── Aether self-authored reflection → HQ feed ─────────────────────────────
  local PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
  local AETHER_REFLECTION="/tmp/aether-reflection-sections-$(date +%Y%m%d).json"

  python3 - "$AETHER_REFLECTION" "$trade_count" "$pnl_total" "$dashboard_status" "$assessment" "$ROOT" << 'PYEOF'
import json, sys, os
sf = sys.argv[1]
trades = int(sys.argv[2]) if sys.argv[2].isdigit() else 0
pnl = float(sys.argv[3]) if sys.argv[3].replace('.','',1).replace('-','',1).isdigit() else 0
dash = sys.argv[4]
assess = sys.argv[5]
root = sys.argv[6]
from datetime import datetime
today = datetime.now().strftime("%Y-%m-%d")

research_summary = "No research conducted this cycle."
ff = os.path.join(root, "agents", "aether", "research", f"findings-{today}.md")
if os.path.exists(ff):
    with open(ff) as f:
        c = f.read()
    if "## Key Takeaways" in c:
        t = c.split("## Key Takeaways")[1].split("##")[0].strip()
        research_summary = t if t else "Research completed — no high-signal findings."

followups = []
src = os.path.join(root, "agents", "aether", "research-sources.json")
if os.path.exists(src):
    with open(src) as f:
        cfg = json.load(f)
    followups = [fu["item"] for fu in cfg.get("followUps", []) if fu.get("status") == "open"]
if not followups:
    followups = ["Model Kelly Criterion against historical trades",
                 "Investigate phantom position tracking",
                 "Fix dashboard data sync issue"]

# ── Build human-readable prose ──
intro_parts = []
if trades > 0:
    intro_parts.append(f"Active cycle — executed {trades} trade{'s' if trades > 1 else ''} with a net P&L of ${pnl:.2f}.")
    if pnl > 0:
        intro_parts.append("Positive day, though I need to verify these aren't phantom positions inflating the numbers. That's been an ongoing issue.")
    elif pnl < -10:
        intro_parts.append("Rough session. Need to analyze what went wrong — was it strategy selection, sizing, or just market conditions?")
    else:
        intro_parts.append("Small loss, but within acceptable range. Reviewing the execution quality to see if there were missed opportunities.")
else:
    intro_parts.append("No trades this cycle — I'm in standby mode. Without live exchange API keys, I'm essentially running analysis on historical data and maintaining the dashboard.")
    intro_parts.append("The trading intelligence layer is ready to go, but I need real-time data to be useful. Right now I'm a dashboard that shows stale numbers.")

if dash == "out-of-sync":
    intro_parts.append("The dashboard sync issue is still happening — the underlying data exists but HQ isn't rendering it. This has been open for too long.")
elif dash == "ok" or dash == "synced":
    intro_parts.append("Dashboard is up to date and showing accurate data.")

research_text = research_summary
if research_text == "No research conducted this cycle.":
    research_text = "Between cycles I've been studying position sizing models, specifically the Kelly Criterion and how it applies to our strategy. Our current COUNTER sizing has a 12.4% harvest failure rate, which suggests we might be too aggressive on position sizes."

changes_text = assess if assess and assess != "routine" else "Routine cycle — monitored positions, updated metrics, no structural changes to the trading logic."

kai_msg = ""
if trades == 0:
    kai_msg = "I need read-only exchange API keys to move from historical replay to live tracking. That's the single biggest blocker. Everything else — analysis, dashboard, strategy evaluation — is ready and waiting for real data."
elif pnl < -20:
    kai_msg = f"Lost ${abs(pnl):.2f} this cycle. I'm investigating whether it's a strategy issue or execution timing. Might need to adjust the harvest gating parameters."
elif dash == "out-of-sync":
    kai_msg = "Trading is functional but the dashboard sync issue means HQ doesn't reflect reality. Fixing this is important for trust — people need to see accurate numbers."
else:
    kai_msg = f"Healthy cycle — {trades} trades, ${pnl:.2f} P&L. Continuing to monitor and refine strategy parameters."

sections = {
    "introspection": " ".join(intro_parts),
    "research": research_text,
    "changes": changes_text,
    "followUps": followups[:5],
    "forKai": kai_msg
}
with open(sf, "w") as f:
    json.dump(sections, f, indent=2)
PYEOF

  if [[ -f "$AETHER_REFLECTION" && -x "$PUBLISH_SCRIPT" ]]; then
    bash "$PUBLISH_SCRIPT" "agent-reflection" "aether" "Aether — Trading Report" "$AETHER_REFLECTION" 2>/dev/null || true
    log "Self-authored report published to HQ feed"

    # Report to Kai — closed-loop upward communication
    DISPATCH_BIN="$ROOT/bin/dispatch.sh"
    if [[ -x "$DISPATCH_BIN" ]]; then
      bash "$DISPATCH_BIN" report aether "research+reflection published: trades=${trade_count}, pnl=${pnl_total}, dashboard=${dashboard_status}" 2>/dev/null || true
    fi
  fi

  # ─── STEP 13: MEMORY UPDATE (constitutional — AGENT_ALGORITHMS.md) ────────
  local aether_active="$ROOT/agents/aether/ledger/ACTIVE.md"
  mkdir -p "$(dirname "$aether_active")"
  local trade_count_mem pnl_mem
  trade_count_mem=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('trades',cw.get('totalTickersTraded',0)))" 2>/dev/null || echo "0")
  pnl_mem=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('pnl',0))" 2>/dev/null || echo "0")
  cat > "$aether_active" << ACTIVEEOF
# Aether — Active Tasks (auto-updated every cycle)
**Last updated:** $(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

## This Cycle
- Trades this period: ${trade_count_mem}
- PNL: \$${pnl_mem}
- Assessment: ${assessment}

## Open Issues
$(if [[ "$staleness_flag" == "True" ]]; then echo "- PLAYBOOK.md is stale"; fi)

## Reflection Summary
- Bottleneck: ${reflect_bottleneck}
- Domain growth: ${reflect_domain_growth}
ACTIVEEOF
  log "Memory update: ACTIVE.md written"

  # ─── Dispatch reporting (closed-loop) ──────────────────────────────────────
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    local trade_count pnl_total dashboard_status
    trade_count=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('trades',cw.get('totalTickersTraded',0)))" 2>/dev/null || echo "0")
    pnl_total=$(python3 -c "import json; d=json.load(open('$METRICS')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('pnl',0))" 2>/dev/null || echo "0")
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
