#!/usr/bin/env python3
"""
Full audit of AetherBot raw logs for the current week.
Parses EVERY line. No shortcuts. No assumptions.
Outputs: trade-by-trade breakdown, per-strategy stats, balance tracking.
"""

import os, re, json, sys
from collections import defaultdict
from datetime import datetime, timedelta

log_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
hyo_root = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))

# Determine week dates from current metrics
metrics_path = os.path.join(hyo_root, "website/data/aether-metrics.json")
with open(metrics_path) as f:
    metrics = json.load(f)

cw = metrics.get("currentWeek", {})
week_start = cw.get("start", "2026-04-13")
week_end = cw.get("end", "2026-04-19")
starting_balance = cw.get("startingBalance", 90.25)

print(f"=== AETHER RAW LOG AUDIT ===")
print(f"Week: {week_start} to {week_end}")
print(f"Starting balance: ${starting_balance}")
print(f"Log directory: {log_dir}")
print()

# Read ALL log files for the week
all_lines = []
d = datetime.strptime(week_start, "%Y-%m-%d").date()
today = datetime.now().date()
end_d = min(datetime.strptime(week_end, "%Y-%m-%d").date(), today)

while d <= end_d:
    ds = d.strftime("%Y-%m-%d")
    path = os.path.join(log_dir, f"AetherBot_{ds}.txt")
    if os.path.isfile(path):
        with open(path) as f:
            lines = f.readlines()
        print(f"  {ds}: {len(lines)} lines, {os.path.getsize(path):,} bytes")
        for line in lines:
            all_lines.append((ds, line))
    else:
        print(f"  {ds}: MISSING")
    d += timedelta(days=1)

print(f"\nTotal lines across all days: {len(all_lines):,}")

# ─── Find EVERY line containing SETTLED ───
settled_lines = [(ds, line.strip()) for ds, line in all_lines if "SETTLED" in line]
print(f"Lines containing 'SETTLED': {len(settled_lines)}")

# Show first and last settled lines verbatim
print("\n=== FIRST 5 SETTLED LINES (verbatim) ===")
for ds, line in settled_lines[:5]:
    print(f"  [{ds}] {line[:300]}")

print(f"\n=== LAST 5 SETTLED LINES (verbatim) ===")
for ds, line in settled_lines[-5:]:
    print(f"  [{ds}] {line[:300]}")

# ─── Parse with regex ───
# Pattern matches: WIN SETTLED | STRATEGY | ... NET +$X.XX | bal $Y.YY
pattern = re.compile(
    r'(WIN|LOSS)\s+SETTLED\s+\|\s+(\S+)\s+\|.*?NET\s+([+-]?\$[\d.]+)\s*\|\s*bal\s+\$([\d.]+)'
)

matched = []
unmatched = []
for ds, line in settled_lines:
    m = pattern.search(line)
    if m:
        wl = m.group(1)
        strat = m.group(2)
        net_raw = m.group(3)
        # Parse NET value
        net_str = net_raw.replace('$', '').replace('+', '')
        net = float(net_str)
        bal = float(m.group(4))
        matched.append({
            "date": ds, "wl": wl, "strat": strat,
            "net_raw": net_raw, "net": net, "bal": bal,
            "line": line[:200]
        })
    else:
        unmatched.append((ds, line[:300]))

print(f"\n=== REGEX RESULTS ===")
print(f"Matched: {len(matched)}")
print(f"Unmatched: {len(unmatched)}")

if unmatched:
    print(f"\n=== UNMATCHED SETTLED LINES (THESE ARE MISSING FROM METRICS) ===")
    for ds, line in unmatched:
        print(f"  [{ds}] {line}")

# ─── Print EVERY matched trade ───
print(f"\n=== ALL {len(matched)} MATCHED TRADES ===")
for i, t in enumerate(matched):
    print(f"  {i+1:3d}. [{t['date']}] {t['wl']:4s} | {t['strat']:20s} | NET {t['net_raw']:>8s} | bal ${t['bal']:>8.2f}")

# ─── Weekly totals ───
total = len(matched)
wins = sum(1 for t in matched if t["wl"] == "WIN")
losses = sum(1 for t in matched if t["wl"] == "LOSS")
total_net = round(sum(t["net"] for t in matched), 2)
win_rate = round(wins / total * 100, 1) if total else 0.0

print(f"\n{'='*60}")
print(f"=== WEEKLY TOTALS (from raw logs, every trade) ===")
print(f"{'='*60}")
print(f"Total settled trades: {total}")
print(f"Wins: {wins}")
print(f"Losses: {losses}")
print(f"Win rate: {win_rate}% ({wins}/{total})")
print(f"Sum of settled NET: ${total_net}")

# ─── Per strategy ───
strats = defaultdict(lambda: {"pnl": 0.0, "trades": 0, "wins": 0, "losses": 0})
for t in matched:
    s = strats[t["strat"]]
    s["pnl"] = round(s["pnl"] + t["net"], 2)
    s["trades"] += 1
    if t["wl"] == "WIN":
        s["wins"] += 1
    else:
        s["losses"] += 1

print(f"\n=== PER-STRATEGY BREAKDOWN ===")
print(f"  {'Strategy':<20s} {'PnL':>10s} {'Trades':>7s} {'W':>4s} {'L':>4s} {'WR':>7s}")
print(f"  {'-'*20} {'-'*10} {'-'*7} {'-'*4} {'-'*4} {'-'*7}")
for name in sorted(strats.keys(), key=lambda n: strats[n]["pnl"], reverse=True):
    s = strats[name]
    wr = round(s["wins"] / s["trades"] * 100, 1) if s["trades"] else 0.0
    print(f"  {name:<20s} ${s['pnl']:>8.2f} {s['trades']:>7d} {s['wins']:>4d} {s['losses']:>4d} {wr:>6.1f}%")

# ─── Balance tracking ───
print(f"\n=== BALANCE TRACKING ===")
# Get ALL balance mentions from ALL lines
all_bals = []
for ds, line in all_lines:
    for b in re.finditer(r'bal\s+\$([\d.]+)', line):
        all_bals.append((ds, float(b.group(1))))

if all_bals:
    print(f"Total balance mentions in logs: {len(all_bals)}")
    print(f"First balance: ${all_bals[0][1]} ({all_bals[0][0]})")
    print(f"Last balance: ${all_bals[-1][1]} ({all_bals[-1][0]})")
    print(f"Min balance: ${min(b for _, b in all_bals)}")
    print(f"Max balance: ${max(b for _, b in all_bals)}")

# ─── Per-day balance at end of day ───
print(f"\n=== PER-DAY ENDING BALANCE ===")
day_bals = defaultdict(list)
for ds, bal in all_bals:
    day_bals[ds].append(bal)
for ds in sorted(day_bals.keys()):
    bals = day_bals[ds]
    print(f"  {ds}: start ${bals[0]}, end ${bals[-1]}, trades that day: {sum(1 for t in matched if t['date'] == ds)}")

# ─── Balance-based P&L ───
if all_bals:
    latest_bal = all_bals[-1][1]
    balance_pnl = round(latest_bal - starting_balance, 2)
    balance_pnl_pct = round(balance_pnl / starting_balance * 100, 2) if starting_balance else 0
    print(f"\n=== BALANCE-BASED P&L ===")
    print(f"Starting balance: ${starting_balance}")
    print(f"Current balance: ${latest_bal}")
    print(f"P&L: ${balance_pnl} ({balance_pnl_pct}%)")
    print(f"Premium collection (inferred): ${round(balance_pnl - total_net, 2)}")

# ─── Compare against current metrics JSON ───
print(f"\n{'='*60}")
print(f"=== COMPARISON: RAW LOGS vs CURRENT METRICS JSON ===")
print(f"{'='*60}")

json_bal = cw.get("currentBalance", 0)
json_pnl = cw.get("pnl", 0)
json_pnl_pct = cw.get("pnlPercent", 0)
json_wins = cw.get("wins", 0)
json_losses = cw.get("losses", 0)
json_wr = cw.get("winRate", 0)
json_settled = cw.get("settledTrades", 0)

if all_bals:
    latest_bal = all_bals[-1][1]
    balance_pnl = round(latest_bal - starting_balance, 2)
    balance_pnl_pct = round(balance_pnl / starting_balance * 100, 2) if starting_balance else 0
else:
    latest_bal = 0
    balance_pnl = 0
    balance_pnl_pct = 0

def check(label, raw_val, json_val, tolerance=0.01):
    match = abs(raw_val - json_val) < tolerance if isinstance(raw_val, float) else raw_val == json_val
    status = "OK" if match else "MISMATCH"
    print(f"  {label:<25s}: raw={raw_val:<12} json={json_val:<12} [{status}]")
    return match

all_ok = True
all_ok &= check("Current Balance", latest_bal, json_bal, 0.05)
all_ok &= check("P&L", balance_pnl, json_pnl, 0.05)
all_ok &= check("P&L %", balance_pnl_pct, json_pnl_pct, 0.1)
all_ok &= check("Wins", wins, json_wins)
all_ok &= check("Losses", losses, json_losses)
all_ok &= check("Win Rate", win_rate, json_wr, 0.2)
all_ok &= check("Settled Trades", total, json_settled)

# Check strategies
print(f"\n  Strategy comparison:")
json_strats = {s["name"]: s for s in cw.get("strategies", [])}
for name in sorted(set(list(strats.keys()) + list(json_strats.keys()))):
    raw = strats.get(name)
    js = json_strats.get(name)
    if raw and js:
        raw_wr = round(raw["wins"] / raw["trades"] * 100, 1) if raw["trades"] else 0
        pnl_ok = abs(raw["pnl"] - js.get("pnl", 0)) < 0.05
        wr_ok = abs(raw_wr - js.get("winRate", 0)) < 0.2
        trades_ok = raw["trades"] == js.get("trades", 0)
        status = "OK" if (pnl_ok and wr_ok and trades_ok) else "MISMATCH"
        if status == "MISMATCH":
            all_ok = False
            print(f"    {name}: [{status}]")
            print(f"      PnL: raw=${raw['pnl']:.2f} vs json=${js.get('pnl',0):.2f} {'OK' if pnl_ok else 'WRONG'}")
            print(f"      WR:  raw={raw_wr}% vs json={js.get('winRate',0)}% {'OK' if wr_ok else 'WRONG'}")
            print(f"      Trades: raw={raw['trades']} vs json={js.get('trades',0)} {'OK' if trades_ok else 'WRONG'}")
            print(f"      W/L: raw={raw['wins']}W/{raw['losses']}L vs json={js.get('wins','?')}W/{js.get('losses','?')}L")
        else:
            print(f"    {name}: [OK]")
    elif raw and not js:
        all_ok = False
        print(f"    {name}: [MISSING FROM JSON]")
    elif js and not raw:
        print(f"    {name}: [IN JSON BUT NOT IN RAW LOGS — may be from prior week]")

print(f"\n{'='*60}")
if all_ok:
    print("RESULT: ALL METRICS MATCH RAW LOGS")
else:
    print("RESULT: MISMATCHES FOUND — CORRECTIONS NEEDED")
print(f"{'='*60}")

# Output the correct values as JSON for fixing
correct = {
    "currentBalance": latest_bal if all_bals else 0,
    "startingBalance": starting_balance,
    "pnl": balance_pnl,
    "pnlPercent": balance_pnl_pct,
    "wins": wins,
    "losses": losses,
    "winRate": win_rate,
    "settledTrades": total,
    "strategies": {}
}
for name, s in strats.items():
    wr = round(s["wins"] / s["trades"] * 100, 1) if s["trades"] else 0
    correct["strategies"][name] = {
        "pnl": round(s["pnl"], 2),
        "trades": s["trades"],
        "wins": s["wins"],
        "losses": s["losses"],
        "winRate": wr
    }

# Write correct values to a temp file for the fix script
out_path = os.path.join(hyo_root, "kai/tools/audit_result.json")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    json.dump(correct, f, indent=2)
print(f"\nCorrect values written to {out_path}")
