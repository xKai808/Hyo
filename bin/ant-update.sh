#!/usr/bin/env bash
# ant-update.sh — Rebuild ant-data.json from kai/ledger/api-usage.jsonl
# Runs nightly via launchd (23:45 MT) and on-demand via: kai ant-update
# Also writes monthly ledger to agents/ant/ledger/monthly-YYYY-MM.json
#
# Output (DUAL-PATH — both must be updated):
#   agents/sam/website/data/ant-data.json  ← read by HQ via /data/ant-data.json
#   website/data/ant-data.json             ← Vercel mirror
#
# PROTOCOL: PROTOCOL_ANT.md (agents/ant/) — read before modifying this script
# CREDIT BARS: credits.anthropic and credits.openai are populated from
#   api-usage.jsonl MTD spend vs ANT_MONTHLY_BUDGET_* config below.
#   No admin API key required — budget-based tracking.
#
# MONTHLY BUDGET CONFIG (update when plans change):
#   ANT_MONTHLY_BUDGET_ANTHROPIC: metered API credit budget per month ($USD)
#   ANT_MONTHLY_BUDGET_OPENAI:    metered API credit budget per month ($USD)
#   These appear as "total" in the credit bars on HQ Ant page.
ANT_MONTHLY_BUDGET_ANTHROPIC="${ANT_MONTHLY_BUDGET_ANTHROPIC:-10.00}"
ANT_MONTHLY_BUDGET_OPENAI="${ANT_MONTHLY_BUDGET_OPENAI:-10.00}"

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
USAGE_FILE="$ROOT/kai/ledger/api-usage.jsonl"
ANT_FILE="$ROOT/agents/sam/website/data/ant-data.json"
ANT_FILE2="$ROOT/website/data/ant-data.json"
ANT_MONTHLY_FILE="$ROOT/agents/ant/ledger/monthly-$(date +%Y-%m).json"
AETHER_METRICS="$ROOT/agents/sam/website/data/aether-metrics.json"

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
today = date.today()
today_str = today.isoformat()
this_month_prefix = today.strftime("%Y-%m")

# Monthly budget config from env (set in ant-update.sh header)
MONTHLY_BUDGET_ANTHROPIC = float(os.environ.get("ANT_MONTHLY_BUDGET_ANTHROPIC", "10.00"))
MONTHLY_BUDGET_OPENAI    = float(os.environ.get("ANT_MONTHLY_BUDGET_OPENAI", "10.00"))

# ── Load records ──────────────────────────────────────────────────────────────
records = []
with open("$USAGE_FILE") as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                records.append(json.loads(line))
            except:
                pass

# ── Aggregate: provider, date, agent, model ───────────────────────────────────
by_provider       = defaultdict(float)
by_date_provider  = defaultdict(lambda: defaultdict(float))
by_agent          = defaultdict(float)
by_model          = defaultdict(lambda: {'calls': 0, 'cost': 0.0})
by_month_provider = defaultdict(lambda: defaultdict(float))  # MTD per month

# Cost-per-process: new field (process_name in newer entries)
by_process        = defaultdict(lambda: {'runs': 0, 'total_cost': 0.0, 'last_run': ''})

for r in records:
    # Normalize field names (older records use 'cost_usd', newer may differ)
    cost = float(r.get('cost_usd', r.get('estimated_cost_usd', 0.0)))
    provider = r.get('provider', 'openai' if 'gpt' in r.get('model','') else 'anthropic')
    d = r.get('date', r.get('ts', today_str)[:10])
    agent = r.get('agent', 'unknown')
    model = r.get('model', 'unknown')
    process = r.get('process_name', agent)  # fallback to agent name

    by_provider[provider] += cost
    by_date_provider[d][provider] += cost
    by_agent[agent] += cost
    by_model[model]['calls'] += 1
    by_model[model]['cost'] += cost
    # MTD per month (for credit bar tracking)
    month_key = d[:7]  # "YYYY-MM"
    by_month_provider[month_key][provider] += cost

    by_process[process]['runs'] += 1
    by_process[process]['total_cost'] += cost
    ts = r.get('ts', r.get('date', ''))
    if ts > by_process[process]['last_run']:
        by_process[process]['last_run'] = ts

# ── MTD credit usage (this calendar month) ───────────────────────────────────
mtd_anthropic = by_month_provider[this_month_prefix].get('anthropic', 0.0)
mtd_openai    = by_month_provider[this_month_prefix].get('openai', 0.0)

credits_data = {
    "anthropic": {
        "monthly_budget": MONTHLY_BUDGET_ANTHROPIC,
        "used_mtd":       round(mtd_anthropic, 4),
        "remaining":      round(max(MONTHLY_BUDGET_ANTHROPIC - mtd_anthropic, 0), 4),
        "total":          MONTHLY_BUDGET_ANTHROPIC,
        "used":           round(mtd_anthropic, 4),
        "source":         "api-usage.jsonl MTD",
        "note":           f"Budget-based. MTD spend for {this_month_prefix}. For exact account balance, add Anthropic admin API key.",
        "expires":        None
    },
    "openai": {
        "monthly_budget": MONTHLY_BUDGET_OPENAI,
        "used_mtd":       round(mtd_openai, 4),
        "remaining":      round(max(MONTHLY_BUDGET_OPENAI - mtd_openai, 0), 4),
        "total":          MONTHLY_BUDGET_OPENAI,
        "used":           round(mtd_openai, 4),
        "source":         "api-usage.jsonl MTD",
        "note":           f"Budget-based. MTD spend for {this_month_prefix}. For exact balance, add OpenAI billing API key.",
        "expires":        None
    }
}

# ── 14-day history ────────────────────────────────────────────────────────────
history = []
for i in range(13, -1, -1):
    d = (today - timedelta(days=i)).isoformat()
    ant = by_date_provider[d].get('anthropic', 0.0)
    oai = by_date_provider[d].get('openai', 0.0)
    history.append({"date": d, "anthropic": round(ant, 4), "openai": round(oai, 4), "total": round(ant + oai, 4)})

# ── Burn rate ─────────────────────────────────────────────────────────────────
recent_days  = [(today - timedelta(days=i)).isoformat() for i in range(7)]
recent_costs = [sum(by_date_provider[d].values()) for d in recent_days if by_date_provider[d]]
daily_avg    = sum(recent_costs) / max(len(recent_costs), 1)

# Today's spend
today_spend = sum(by_date_provider[today_str].values())

# ── Budget alert logic ────────────────────────────────────────────────────────
DAILY_ALERT_USD = 1.00   # Warn Hyo if any single day exceeds \$1
PROCESS_ALERT_USD = 0.50 # Warn if any single process run exceeds \$0.50/run
alerts = []

if today_spend > DAILY_ALERT_USD:
    alerts.append({
        "level": "WARNING",
        "msg": f"Today's API spend (\${today_spend:.4f}) exceeds daily alert threshold (\${DAILY_ALERT_USD:.2f})",
        "ts": datetime.now(tz_mt).isoformat()
    })

# Check process-level: if any process has avg cost > threshold
for proc, stats in by_process.items():
    avg = stats['total_cost'] / max(stats['runs'], 1)
    if avg > PROCESS_ALERT_USD:
        alerts.append({
            "level": "WARNING",
            "msg": f"Process '{proc}' avg \${avg:.4f}/run over {stats['runs']} runs — exceeds \${PROCESS_ALERT_USD:.2f} threshold",
            "ts": datetime.now(tz_mt).isoformat()
        })

# ── Totals ────────────────────────────────────────────────────────────────────
total_anthropic = by_provider.get('anthropic', 0.0)
total_openai    = by_provider.get('openai', 0.0)
total_cost      = total_anthropic + total_openai

# ── Revenue: read Aether's trading P&L as income stream ──────────────────────
aether_pnl = 0.0
aether_balance = 0.0
aether_pnl_pct = 0.0
aether_week_start = ""
try:
    with open("$AETHER_METRICS") as af:
        am = json.load(af)
    cw = am.get("currentWeek", {})
    aether_pnl = cw.get("pnl", 0.0)
    aether_balance = cw.get("currentBalance", 0.0)
    aether_pnl_pct = cw.get("pnlPercent", 0.0)
    aether_week_start = cw.get("start", "")
except Exception:
    pass  # aether metrics unavailable — income shows 0

income_streams = []
if aether_pnl != 0.0:
    income_streams.append({
        "name": "AetherBot Trading",
        "source": "aether-metrics.json",
        "weekly_pnl": round(aether_pnl, 2),
        "pnl_pct": round(aether_pnl_pct, 2),
        "balance": round(aether_balance, 2),
        "week_start": aether_week_start,
        "note": "Current week P&L from autonomous trading"
    })
income_total = round(aether_pnl, 2)

# ── Known fixed expenses (monthly subscriptions) ──────────────────────────────
# Update when plans change.
fixed_subscriptions = [
    {"name": "Claude Max", "monthly": 200.00, "actual": 200.00, "category": "AI"},
    {"name": "GPT Plus",   "monthly": 20.00,  "actual": 20.00,  "category": "AI"},
]
api_items = [
    {"name": "Anthropic API", "actual": round(total_anthropic, 4), "category": "API"},
    {"name": "OpenAI API",    "actual": round(total_openai, 4),    "category": "API"},
]
total_fixed = sum(s["actual"] for s in fixed_subscriptions)
total_all_expenses = total_fixed + total_cost

# ── Build output ──────────────────────────────────────────────────────────────
data = {
    "status":     "active",
    "note":       "Costs from api-usage.jsonl. Revenue from aether-metrics.json. Subscriptions hardcoded.",
    "updatedAt":  datetime.now(tz_mt).isoformat(),
    "dataSource": "api-usage.jsonl + aether-metrics.json",
    "staleness":  {
        "lastUpdated": datetime.now(tz_mt).isoformat(),
        "staleAfterHours": 24,
        "note": "If updatedAt is >24h ago, Ant data is stale — check ant-update.sh cron"
    },
    "alerts": alerts,
    "costs": {
        "anthropic": {"total": round(total_anthropic, 4), "currency": "USD"},
        "openai":    {"total": round(total_openai, 4),    "currency": "USD"},
        "total":     round(total_cost, 4),
        "today":     round(today_spend, 4)
    },
    "burn": {
        "daily":       round(daily_avg, 4),
        "dailyBudget": 50,
        "pctOfBudget": round(daily_avg / 50 * 100, 1),
        "trend":       "stable" if len(recent_costs) >= 3 else "insufficient_data",
        "alertThreshold": DAILY_ALERT_USD
    },
    "byProcess": [
        {
            "process":    k,
            "runs":       v['runs'],
            "totalCost":  round(v['total_cost'], 6),
            "avgPerRun":  round(v['total_cost'] / max(v['runs'], 1), 6),
            "lastRun":    v['last_run']
        }
        for k, v in sorted(by_process.items(), key=lambda x: -x[1]['total_cost'])
    ],
    "revenue": {
        "monthly": income_total,
        "streams": income_streams
    },
    "income": {
        "total_monthly": income_total,
        "streams": income_streams
    },
    "expenses": {
        "subscriptions": fixed_subscriptions,
        "api": api_items,
        "infrastructure": [],
        "other": [],
        "total_fixed": round(total_fixed, 2),
        "total_api": round(total_cost, 4),
        "total": round(total_all_expenses, 4)
    },
    "income": {
        "total_monthly": income_total,
        "streams": income_streams
    },
    "expenses": {
        "subscriptions": fixed_subscriptions,
        "api": api_items,
        "infrastructure": [],
        "other": [],
        "total_fixed": round(total_fixed, 2),
        "total_api": round(total_cost, 4),
        "total": round(total_all_expenses, 4)
    },
    # credits: populated from MTD spend vs configurable monthly budget
    # HQ uses remaining/total to draw horizontal bars — no admin API key needed
    "credits": credits_data,
    "models": [
        {"name": k, "calls": v['calls'], "cost": round(v['cost'], 4)}
        for k, v in sorted(by_model.items(), key=lambda x: -x[1]['cost'])
    ],
    "agents": [
        {"name": k, "cost": round(v, 4)}
        for k, v in sorted(by_agent.items(), key=lambda x: -x[1])
    ],
    "history": history
}

out = json.dumps(data, indent=2)

for path in ["$ANT_FILE", "$ANT_FILE2"]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(out + "\n")

# ── Write monthly ledger record ───────────────────────────────────────────────
# agents/ant/ledger/monthly-YYYY-MM.json — persistent record for this month.
# Kept as a running snapshot; closed (status: "closed") on the 1st of next month.
monthly_record = {
    "month":        this_month_prefix,
    "generated_at": datetime.now(tz_mt).isoformat(),
    "status":       "open",
    "income": {
        "trading_pnl_wtd": round(aether_pnl, 2),
        "trading_balance":  round(aether_balance, 2),
        "week_start":       aether_week_start,
        "streams":          income_streams,
        "total_income_mtd": round(income_total, 2)
    },
    "expenses": {
        "subscriptions":    fixed_subscriptions,
        "api_anthropic_mtd": round(mtd_anthropic, 4),
        "api_openai_mtd":   round(mtd_openai, 4),
        "total_fixed":      round(total_fixed, 2),
        "total_api_mtd":    round(mtd_anthropic + mtd_openai, 4),
        "total_expenses":   round(total_fixed + mtd_anthropic + mtd_openai, 4)
    },
    "net_position": round(income_total - total_fixed - mtd_anthropic - mtd_openai, 4),
    "api_credits": {
        "anthropic": credits_data["anthropic"],
        "openai":    credits_data["openai"]
    },
    "notes": []
}

monthly_path = "$ANT_MONTHLY_FILE"
os.makedirs(os.path.dirname(monthly_path), exist_ok=True)
with open(monthly_path, "w") as f:
    json.dump(monthly_record, f, indent=2)
    f.write("\n")

print(f"[ant-update] Written to $ANT_FILE", file=sys.stderr)
print(f"[ant-update] Monthly ledger: {monthly_path}", file=sys.stderr)
print(f"[ant-update] MTD — Anthropic \${mtd_anthropic:.4f} / OpenAI \${mtd_openai:.4f}", file=sys.stderr)
print(f"[ant-update] Today spend: \${today_spend:.4f} | Total: \${total_cost:.4f}", file=sys.stderr)
if alerts:
    for a in alerts:
        print(f"[ant-update] {a['level']}: {a['msg']}", file=sys.stderr)
PYEOF

echo "[ant-update] Done."
