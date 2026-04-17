#!/usr/bin/env python3
"""
Complete rebuild of aether-metrics.json from raw AetherBot logs.
No shortcuts. Every number provable from raw data.

This script:
1. Reads ALL raw log files for the current week
2. Parses EVERY SETTLED trade line
3. Parses EVERY balance mention
4. Computes per-calendar-day breakdowns
5. Computes per-strategy stats
6. Rebuilds the complete metrics JSON
7. Writes to both paths (website/data/ and agents/sam/website/data/)
8. Outputs a verification report

Run: python3 kai/tools/rebuild_aether_complete.py
"""

import os, re, json, sys
from collections import defaultdict
from datetime import datetime, timedelta

hyo_root = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
metrics_path = os.path.join(hyo_root, "website/data/aether-metrics.json")
sam_metrics_path = os.path.join(hyo_root, "agents/sam/website/data/aether-metrics.json")

# Read existing metrics for structure we want to preserve
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
all_lines_by_date = defaultdict(list)
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

# ─── Parse SETTLED trades ───
settled_pattern = re.compile(
    r'(WIN|LOSS)\s+SETTLED\s+\|\s+(\S+)\s+\|.*?NET\s+([+-]?\$[\d.]+)\s*\|\s*bal\s+\$([\d.]+)'
)

all_settled = []  # (date, wl, strat, net, bal)
for ds in sorted(all_lines_by_date.keys()):
    for line in all_lines_by_date[ds]:
        m = settled_pattern.search(line)
        if m:
            wl = m.group(1)
            strat = m.group(2)
            net_str = m.group(3).replace('$', '').replace('+', '')
            net = float(net_str)
            bal = float(m.group(4))
            all_settled.append({
                "date": ds, "wl": wl, "strat": strat,
                "net": net, "bal": bal
            })

print(f"\nTotal SETTLED trades parsed: {len(all_settled)}")

# ─── Parse ALL balance mentions per day ───
bal_pattern = re.compile(r'bal\s+\$([\d.]+)')
bals_by_date = defaultdict(list)
for ds in sorted(all_lines_by_date.keys()):
    for line in all_lines_by_date[ds]:
        for m in bal_pattern.finditer(line):
            bals_by_date[ds].append(float(m.group(1)))

# ─── Count TICKER CLOSE events (each = one 15-min trading interval evaluated) ───
trade_events_by_date = defaultdict(int)
for ds in sorted(all_lines_by_date.keys()):
    for line in all_lines_by_date[ds]:
        if "TICKER CLOSE" in line:
            trade_events_by_date[ds] += 1

# ─── WEEKLY AGGREGATES ───
total_settled = len(all_settled)
total_wins = sum(1 for t in all_settled if t["wl"] == "WIN")
total_losses = sum(1 for t in all_settled if t["wl"] == "LOSS")
win_rate = round(total_wins / total_settled * 100, 1) if total_settled else 0.0

# Balance-based P&L (authoritative)
all_bals_flat = []
for ds in sorted(bals_by_date.keys()):
    for b in bals_by_date[ds]:
        all_bals_flat.append(b)

latest_balance = all_bals_flat[-1] if all_bals_flat else starting_balance
balance_pnl = round(latest_balance - starting_balance, 2)
balance_pnl_pct = round(balance_pnl / starting_balance * 100, 2) if starting_balance else 0

total_trade_events = sum(trade_events_by_date.values())

print(f"\n=== WEEKLY SUMMARY ===")
print(f"Balance: ${starting_balance} → ${latest_balance}")
print(f"P&L: ${balance_pnl} ({balance_pnl_pct}%)")
print(f"Settled: {total_settled} ({total_wins}W/{total_losses}L, {win_rate}% WR)")
print(f"Total trade events: {total_trade_events}")

# ─── PER-STRATEGY (from SETTLED trades only) ───
strat_stats = defaultdict(lambda: {"pnl": 0.0, "trades": 0, "wins": 0, "losses": 0})
for t in all_settled:
    s = strat_stats[t["strat"]]
    s["pnl"] = round(s["pnl"] + t["net"], 2)
    s["trades"] += 1
    if t["wl"] == "WIN":
        s["wins"] += 1
    else:
        s["losses"] += 1

print(f"\n=== STRATEGY PERFORMANCE ===")
strategies_list = []
_now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")
for name in sorted(strat_stats.keys(), key=lambda n: strat_stats[n]["pnl"], reverse=True):
    s = strat_stats[name]
    wr = round(s["wins"] / s["trades"] * 100, 1) if s["trades"] else 0.0
    print(f"  {name:<20s}: PnL=${s['pnl']:>8.2f}, {s['trades']}T ({s['wins']}W/{s['losses']}L), WR={wr}%")
    strategies_list.append({
        "name": name,
        "status": "active",
        "pnl": s["pnl"],
        "trades": s["trades"],
        "wins": s["wins"],
        "losses": s["losses"],
        "winRate": wr,
        "lastAction": _now,
    })

# Sort strategies by PnL descending
strategies_list.sort(key=lambda x: x["pnl"], reverse=True)

# ─── PER-CALENDAR-DAY BREAKDOWN ───
print(f"\n=== DAILY BREAKDOWN (calendar day) ===")
daily_pnl = []
dates_in_week = sorted(all_lines_by_date.keys())

for ds in dates_in_week:
    day_settled = [t for t in all_settled if t["date"] == ds]
    day_wins = sum(1 for t in day_settled if t["wl"] == "WIN")
    day_losses = sum(1 for t in day_settled if t["wl"] == "LOSS")
    day_wr = round(day_wins / len(day_settled) * 100, 1) if day_settled else 0.0

    # Balance tracking for this day
    day_bals = bals_by_date.get(ds, [])
    day_start = day_bals[0] if day_bals else 0
    day_end = day_bals[-1] if day_bals else 0
    day_pnl = round(day_end - day_start, 2) if day_bals else 0
    day_pnl_pct = round(day_pnl / day_start * 100, 1) if day_start else 0

    # Per-strategy for this day
    day_strats = defaultdict(lambda: {"trades": 0, "wins": 0, "losses": 0, "net": 0.0})
    for t in day_settled:
        ds2 = day_strats[t["strat"]]
        ds2["trades"] += 1
        ds2["net"] = round(ds2["net"] + t["net"], 2)
        if t["wl"] == "WIN":
            ds2["wins"] += 1
        else:
            ds2["losses"] += 1

    day_name = datetime.strptime(ds, "%Y-%m-%d").strftime("%A")
    trade_events = trade_events_by_date.get(ds, 0)

    print(f"  {ds} ({day_name}): bal ${day_start}→${day_end}, P&L ${day_pnl} ({day_pnl_pct}%)")
    print(f"    Settled: {len(day_settled)} ({day_wins}W/{day_losses}L, {day_wr}% WR), Events: {trade_events}")

    daily_entry = {
        "date": ds,
        "day": day_name,
        "balanceStart": round(day_start, 2),
        "balanceEnd": round(day_end, 2),
        "pnl": day_pnl,
        "pnlPct": day_pnl_pct,
        "settledTrades": len(day_settled),
        "tradeEvents": trade_events,
        "wins": day_wins,
        "losses": day_losses,
        "winRate": day_wr,
        "strategies": {},
        "source": "raw AetherBot log"
    }
    for sname, ss in sorted(day_strats.items()):
        daily_entry["strategies"][sname] = {
            "trades": ss["trades"],
            "wins": ss["wins"],
            "losses": ss["losses"],
            "net": ss["net"]
        }

    daily_pnl.append(daily_entry)

# ─── REBUILD THE JSON ───
now_ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00")

# Preserve sections we don't rebuild
rebuilt = {
    "agent": existing.get("agent", "aether.hyo"),
    "description": existing.get("description", "Live Kalshi BTC 15-minute binary options trading bot."),
    "status": "active",
    "lastUpdated": now_ts,
    "updatedAt": now_ts,
    "dataSource": "RAW AetherBot logs — ~/Documents/Projects/AetherBot/Logs/AetherBot_YYYY-MM-DD.txt",
    "sessionBoundary": "17:00 MT daily",
    "currentWeek": {
        "start": week_start,
        "end": week_end,
        "startingBalance": starting_balance,
        "currentBalance": round(latest_balance, 2),
        "pnl": balance_pnl,
        "pnlPercent": balance_pnl_pct,
        "totalTradeEvents": total_trade_events,
        "settledTrades": total_settled,
        "wins": total_wins,
        "losses": total_losses,
        "winRate": win_rate,
        "strategies": strategies_list,
        "dailyPnl": daily_pnl,
    },
    "btcMarketContext": existing.get("btcMarketContext", {}),
    "allTimeStats": existing.get("allTimeStats", {}),
    "openIssues": [],  # Will rebuild below
    "operationalNotes": existing.get("operationalNotes", {}),
}

# Rebuild open issues with current data
for s in strategies_list:
    if s["pnl"] < -5 and s["trades"] >= 3:
        rebuilt["openIssues"].append({
            "id": len(rebuilt["openIssues"]) + 1,
            "title": f"{s['name']} Net Negative (${s['pnl']:.2f} weekly)",
            "priority": "P1" if s["pnl"] < -10 else "P2",
            "status": "ACTIVE",
            "detail": f"{s['trades']} settled trades, {s['wins']}W/{s['losses']}L ({s['winRate']}% WR) this week."
        })

# Preserve existing issues that aren't strategy-performance related
for issue in existing.get("openIssues", []):
    title = issue.get("title", "")
    if "Net Negative" not in title:
        rebuilt["openIssues"].append(issue)

# ─── WRITE ───
for path in [metrics_path, sam_metrics_path]:
    with open(path, "w") as f:
        json.dump(rebuilt, f, indent=2)
        f.write("\n")
    print(f"\nWritten: {path}")

# ─── VERIFICATION ───
print(f"\n{'='*60}")
print(f"=== VERIFICATION: READ BACK AND CHECK ===")
print(f"{'='*60}")

with open(metrics_path) as f:
    verify = json.load(f)

vcw = verify["currentWeek"]
checks = [
    ("currentBalance", vcw["currentBalance"], round(latest_balance, 2)),
    ("startingBalance", vcw["startingBalance"], starting_balance),
    ("pnl", vcw["pnl"], balance_pnl),
    ("pnlPercent", vcw["pnlPercent"], balance_pnl_pct),
    ("settledTrades", vcw["settledTrades"], total_settled),
    ("wins", vcw["wins"], total_wins),
    ("losses", vcw["losses"], total_losses),
    ("winRate", vcw["winRate"], win_rate),
]

all_pass = True
for label, actual, expected in checks:
    match = abs(actual - expected) < 0.01 if isinstance(actual, float) else actual == expected
    status = "PASS" if match else "FAIL"
    if not match:
        all_pass = False
    print(f"  {label:<20s}: {actual} == {expected} [{status}]")

# Check strategies
print(f"\n  Strategies ({len(vcw['strategies'])}):")
for s in vcw["strategies"]:
    raw = strat_stats.get(s["name"])
    if raw:
        raw_wr = round(raw["wins"] / raw["trades"] * 100, 1) if raw["trades"] else 0
        match = (abs(s["pnl"] - raw["pnl"]) < 0.01 and
                 s["trades"] == raw["trades"] and
                 s["wins"] == raw["wins"] and
                 s["losses"] == raw["losses"] and
                 abs(s["winRate"] - raw_wr) < 0.1)
        status = "PASS" if match else "FAIL"
        if not match:
            all_pass = False
        print(f"    {s['name']:<20s}: PnL=${s['pnl']}, {s['trades']}T, "
              f"{s['wins']}W/{s['losses']}L, WR={s['winRate']}% [{status}]")
    else:
        print(f"    {s['name']:<20s}: NOT IN RAW LOGS (should not be here)")
        all_pass = False

# Check daily
print(f"\n  Daily PnL ({len(vcw['dailyPnl'])} days):")
for day in vcw["dailyPnl"]:
    ds = day["date"]
    raw_day = [t for t in all_settled if t["date"] == ds]
    expected_settled = len(raw_day)
    expected_wins = sum(1 for t in raw_day if t["wl"] == "WIN")
    expected_losses = sum(1 for t in raw_day if t["wl"] == "LOSS")
    match = (day["settledTrades"] == expected_settled and
             day["wins"] == expected_wins and
             day["losses"] == expected_losses)
    status = "PASS" if match else "FAIL"
    if not match:
        all_pass = False
    print(f"    {ds}: {day['settledTrades']} settled ({day['wins']}W/{day['losses']}L) [{status}]")

print(f"\n{'='*60}")
if all_pass:
    print("ALL CHECKS PASSED — metrics fully rebuilt from raw logs")
else:
    print("SOME CHECKS FAILED — review output above")
print(f"{'='*60}")
