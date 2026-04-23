#!/usr/bin/env bash
# bin/aether-weekly-summary.sh — Weekly synthesis of Aether daily analyses for Hyo
#
# Hyo directive 2026-04-23: Hyo does a manual analysis on weekly basis.
# This script prepares the week's data: collects all daily analyses,
# computes aggregate stats, and presents a clean summary for Hyo's review.
#
# Output: agents/aether/analysis/Weekly_Summary_YYYY-WNN.md
# Schedule: Saturday 06:00 MT via kai-autonomous.sh (cross-agent-review slot)
# Manual run: HYO_ROOT=... bash bin/aether-weekly-summary.sh

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
ANALYSIS_DIR="$ROOT/agents/aether/analysis"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
WEEK_NUM=$(TZ=America/Denver date +%V)
YEAR=$(TZ=America/Denver date +%Y)
OUTPUT="$ANALYSIS_DIR/Weekly_Summary_${YEAR}-W${WEEK_NUM}.md"
LOG="$ROOT/agents/aether/logs/weekly-summary.log"

log() { echo "[weekly-summary] $(TZ=America/Denver date +%H:%M:%S) $*" | tee -a "$LOG"; }

log "=== Weekly Aether Summary — Week ${WEEK_NUM} ==="

python3 - "$ROOT" "$ANALYSIS_DIR" "$OUTPUT" "$TODAY" "$YEAR" "$WEEK_NUM" << 'PYEOF'
import json, os, re, sys
from datetime import date, timedelta
from pathlib import Path

root, analysis_dir, output_path, today_str, year, week_num = sys.argv[1:7]
today = date.fromisoformat(today_str)

# Find this week's days (Mon-Sun)
week_start = today - timedelta(days=today.weekday())
week_days = [week_start + timedelta(days=i) for i in range(7)]
week_day_strs = [d.isoformat() for d in week_days]

# Collect this week's analyses
analyses = []
for day_str in week_day_strs:
    path = os.path.join(analysis_dir, f"Analysis_{day_str}.txt")
    if os.path.exists(path):
        with open(path) as f:
            content = f.read()
        analyses.append({"date": day_str, "content": content, "lines": len(content.splitlines())})

if not analyses:
    print(f"[weekly-summary] No analyses found for week {week_num}")
    sys.exit(0)

# Extract key metrics from each analysis
def extract_balance(text):
    m = re.search(r'\$(\d+\.\d+)\s*→\s*\$(\d+\.\d+)', text)
    if m:
        return float(m.group(1)), float(m.group(2))
    # Try table format
    m = re.search(r'\|\s*\$(\d+\.\d+)\s*\|\s*\$(\d+\.\d+)\s*\|', text)
    if m:
        return float(m.group(1)), float(m.group(2))
    return None, None

def extract_net(text):
    m = re.search(r'Day net[:\s]+([+-]?\$[\d.]+)', text, re.I)
    if m:
        v = m.group(1).replace('$','').replace('+','')
        try: return float(v)
        except: pass
    return 0.0

# Build weekly report
lines = []
lines.append(f"# Aether Weekly Summary — {year} Week {week_num}")
lines.append(f"Period: {week_days[0].isoformat()} — {week_days[-1].isoformat()}")
lines.append(f"Generated: {today_str} | Manual review by Hyo")
lines.append("")
lines.append("## Week at a Glance")
lines.append("")

total_pnl = 0.0
trading_days = 0
first_balance = None
last_balance = None

for a in analyses:
    o, c = extract_balance(a["content"])
    net = extract_net(a["content"])
    if o and c:
        if first_balance is None: first_balance = o
        last_balance = c
        trading_days += 1
        total_pnl += net
    lines.append(f"### {a['date']}")
    if o and c:
        sign = "+" if net >= 0 else ""
        lines.append(f"- Balance: ${o:.2f} → ${c:.2f} | Net: {sign}${net:.2f}")
    else:
        lines.append(f"- Analysis available ({a['lines']} lines)")
    
    # Extract key finding
    find = re.search(r'CRITICAL FINDING[:\s]+(.+)', a['content'], re.I)
    if find:
        lines.append(f"- Key finding: {find.group(1)[:120]}")
    lines.append("")

lines.append("## Week Totals")
lines.append(f"- Trading days with data: {trading_days}/7")
if first_balance and last_balance:
    week_pnl = last_balance - first_balance
    lines.append(f"- Starting balance: ${first_balance:.2f}")
    lines.append(f"- Ending balance: ${last_balance:.2f}")
    sign = "+" if week_pnl >= 0 else ""
    lines.append(f"- Week P&L: {sign}${week_pnl:.2f} ({sign}{week_pnl/first_balance*100:.1f}%)")
lines.append("")
lines.append("## Hyo's Manual Review Notes")
lines.append("_(Add observations, decisions, strategy changes below)_")
lines.append("")
lines.append("## Action Items from This Week")
lines.append("- [ ] Review strategy performance vs expectations")
lines.append("- [ ] Confirm balance reconciliation for each day")
lines.append("- [ ] Note any patterns for next week")

output = '\n'.join(lines)
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, 'w') as f:
    f.write(output)

print(f"[weekly-summary] Written: {output_path}")
print(f"[weekly-summary] Covered {len(analyses)} days, {trading_days} with balance data")
PYEOF

log "Weekly summary written: $OUTPUT"
