#!/usr/bin/env bash
# ant-update.sh — Rebuild ant-data.json from kai/ledger/api-usage.jsonl
# Runs as part of Sam's daily report cycle and on-demand via: kai ant-update
#
# Output: agents/sam/website/data/ant-data.json + website/data/ant-data.json

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
USAGE_FILE="$ROOT/kai/ledger/api-usage.jsonl"
ANT_FILE="$ROOT/agents/sam/website/data/ant-data.json"
ANT_FILE2="$ROOT/website/data/ant-data.json"

if [[ ! -f "$USAGE_FILE" ]]; then
    echo "[ant-update] ERROR: $USAGE_FILE not found" >&2
    exit 1
fi

echo "[ant-update] Rebuilding ant-data.json from $USAGE_FILE..."

python3 << PYEOF
import json, sys, os
from collections import defaultdict
from datetime import datetime, date, timedelta, timezone

tz_mt = timezone(timedelta(hours=-6))

records = []
with open("$USAGE_FILE") as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                records.append(json.loads(line))
            except:
                pass

# By provider
by_provider = defaultdict(float)
for r in records:
    by_provider[r['provider']] += r['cost_usd']

# By date+provider
by_date_provider = defaultdict(lambda: defaultdict(float))
for r in records:
    by_date_provider[r['date']][r['provider']] += r['cost_usd']

# By agent
by_agent = defaultdict(float)
for r in records:
    by_agent[r['agent']] += r['cost_usd']

# By model
by_model = defaultdict(lambda: {'calls': 0, 'cost': 0.0})
for r in records:
    by_model[r['model']]['calls'] += 1
    by_model[r['model']]['cost'] += r['cost_usd']

# 14-day history
today = date.today()
history = []
for i in range(13, -1, -1):
    d = (today - timedelta(days=i)).isoformat()
    ant = by_date_provider[d].get('anthropic', 0.0)
    oai = by_date_provider[d].get('openai', 0.0)
    history.append({"date": d, "anthropic": round(ant, 4), "openai": round(oai, 4), "total": round(ant + oai, 4)})

# Compute daily burn from last 7 days
recent_days = [(today - timedelta(days=i)).isoformat() for i in range(7)]
recent_costs = [sum(by_date_provider[d].values()) for d in recent_days if by_date_provider[d]]
daily_avg = sum(recent_costs) / max(len(recent_costs), 1)

total_anthropic = by_provider.get('anthropic', 0.0)
total_openai = by_provider.get('openai', 0.0)
total_cost = total_anthropic + total_openai

data = {
    "status": "active",
    "note": "Costs sourced from kai/ledger/api-usage.jsonl. Self-reported via api-usage.sh instrumentation. Admin API key not configured.",
    "updatedAt": datetime.now(tz_mt).isoformat(),
    "dataSource": "api-usage.jsonl",
    "costs": {
        "anthropic": {"total": round(total_anthropic, 4), "currency": "USD"},
        "openai": {"total": round(total_openai, 4), "currency": "USD"},
        "total": round(total_cost, 4)
    },
    "burn": {
        "daily": round(daily_avg, 4),
        "dailyBudget": 50,
        "pctOfBudget": round(daily_avg / 50 * 100, 1),
        "trend": "stable" if len(recent_costs) >= 3 else "insufficient_data"
    },
    "revenue": {"monthly": 0, "streams": []},
    "credits": {
        "anthropic": {"available": None, "note": "Admin API key required"},
        "openai": {"available": None, "note": "Admin API key required"}
    },
    "models": [
        {"name": k, "calls": v['calls'], "cost": round(v['cost'], 4)}
        for k, v in by_model.items()
    ],
    "agents": [
        {"name": k, "cost": round(v, 4)}
        for k, v in sorted(by_agent.items(), key=lambda x: -x[1])
    ],
    "history": history
}

out = json.dumps(data, indent=2)
print(out)

# Write both paths
for path in ["$ANT_FILE", "$ANT_FILE2"]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(out + "\n")

print(f"\n[ant-update] Written to $ANT_FILE", file=sys.stderr)
print(f"[ant-update] Written to $ANT_FILE2", file=sys.stderr)
print(f"[ant-update] Total cost: \${data['costs']['total']:.4f}", file=sys.stderr)
PYEOF

echo "[ant-update] Done."
