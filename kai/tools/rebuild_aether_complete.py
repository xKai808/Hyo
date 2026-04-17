#!/usr/bin/env python3
"""
Complete rebuild of aether-metrics.json from raw AetherBot logs.
Trade = BUY SNAPSHOT (each entry is one trade).
Outcome = TICKER CLOSE (NET WIN or NET LOSS per trading interval).
P&L = balance math (only authoritative number).
Strategy P&L = from TICKER CLOSE per-strategy breakdown.

No SETTLED-only counting. No shortcuts.
"""

import os, re, json, sys
from collections import defaultdict
from datetime import datetime, timedelta

hyo_root = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
metrics_path = os.path.join(hyo_root, "website/data/aether-metrics.json")
sam_metrics_path = os.path.join(hyo_root, "agents/sam/website/data/aether-metrics.json")

# Read existing metrics for structure
with open(metrics_path) as f:
    existing = json.load(f)

cw = existing.get("currentWeek", {})
week_start = cw.get("start", "2026-04-13")
week_end = cw.get("end", "2026-04-19")
starting_balance = cw.get("startingBalance", 90.25)

print(f"=== COMPLETE AETHER METRICS REBUILD ===")
print(f"Week: {week_start} to {week_end}")
print(f"Starting balance: ${starting_balance}")
print()

# ─── Read ALL raw logs ───
all_lines_by_date = {}
d = datetime.strptime(week_start, "%Y-%m-%d").date()
today = datetime.now().date()
end_d = min(datetime.strptime(week_end, "%Y-%m-%d").date(), today)

while d <= end_d:
    ds = d.strftime("%Y-%m-%d")
    path = os.path.join(log_dir, f"AetherBot_{ds}.txt")
    if os.path.isfile(path):
        with open(path) as f:
            lines = f.readlines()
        all_lines_by_date[ds] = lines
        print(f"  {ds}: {len(lines):,} lines")
    else:
        print(f"  {ds}: MISSING")
    d += timedelta(days=1)

# ═══ TRADE COUNT: BUY SNAPSHOT ═══
# Each BUY SNAPSHOT = one trade entered
buy_snapshots_by_date = {}
buy_snapshots_by_strat = defaultdict(int)

for ds in sorted(all_lines_by_date.keys()):
    count = 0
    lines = all_lines_by_date[ds]
    for i, line in enumerate(lines):
        if "BUY SNAPSHOT" in line:
            count += 1
            # Get strategy from "Reason:" line (usually 2 lines after)
            for j in range(1, 5):
                if i + j < len(lines) and "Reason:" in lines[i + j]:
                    strat = lines[i + j].strip().split("Reason:")[1].strip()
                    buy_snapshots_by_strat[strat] += 1
                    break
    buy_snapshots_by_date[ds] = count

total_trades = sum(buy_snapshots_by_date.values())
print(f"\n=== TRADES (BUY SNAPSHOT) ===")
print(f"Total: {total_trades}")
for ds in sorted(buy_snapshots_by_date.keys()):
    print(f"  {ds}: {buy_snapshots_by_date[ds]}")

# ═══ OUTCOMES: TICKER CLOSE ═══
# Each TICKER CLOSE = one completed trade with NET WIN/LOSS
ticker_close_pattern = re.compile(
    r'TICKER CLOSE\s*\|\s*(\S+)\s+MTN\s*\|\s*(\d+)\s+trade\w*\s*\|\s*NET\s+(WIN|LOSS)\s+([+-]?[\d.]+)\s*\|\s*(.*)'
)

all_ticker_closes = []
for ds in sorted(all_lines_by_date.keys()):
    for line in all_lines_by_date[ds]:
        m = ticker_close_pattern.search(line)
        if m:
            time = m.group(1)
            count = int(m.group(2))
            wl = m.group(3)
            pnl = float(m.group(4))
            strat_info = m.group(5).strip()
            all_ticker_closes.append({
                "date": ds, "time": time, "count": count,
                "wl": wl, "pnl": pnl, "strats": strat_info
            })

tc_total = sum(t["count"] for t in all_ticker_closes)
tc_wins = sum(t["count"] for t in all_ticker_closes if t["wl"] == "WIN")
tc_losses = sum(t["count"] for t in all_ticker_closes if t["wl"] == "LOSS")
tc_wr = round(tc_wins / tc_total * 100, 1) if tc_total else 0

print(f"\n=== OUTCOMES (TICKER CLOSE) ===")
print(f"Total: {tc_total} (from {len(all_ticker_closes)} TICKER CLOSE lines)")
print(f"Wins: {tc_wins}, Losses: {tc_losses}")
print(f"Win Rate: {tc_wr}%")

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

print(f"\n=== STRATEGY PERFORMANCE (from TICKER CLOSE) ===")
print(f"  {'Strategy':<20s} {'PnL':>10s} {'Trades':>7s} {'W':>4s} {'L':>4s} {'WR':>7s}")
print(f"  {'-'*20} {'-'*10} {'-'*7} {'-'*4} {'-'*4} {'-'*7}")
strategies_list = []
_now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")
for name in sorted(strat_stats.keys(), key=lambda n: strat_stats[n]["pnl"], reverse=True):
    s = strat_stats[name]
    wr = round(s["wins"] / s["trades"] * 100, 1) if s["trades"] else 0.0
    print(f"  {name:<20s} ${s['pnl']:>8.2f} {s['trades']:>7d} {s['wins']:>4d} {s['losses']:>4d} {wr:>6.1f}%")
    strategies_list.append({
        "name": name,
        "status": "active" if any(tc["date"] == datetime.now().strftime("%Y-%m-%d") for tc in all_ticker_closes if name in tc["strats"]) else "idle today",
        "pnl": s["pnl"],
        "trades": s["trades"],
        "wins": s["wins"],
        "losses": s["losses"],
        "winRate": wr,
        "lastAction": _now,
    })

strategies_list.sort(key=lambda x: x["pnl"], reverse=True)

# ═══ BALANCE TRACKING ═══
bal_pattern = re.compile(r'bal\s+\$([\d.]+)')
bals_by_date = defaultdict(list)
for ds in sorted(all_lines_by_date.keys()):
    for line in all_lines_by_date[ds]:
        for m in bal_pattern.finditer(line):
            bals_by_date[ds].append(float(m.group(1)))

all_bals = []
for ds in sorted(bals_by_date.keys()):
    for b in bals_by_date[ds]:
        all_bals.append(b)

latest_balance = all_bals[-1] if all_bals else starting_balance
balance_pnl = round(latest_balance - starting_balance, 2)
balance_pnl_pct = round(balance_pnl / starting_balance * 100, 2) if starting_balance else 0

print(f"\n=== BALANCE P&L ===")
print(f"${starting_balance} → ${latest_balance}")
print(f"P&L: ${balance_pnl} ({balance_pnl_pct}%)")

# ═══ PER-DAY BREAKDOWN ═══
print(f"\n=== DAILY BREAKDOWN ===")
daily_pnl = []
for ds in sorted(all_lines_by_date.keys()):
    day_tc = [t for t in all_ticker_closes if t["date"] == ds]
    day_wins = sum(t["count"] for t in day_tc if t["wl"] == "WIN")
    day_losses = sum(t["count"] for t in day_tc if t["wl"] == "LOSS")
    day_trade_count = buy_snapshots_by_date.get(ds, 0)
    day_wr = round(day_wins / (day_wins + day_losses) * 100, 1) if (day_wins + day_losses) else 0

    day_bals = bals_by_date.get(ds, [])
    day_start = day_bals[0] if day_bals else 0
    day_end = day_bals[-1] if day_bals else 0
    day_pnl_val = round(day_end - day_start, 2)
    day_pnl_pct = round(day_pnl_val / day_start * 100, 1) if day_start else 0

    # Per-strategy for this day
    day_strat_stats = defaultdict(lambda: {"trades": 0, "wins": 0, "losses": 0, "pnl": 0.0})
    for t in day_tc:
        for part in re.finditer(r'(\w+)\s+([+-][\d.]+)', t["strats"]):
            sname = part.group(1)
            spnl = float(part.group(2))
            ds2 = day_strat_stats[sname]
            ds2["trades"] += 1
            ds2["pnl"] = round(ds2["pnl"] + spnl, 2)
            if spnl >= 0:
                ds2["wins"] += 1
            else:
                ds2["losses"] += 1

    day_name = datetime.strptime(ds, "%Y-%m-%d").strftime("%A")
    print(f"  {ds} ({day_name}): {day_trade_count} trades, {day_wins}W/{day_losses}L ({day_wr}%), bal ${day_start}→${day_end}, P&L ${day_pnl_val}")

    daily_entry = {
        "date": ds,
        "day": day_name,
        "trades": day_trade_count,
        "balanceStart": round(day_start, 2),
        "balanceEnd": round(day_end, 2),
        "pnl": day_pnl_val,
        "pnlPct": day_pnl_pct,
        "wins": day_wins,
        "losses": day_losses,
        "winRate": day_wr,
        "strategies": {},
        "source": "raw AetherBot log (BUY SNAPSHOT + TICKER CLOSE)"
    }
    for sname, ss in sorted(day_strat_stats.items()):
        daily_entry["strategies"][sname] = {
            "trades": ss["trades"],
            "wins": ss["wins"],
            "losses": ss["losses"],
            "pnl": ss["pnl"]
        }
    daily_pnl.append(daily_entry)

# ═══ BUILD JSON ═══
rebuilt = {
    "agent": existing.get("agent", "aether.hyo"),
    "description": existing.get("description", "Live Kalshi BTC 15-minute binary options trading bot."),
    "status": "active",
    "lastUpdated": _now,
    "updatedAt": _now,
    "dataSource": "RAW AetherBot logs — BUY SNAPSHOT for trades, TICKER CLOSE for outcomes, bal for P&L",
    "currentWeek": {
        "start": week_start,
        "end": week_end,
        "startingBalance": starting_balance,
        "currentBalance": round(latest_balance, 2),
        "pnl": balance_pnl,
        "pnlPercent": balance_pnl_pct,
        "trades": total_trades,
        "wins": tc_wins,
        "losses": tc_losses,
        "winRate": tc_wr,
        "strategies": strategies_list,
        "dailyPnl": daily_pnl,
    },
    "btcMarketContext": existing.get("btcMarketContext", {}),
    "allTimeStats": {
        "totalPnl": balance_pnl,
        "totalTrades": total_trades,
        "totalWins": tc_wins,
        "totalLosses": tc_losses,
        "weeklyHistory": [{
            "start": week_start,
            "end": week_end,
            "pnl": balance_pnl,
            "trades": total_trades,
            "winRate": tc_wr,
        }],
        "note": "Tracking since 2026-04-13."
    },
    "openIssues": [],
    "operationalNotes": existing.get("operationalNotes", {}),
}

# Flag struggling strategies
for s in strategies_list:
    if s["pnl"] < -5 and s["trades"] >= 3:
        rebuilt["openIssues"].append({
            "id": len(rebuilt["openIssues"]) + 1,
            "title": f"{s['name']} Net Negative (${s['pnl']:.2f} weekly)",
            "priority": "P1" if s["pnl"] < -10 else "P2",
            "status": "ACTIVE",
            "detail": f"{s['trades']} trades, {s['wins']}W/{s['losses']}L ({s['winRate']}% WR)."
        })

# Preserve non-strategy issues
for issue in existing.get("openIssues", []):
    if "Net Negative" not in issue.get("title", ""):
        rebuilt["openIssues"].append(issue)

# ─── WRITE ───
for path in [metrics_path, sam_metrics_path]:
    with open(path, "w") as f:
        json.dump(rebuilt, f, indent=2)
        f.write("\n")
    print(f"\nWritten: {path}")

# ─── VERIFY ───
print(f"\n{'='*60}")
print(f"=== FINAL VERIFICATION ===")
print(f"{'='*60}")
with open(metrics_path) as f:
    v = json.load(f)
vcw = v["currentWeek"]
print(f"  Trades:     {vcw['trades']} (from {total_trades} BUY SNAPSHOTS)")
print(f"  Wins:       {vcw['wins']}")
print(f"  Losses:     {vcw['losses']}")
print(f"  Win Rate:   {vcw['winRate']}%")
print(f"  Balance:    ${vcw['currentBalance']}")
print(f"  P&L:        ${vcw['pnl']} ({vcw['pnlPercent']}%)")
print(f"  Strategies: {len(vcw['strategies'])}")
for s in vcw["strategies"]:
    print(f"    {s['name']:<20s}: ${s['pnl']:>8.2f}, {s['trades']}T ({s['wins']}W/{s['losses']}L), {s['winRate']}% WR")
print(f"  Daily entries: {len(vcw['dailyPnl'])}")
for day in vcw["dailyPnl"]:
    print(f"    {day['date']}: {day['trades']}T, {day['wins']}W/{day['losses']}L ({day['winRate']}%), P&L ${day['pnl']}")
print(f"{'='*60}")
