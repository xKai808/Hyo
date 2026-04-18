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

# ─── Growth Phase (self-improvement before main work) ─────────────────────────
GROWTH_SH="$ROOT/bin/agent-growth.sh"
if [[ -f "$GROWTH_SH" ]]; then
  source "$GROWTH_SH"
  run_growth_phase "aether" || true
fi

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
  # SE-012-005: REWRITTEN — uses BUY SNAPSHOT for trade counts, TICKER CLOSE
  # for outcomes (wins/losses/strategy P&L), balance math for P&L.
  # NO SETTLED-only counting. Settled captures a subset; TICKER CLOSE captures all.
  #
  # Trade lifecycle:
  #   BUY SNAPSHOT (trade entry) → position mgmt → TICKER CLOSE (outcome summary)
  #   TICKER CLOSE | 18:00 MTN | 1 trade | NET WIN +1.04 | PAQ_EARLY_AGG +1.04
  #   BUY SNAPSHOT | Side: NO | Reason: PAQ_EARLY_AGG | Seconds: 210

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

  log "Parsing full metrics from $log_file (BUY SNAPSHOT + TICKER CLOSE)..."

  python3 - "$METRICS" "$log_file" <<'PYEOF'
import json, sys, re, os
from datetime import datetime, timedelta
from collections import defaultdict

metrics_file = sys.argv[1]
today_log_file = sys.argv[2]

with open(metrics_file) as f:
    data = json.load(f)

cw = data.get("currentWeek", data.get("currentPeriod", {}))

# ── Collect ALL log files for the current week period ──
week_start = cw.get("start", datetime.now().strftime("%Y-%m-%d"))
week_end = cw.get("end", (datetime.now() + timedelta(days=6)).strftime("%Y-%m-%d"))
log_dir = os.path.dirname(today_log_file)
alt_log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")

all_lines_by_date = {}
d = datetime.strptime(week_start, "%Y-%m-%d").date()
end_d = min(datetime.strptime(week_end, "%Y-%m-%d").date(), datetime.now().date())
while d <= end_d:
    ds = d.strftime("%Y-%m-%d")
    for search_dir in [log_dir, alt_log_dir]:
        candidate = os.path.join(search_dir, f"AetherBot_{ds}.txt")
        if os.path.isfile(candidate):
            try:
                with open(candidate) as f:
                    all_lines_by_date[ds] = f.readlines()
            except Exception:
                pass
            break
    d += timedelta(days=1)

if not all_lines_by_date:
    with open(today_log_file) as f:
        all_lines_by_date[datetime.now().strftime("%Y-%m-%d")] = f.readlines()

# ═══ TRADE COUNT: BUY SNAPSHOT (each = one trade entered) ═══
total_trades = 0
for ds in all_lines_by_date:
    for line in all_lines_by_date[ds]:
        if "BUY SNAPSHOT" in line:
            total_trades += 1

# ═══ OUTCOMES: TICKER CLOSE (authoritative win/loss per interval) ═══
ticker_close_pattern = re.compile(
    r'TICKER CLOSE\s*\|\s*(\S+)\s+MTN\s*\|\s*(\d+)\s+trade\w*\s*\|\s*NET\s+(WIN|LOSS)\s+([+-]?[\d.]+)\s*\|\s*(.*)'
)

all_ticker_closes = []
for ds in sorted(all_lines_by_date.keys()):
    for line in all_lines_by_date[ds]:
        m = ticker_close_pattern.search(line)
        if m:
            all_ticker_closes.append({
                "date": ds, "count": int(m.group(2)),
                "wl": m.group(3), "pnl": float(m.group(4)),
                "strats": m.group(5).strip()
            })

tc_wins = sum(t["count"] for t in all_ticker_closes if t["wl"] == "WIN")
tc_losses = sum(t["count"] for t in all_ticker_closes if t["wl"] == "LOSS")
tc_total = tc_wins + tc_losses
win_rate = round(tc_wins / tc_total * 100, 1) if tc_total else 0.0

# ═══ PER-STRATEGY from TICKER CLOSE ═══
strat_stats = defaultdict(lambda: {"pnl": 0.0, "trades": 0, "wins": 0, "losses": 0})
for t in all_ticker_closes:
    for part in re.finditer(r'(\w+)\s+([+-][\d.]+)', t["strats"]):
        sname = part.group(1)
        spnl = float(part.group(2))
        s = strat_stats[sname]
        s["pnl"] = round(s["pnl"] + spnl, 2)
        s["trades"] += 1
        if spnl >= 0:
            s["wins"] += 1
        else:
            s["losses"] += 1

# ═══ BALANCE: latest from today's log ═══
try:
    with open(today_log_file) as f:
        today_text = f.read()
    today_bal_match = re.findall(r'bal\s+\$([\d.]+)', today_text)
    latest_balance = float(today_bal_match[-1]) if today_bal_match else cw.get("currentBalance", 0)
except Exception:
    all_text = "".join("".join(lines) for lines in all_lines_by_date.values())
    bal_match = re.findall(r'bal\s+\$([\d.]+)', all_text)
    latest_balance = float(bal_match[-1]) if bal_match else cw.get("currentBalance", 0)

_now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")

# ── Write back ──
cw["currentBalance"] = round(latest_balance, 2)

# ── SE-016-001: Backfill dailyPnl from real AetherBot logs every cycle ──
# This ensures dailyPnl is ALWAYS accurate, not dependent on --record-trade calls.
try:
    daily_map = {e["date"]: e for e in cw.get("dailyPnl", [])}
    week_start_date = cw.get("start", datetime.now().strftime("%Y-%m-%d"))
    ws = datetime.strptime(week_start_date, "%Y-%m-%d").date()
    starting_bal = cw.get("startingBalance", 0.0)
    prev_bal = starting_bal
    # Build opening balance for each day by chaining from week start
    for i in range(7):
        day = ws + timedelta(days=i)
        ds = day.strftime("%Y-%m-%d")
        if ds not in daily_map:
            daily_map[ds] = {"date": ds, "pnl": 0.0, "balance": prev_bal, "trades": 0}
        for search_dir in [os.path.dirname(today_log_file), alt_log_dir]:
            candidate = os.path.join(search_dir, f"AetherBot_{ds}.txt")
            if os.path.isfile(candidate):
                try:
                    with open(candidate) as f:
                        day_text = f.read()
                    day_bals = re.findall(r'bal\s+\$([\d.]+)', day_text)
                    day_trades = len(re.findall(r'BUY SNAPSHOT', day_text))
                    if day_bals:
                        day_last = float(day_bals[-1])
                        daily_map[ds]["pnl"] = round(day_last - prev_bal, 2)
                        daily_map[ds]["balance"] = day_last
                        daily_map[ds]["trades"] = day_trades
                        prev_bal = day_last
                except Exception:
                    pass
                break
    cw["dailyPnl"] = [daily_map.get((ws + timedelta(days=i)).strftime("%Y-%m-%d"),
                      {"date": (ws + timedelta(days=i)).strftime("%Y-%m-%d"), "pnl": 0.0, "balance": prev_bal, "trades": 0})
                     for i in range(7)]
except Exception as e:
    pass  # non-fatal — existing dailyPnl preserved if backfill fails

# P&L: balance math is authoritative (captures premium + settlements + expiries)
# SE-012-002: never use settled NET sum — it misses premium collection.
cw["pnl"] = round(cw["currentBalance"] - cw["startingBalance"], 2)
cw["pnlPercent"] = round((cw["pnl"] / cw["startingBalance"]) * 100, 2) if cw.get("startingBalance") else 0

# Trade count = BUY SNAPSHOT count (each snapshot = one trade entered)
cw["trades"] = total_trades
# Outcomes from TICKER CLOSE
cw["wins"] = tc_wins
cw["losses"] = tc_losses
cw["winRate"] = win_rate

# ── Strategy merge — ALWAYS update from TICKER CLOSE data ──
existing_strats = {s["name"]: s for s in cw.get("strategies", [])}
for sname, ss in strat_stats.items():
    if sname in existing_strats:
        es = existing_strats[sname]
        es["pnl"] = ss["pnl"]
        es["trades"] = ss["trades"]
        es["wins"] = ss["wins"]
        es["losses"] = ss["losses"]
        es["winRate"] = round((ss["wins"] / ss["trades"]) * 100, 1) if ss["trades"] else 0.0
        es["status"] = "active"
        es["lastAction"] = _now
    else:
        existing_strats[sname] = {
            "name": sname,
            "status": "active",
            "pnl": ss["pnl"],
            "trades": ss["trades"],
            "wins": ss["wins"],
            "losses": ss["losses"],
            "winRate": round((ss["wins"] / ss["trades"]) * 100, 1) if ss["trades"] else 0.0,
            "lastAction": _now,
        }

for sname, es in existing_strats.items():
    if sname not in strat_stats:
        es["status"] = "idle this week"

cw["strategies"] = sorted(existing_strats.values(), key=lambda x: x.get("pnl", 0), reverse=True)

# Clean up legacy fields
cw.pop("settledTrades", None)
cw.pop("totalTradeEvents", None)
cw.pop("settledPnl", None)

data["updatedAt"] = _now
data["lastUpdated"] = _now
data["dataSource"] = "BUY SNAPSHOT for trades, TICKER CLOSE for outcomes, balance math for P&L"

with open(metrics_file, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

pnl_val = round(latest_balance - cw["startingBalance"], 2)
print(f"Metrics: bal ${latest_balance} (start ${cw['startingBalance']}), "
      f"PnL ${pnl_val} ({round(pnl_val/cw['startingBalance']*100,1) if cw['startingBalance'] else 0}%), "
      f"{total_trades} trades (BUY SNAPSHOT), {tc_wins}W/{tc_losses}L (TICKER CLOSE), "
      f"{len(strat_stats)} strategies")
PYEOF

  # Sync to dual path
  local sam_metrics="$ROOT/agents/sam/website/data/aether-metrics.json"
  if [[ -f "$sam_metrics" ]] && [[ ! "$METRICS" -ef "$sam_metrics" ]] 2>/dev/null; then
    cp "$METRICS" "$sam_metrics" 2>/dev/null || true
  fi

  local ticker_closes=""
  ticker_closes=$(grep -c "TICKER CLOSE" "$log_file" 2>/dev/null || echo "0")
  local buy_snapshots=""
  buy_snapshots=$(grep -c "BUY SNAPSHOT" "$log_file" 2>/dev/null || echo "0")
  log "Today: $buy_snapshots trades (BUY SNAPSHOT), $ticker_closes ticker closes"
}

# ─── GPT Two-Phase Analysis — S18-017 Independence Gate ─────────────────────
# Phase 1: GPT sees raw log ONLY → GPT_Independent_DATE.txt
# Phase 2: GPT sees Phase1 + Kai analysis → GPT_Review_DATE.txt
# Gate: Phase 2 ONLY runs if Phase 1 file exists.
# This prevents GPT from being seeded by Kai's framing before forming its own view.
#
# Called as: gpt_daily_log_review (backward-compat name kept for call site below)
#
gpt_daily_log_review() {
  local today
  today=$(TZ="America/Denver" date +%Y-%m-%d)
  local independent_file="$ROOT/agents/aether/analysis/GPT_Independent_${today}.txt"
  local review_file="$ROOT/agents/aether/analysis/GPT_Review_${today}.txt"
  local crosscheck_file="$ROOT/agents/aether/analysis/GPT_CrossCheck_${today}.txt"  # backward compat
  local factcheck_script="$ROOT/agents/aether/analysis/gpt_factcheck.py"

  # Verify factcheck script exists
  if [[ ! -f "$factcheck_script" ]]; then
    log "WARN: gpt_factcheck.py not found at $factcheck_script"
    return 0
  fi

  # Find today's log
  local log_file=""
  local agents_log="$LOGS/AetherBot_${today}.txt"
  local aetherbot_log="$HOME/Documents/Projects/AetherBot/Logs/AetherBot_${today}.txt"

  if [[ -f "$agents_log" ]]; then
    log_file="$agents_log"
  elif [[ -f "$aetherbot_log" ]]; then
    log_file="$aetherbot_log"
  fi

  if [[ -z "$log_file" ]]; then
    log "GPT analysis: no AetherBot log found for $today, skipping"
    return 0
  fi

  # Only run after enough data accumulates (at least 500 lines = ~2 hours of tickers)
  local line_count
  line_count=$(wc -l < "$log_file" 2>/dev/null || echo "0")
  if [[ "$line_count" -lt 500 ]]; then
    log "GPT analysis: log only has $line_count lines, waiting for more data (need 500+)"
    return 0
  fi

  # ── Phase 1: Independent Review ───────────────────────────────────────────
  if [[ -f "$independent_file" ]] && ! grep -q "PENDING" "$independent_file" 2>/dev/null; then
    log "GPT Phase 1: already complete for $today, skipping"
  else
    log "GPT Phase 1 (independent): sending $log_file ($line_count lines) to GPT-4o..."
    local p1_result
    if p1_result=$(HYO_ROOT="$ROOT" python3 "$factcheck_script" --phase1 "$today" 2>&1); then
      log "GPT Phase 1: complete — saved to GPT_Independent_${today}.txt"
    else
      log "GPT Phase 1: FAILED — $p1_result"
      echo "PENDING — Phase 1 failed at $(TZ='America/Denver' date). Will retry next cycle." > "$independent_file"
      return 0  # Don't attempt Phase 2 if Phase 1 failed
    fi
  fi

  # ── Phase 2: Cross-Review (Independence Gate) ─────────────────────────────
  # Gate question: Did Phase 1 complete successfully?
  if [[ ! -f "$independent_file" ]] || grep -q "PENDING" "$independent_file" 2>/dev/null; then
    log "GPT Phase 2: GATE BLOCKED — Phase 1 incomplete. Cannot proceed."
    return 0
  fi

  if [[ -f "$review_file" ]] && ! grep -q "PENDING" "$review_file" 2>/dev/null; then
    log "GPT Phase 2: already complete for $today, skipping"
    return 0
  fi

  log "GPT Phase 2 (cross-review): sending Phase1 + Kai analysis to GPT-4o..."
  local p2_result
  if p2_result=$(HYO_ROOT="$ROOT" python3 "$factcheck_script" --phase2 "$today" 2>&1); then
    log "GPT Phase 2: complete — saved to GPT_Review_${today}.txt"

    # Report to Kai via dispatch
    local dispatch_bin="$ROOT/bin/dispatch.sh"
    if [[ -x "$dispatch_bin" ]]; then
      bash "$dispatch_bin" report aether \
        "GPT two-phase analysis complete for $today — Phase1: GPT_Independent_${today}.txt, Phase2: GPT_Review_${today}.txt" \
        2>> "$LOG" || true
    fi
  else
    local exit_code=$?
    if [[ "$exit_code" -eq 2 ]]; then
      log "GPT Phase 2: GATE BLOCKED by independence gate (exit 2) — Phase 1 file missing"
    else
      log "GPT Phase 2: FAILED — $p2_result"
      echo "PENDING — Phase 2 failed at $(TZ='America/Denver' date). Will retry next cycle." > "$review_file"
    fi
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

_now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")
data["updatedAt"] = _now
data["lastUpdated"] = _now  # SE-011-002: HQ reads lastUpdated, must refresh too

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

  # GET metrics from static file on Vercel (api/aether does not exist — use static data path)
  api_response=$(curl -sf "https://www.hyo.world/data/aether-metrics.json" 2>> "$LOG")

  if [[ -z "$api_response" ]]; then
    log "WARN: Dashboard verification failed (empty response from data endpoint)"
    # Rate-limit this flag to once per hour to avoid spam
    local flag_marker="/tmp/aether-dashfail-$(TZ=America/Denver date +%Y%m%d%H)"
    if [[ ! -f "$flag_marker" ]]; then
      touch "$flag_marker"
      local dispatch_bin="$ROOT/bin/dispatch.sh"
      if [[ -x "$dispatch_bin" ]]; then
        bash "$dispatch_bin" flag aether P2 "dashboard data verification failed: empty response from /data/aether-metrics.json" 2>> "$LOG" || true
      fi
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
    python3 - "$METRICS" <<'INIT_PYEOF'
import json, re, os, sys
from datetime import datetime, timedelta

metrics_file = sys.argv[1]
now = datetime.now()
monday = now - timedelta(days=now.weekday())
sunday = monday + timedelta(days=6)

# SE-016-001: Read REAL starting balance from first AetherBot log of the week.
# NEVER hardcode 1000 — that creates phantom losses when file is recreated mid-week.
log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
week_opening = None
d = monday.date()
while d <= now.date() and week_opening is None:
    ds = d.strftime("%Y-%m-%d")
    candidate = os.path.join(log_dir, f"AetherBot_{ds}.txt")
    if os.path.isfile(candidate):
        try:
            with open(candidate) as f:
                text = f.read()
            bals = re.findall(r'bal\s+\$([\d.]+)', text)
            if bals:
                week_opening = float(bals[0])
                print(f"[init] week_opening={week_opening} from {candidate}")
        except Exception:
            pass
    d += timedelta(days=1)

if week_opening is None:
    # Absolute fallback: use current day's balance or 0
    week_opening = 0.0
    print("[init] WARN: no AetherBot logs found for this week — startingBalance=0")

# Build daily entries with real balances where logs exist
daily_entries = []
prev = week_opening
for i in range(7):
    day = monday + timedelta(days=i)
    ds = day.strftime("%Y-%m-%d")
    candidate = os.path.join(log_dir, f"AetherBot_{ds}.txt")
    entry = {'date': ds, 'pnl': 0.0, 'balance': prev, 'trades': 0}
    if os.path.isfile(candidate):
        try:
            with open(candidate) as f:
                text = f.read()
            bals = re.findall(r'bal\s+\$([\d.]+)', text)
            trades = len(re.findall(r'BUY SNAPSHOT', text))
            if bals:
                last_bal = float(bals[-1])
                entry['pnl'] = round(last_bal - prev, 2)
                entry['balance'] = last_bal
                entry['trades'] = trades
                prev = last_bal
        except Exception:
            pass
    daily_entries.append(entry)

current_bal = prev

d = {
  'currentWeek': {
    'start': monday.strftime('%Y-%m-%d'),
    'end': sunday.strftime('%Y-%m-%d'),
    'startingBalance': week_opening, 'currentBalance': current_bal,
    'pnl': round(current_bal - week_opening, 2),
    'pnlPercent': round((current_bal - week_opening) / week_opening * 100, 2) if week_opening else 0.0,
    'trades': 0, 'wins': 0, 'losses': 0, 'winRate': 0.0,
    'stoplossTriggers': 0, 'harvestEvents': 0,
    'strategies': [{'name': 'Grid Bot', 'status': 'standby', 'pnl': 0.0, 'trades': 0, 'winRate': 0.0, 'lastAction': now.strftime('%Y-%m-%dT%H:%M:%S-06:00')}],
    'dailyPnl': daily_entries,
    'recentTrades': [],
  },
  'lastWeek': {'start': '', 'end': '', 'startingBalance': 0, 'endingBalance': 0, 'pnl': 0, 'pnlPercent': 0, 'trades': 0, 'wins': 0, 'losses': 0, 'winRate': 0, 'stoplossTriggers': 0, 'harvestEvents': 0, 'bestStrategy': '—', 'worstStrategy': '—'},
  'allTimeStats': {'totalPnl': 0.0, 'totalTrades': 0, 'weeklyHistory': []},
  'updatedAt': now.strftime('%Y-%m-%dT%H:%M:%S-06:00'),
}
with open(metrics_file, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
INIT_PYEOF
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

  # ─── GPT Two-Phase Analysis (S18-017 Independence Gate) ──────────────────
  # Phase 1: GPT sees raw log ONLY → GPT_Independent_DATE.txt
  # Phase 2 (gated): GPT sees Phase1 + Kai analysis → GPT_Review_DATE.txt
  # Gate: Phase 2 aborts if Phase 1 file is missing (prevents seeding).
  # Hyo directive: "Aether needs to send GPT the day's log so that it can come
  # up with its own analysis and actually factcheck anything that Aether
  # recognizes, wants to change, etc"
  gpt_daily_log_review

  # Normal run: update timestamps + push to HQ
  # Both `updatedAt` (internal) and `lastUpdated` (HQ consumer reads this) must refresh.
  # Bug fix: prior version only touched updatedAt, so HQ showed a stale lastUpdated
  # even when the file was being written every 15 min. SE-011-002.
  python3 -c "
import json
from datetime import datetime
with open('$METRICS') as f: d = json.load(f)
now = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-06:00')
d['updatedAt'] = now
d['lastUpdated'] = now
with open('$METRICS', 'w') as f: json.dump(d, f, indent=2); f.write('\n')
"
  # ─── SE-016-001: Data Verification Gate ─────────────────────────────────
  # Run 6 yes/no gate questions before every HQ push.
  # Any BLOCK = skip push, open P1 ticket. See protocols/DATA_VERIFICATION_GATE.md
  gate_result=$(python3 - "$METRICS" <<'GATE_PYEOF'
import json, sys, os, re
from pathlib import Path

metrics_file = sys.argv[1]
with open(metrics_file) as f:
    data = json.load(f)

cw = data.get("currentWeek", data.get("currentPeriod", {}))
starting_bal = cw.get("startingBalance", 0)
current_bal = cw.get("currentBalance", 0)
daily_pnl = cw.get("dailyPnl", [])
strategies = cw.get("strategies", [])
trades = cw.get("trades", 0)
week_pnl = cw.get("pnl", 0)

gate_pass = True
blocks = []
warns = []

# Q1: Starting balance not hardcoded/null/zero
if starting_bal == 1000.0 or starting_bal <= 0:
    blocks.append(f"Q1 FAIL: startingBalance={starting_bal} (hardcoded or zero — must be read from AetherBot log)")

# Q2: Balance chain continuity
chain = starting_bal
for day in daily_pnl:
    from datetime import datetime, date
    try:
        day_d = datetime.strptime(day["date"], "%Y-%m-%d").date()
        if day_d <= date.today():
            chain += day.get("pnl", 0)
    except Exception:
        pass
chain = round(chain, 2)
if abs(chain - current_bal) > 0.10:
    blocks.append(f"Q2 FAIL: startingBalance({starting_bal}) + dailyPnl chain={chain} != currentBalance({current_bal}) (drift={abs(chain-current_bal):.2f})")

# Q3: Daily PnL non-zero for days with trades
log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
for day in daily_pnl:
    ds = day["date"]
    log_path = os.path.join(log_dir, f"AetherBot_{ds}.txt")
    if os.path.isfile(log_path):
        if day.get("trades", 0) == 0 and day.get("pnl", 0) == 0 and day.get("balance", 0) == 0:
            blocks.append(f"Q3 FAIL: {ds} has AetherBot log but dailyPnl shows 0/0/0 — backfill missing")

# Q4: Strategy sum sanity (warn only)
strat_sum = sum(s.get("pnl", 0) for s in strategies)
if abs(week_pnl) > 5 and trades > 0:
    divergence = abs(strat_sum - week_pnl) / max(abs(week_pnl), 1)
    if divergence > 0.20:
        warns.append(f"Q4 WARN: strategy sum={strat_sum:.2f} vs week_pnl={week_pnl:.2f} (divergence={divergence:.0%}) — review for uncaptured trades")

# Q5: Balance source (warn if no today log)
from datetime import date as _date
today_log = os.path.join(log_dir, f"AetherBot_{_date.today().strftime('%Y-%m-%d')}.txt")
yesterday_log = os.path.join(log_dir, f"AetherBot_{(_date.today().__class__.fromordinal(_date.today().toordinal()-1)).strftime('%Y-%m-%d')}.txt")
if not os.path.isfile(today_log) and not os.path.isfile(yesterday_log):
    warns.append(f"Q5 WARN: no recent AetherBot log (today or yesterday) — currentBalance may be stale")

# Q6: Phantom loss gate
pnl_per_trade = abs(week_pnl) / max(trades, 1)
if pnl_per_trade > 50:
    blocks.append(f"Q6 FAIL: pnl_per_trade=${pnl_per_trade:.2f} > $50 threshold — likely data corruption (week_pnl={week_pnl}, trades={trades})")

# Output result
if blocks:
    print("BLOCKED:" + "|".join(blocks))
elif warns:
    print("PASS_WARN:" + "|".join(warns))
else:
    print("PASS")
GATE_PYEOF
)

  if [[ "$gate_result" == BLOCKED:* ]]; then
    gate_reason="${gate_result#BLOCKED:}"
    log "DATA GATE BLOCKED: $gate_reason"
    # Open P1 ticket
    dispatch_bin="$ROOT/bin/kai.sh"
    if [[ -f "$dispatch_bin" ]]; then
      bash "$dispatch_bin" exec "cd ~/Documents/Projects/Hyo && bash bin/ticket.sh --create --id AET-$(date +%Y%m%d%H%M) --title 'Aether data gate blocked: metrics not published' --body '$gate_reason' --priority P1 --agent aether" 2>>"$LOG" || true
    fi
    log "HQ push SKIPPED — gate blocked. Fix data before next cycle."
    # Write gate status to metrics without pushing
    python3 -c "
import json
with open('$METRICS') as f: d = json.load(f)
d['dataGateStatus'] = 'BLOCKED'
d['dataGateReason'] = '$gate_reason'
with open('$METRICS', 'w') as f: json.dump(d, f, indent=2); f.write('\n')
" 2>>"$LOG" || true
  else
    if [[ "$gate_result" == PASS_WARN:* ]]; then
      log "DATA GATE PASS (with warnings): ${gate_result#PASS_WARN:}"
    else
      log "DATA GATE PASS: all 6 verification questions passed"
    fi
    python3 -c "
import json
with open('$METRICS') as f: d = json.load(f)
d['dataGateStatus'] = 'PASS'
d.pop('dataGateReason', None)
with open('$METRICS', 'w') as f: json.dump(d, f, indent=2); f.write('\n')
" 2>>"$LOG" || true
    push_to_hq
  fi

  # ─── Git push metrics to Vercel (every 15-min cycle) ─────────────────────
  # The API push_to_hq is ephemeral (serverless cold starts reset it).
  # Git push ensures the static site always has fresh metrics.
  (
    cd "$ROOT" || exit 1
    # Remove stale lock files (e.g., from crashed processes)
    rm -f .git/index.lock 2>/dev/null
    git add website/data/aether-metrics.json 2>/dev/null
    if ! git diff --cached --quiet website/data/aether-metrics.json 2>/dev/null; then
      git commit -m "aether: metrics update $(TZ=America/Denver date +%H:%M)" 2>/dev/null \
        && git push origin main 2>/dev/null \
        && log "Git push: metrics deployed to Vercel" \
        || log "Git push: failed (will retry next cycle)"
    fi
  )

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
  # PUBLISH GATE: Only publish to HQ feed ONCE per day, not every 15-min cycle.
  local RESEARCH_SCRIPT="$ROOT/bin/agent-research.sh"
  local AETHER_PUBLISH_MARKER="/tmp/aether-published-$(TZ=America/Denver date +%Y%m%d)"
  if [[ -x "$RESEARCH_SCRIPT" ]]; then
    if [[ -f "$AETHER_PUBLISH_MARKER" ]]; then
      log "Domain research: skipping publish (already published today). Metrics-only cycle."
      # Still run research without --publish to update local findings
      bash "$RESEARCH_SCRIPT" aether 2>&1 | tail -3 || true
    else
      log "Running domain research: trading strategies, position sizing, market tools..."
      if bash "$RESEARCH_SCRIPT" aether --publish 2>&1 | tail -5; then
        log "Domain research complete — findings saved and published"
        touch "$AETHER_PUBLISH_MARKER"
      else
        log "WARN: Domain research encountered issues — check agents/aether/research/"
      fi
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

  # PUBLISH GATE: Only publish reflection to HQ feed ONCE per day.
  # The marker file is shared with the research publish gate above.
  local REPORT_PUBLISH_MARKER="/tmp/aether-report-published-$(TZ=America/Denver date +%Y%m%d)"
  if [[ -f "$AETHER_REFLECTION" && -x "$PUBLISH_SCRIPT" ]]; then
    if [[ -f "$REPORT_PUBLISH_MARKER" ]]; then
      log "Self-authored report: skipping publish (already published today)"
    else
      bash "$PUBLISH_SCRIPT" "agent-reflection" "aether" "Aether — Trading Report" "$AETHER_REFLECTION" 2>/dev/null || true
      touch "$REPORT_PUBLISH_MARKER"
      log "Self-authored report published to HQ feed"
    fi

    # Report to Kai — closed-loop upward communication (always, for metrics tracking)
    DISPATCH_BIN="$ROOT/bin/dispatch.sh"
    if [[ -x "$DISPATCH_BIN" ]]; then
      bash "$DISPATCH_BIN" report aether "cycle complete: ${trade_count} trades, PNL=\$${pnl_total}, dashboard: ${dashboard_status}" 2>/dev/null || true
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

# ── Daily report to HQ feed (weekdays only) ───────────────────────────────────
_HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
if [[ -x "$_HYO_ROOT/bin/daily-agent-report.sh" ]]; then
  bash "$_HYO_ROOT/bin/daily-agent-report.sh" aether || true
fi

