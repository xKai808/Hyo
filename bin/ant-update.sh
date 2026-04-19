#!/usr/bin/env bash
# ant-update.sh — Rebuild ant-data.json from kai/ledger/api-usage.jsonl
# Runs nightly via launchd (23:45 MT) and on-demand via: kai ant-update
# Also writes monthly ledger to agents/ant/ledger/monthly-YYYY-MM.json
#
# Output (DUAL-PATH — both must be updated):
#   agents/sam/website/data/ant-data.json  ← read by HQ via /data/ant-data.json
#   website/data/ant-data.json             ← Vercel mirror
#
# PROTOCOL: agents/ant/PROTOCOL_ANT.md — read before modifying this script
#
# CREDITS: Two-tier system:
#   1. Real balance from agents/ant/ledger/scraped-credits.json (kai ant-scrape)
#   2. Budget-based fallback from ANT_MONTHLY_BUDGET_* env vars
#
# MONTHLY BUDGET CONFIG (update when plans change):
#   ANT_MONTHLY_BUDGET_ANTHROPIC: account credit total ($USD)
#   ANT_MONTHLY_BUDGET_OPENAI:    account credit total ($USD)
ANT_MONTHLY_BUDGET_ANTHROPIC="${ANT_MONTHLY_BUDGET_ANTHROPIC:-40.00}"
ANT_MONTHLY_BUDGET_OPENAI="${ANT_MONTHLY_BUDGET_OPENAI:-20.00}"

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
USAGE_FILE="$ROOT/kai/ledger/api-usage.jsonl"
ANT_FILE="$ROOT/agents/sam/website/data/ant-data.json"
ANT_FILE2="$ROOT/website/data/ant-data.json"
ANT_MONTHLY_FILE="$ROOT/agents/ant/ledger/monthly-$(date +%Y-%m).json"
AETHER_METRICS="$ROOT/agents/sam/website/data/aether-metrics.json"
SCRAPED_CREDITS="$ROOT/agents/ant/ledger/scraped-credits.json"

if [[ ! -f "$USAGE_FILE" ]]; then
    echo "[ant-update] ERROR: $USAGE_FILE not found" >&2
    exit 1
fi

echo "[ant-update] Rebuilding ant-data.json from $USAGE_FILE..."

# Export all paths as env vars — Python reads via os.environ
# Using quoted heredoc (<< 'PYEOF') to prevent bash from expanding ${} inside Python f-strings
export ANT_ROOT="$ROOT"
export ANT_USAGE_FILE="$USAGE_FILE"
export ANT_OUT_FILE="$ANT_FILE"
export ANT_OUT_FILE2="$ANT_FILE2"
export ANT_MONTHLY_PATH="$ANT_MONTHLY_FILE"
export ANT_AETHER_METRICS="$AETHER_METRICS"
export ANT_SCRAPED_CREDITS="$SCRAPED_CREDITS"

python3 << 'PYEOF'
import json, sys, os
from collections import defaultdict
from datetime import datetime, date, timedelta, timezone

# All paths from environment — safe with quoted heredoc
ROOT            = os.environ["ANT_ROOT"]
USAGE_FILE      = os.environ["ANT_USAGE_FILE"]
ANT_FILE        = os.environ["ANT_OUT_FILE"]
ANT_FILE2       = os.environ["ANT_OUT_FILE2"]
ANT_MONTHLY_FILE= os.environ["ANT_MONTHLY_PATH"]
AETHER_METRICS  = os.environ["ANT_AETHER_METRICS"]
SCRAPED_CREDITS_FILE = os.environ["ANT_SCRAPED_CREDITS"]

MONTHLY_BUDGET_ANTHROPIC = float(os.environ.get("ANT_MONTHLY_BUDGET_ANTHROPIC", "40.00"))
MONTHLY_BUDGET_OPENAI    = float(os.environ.get("ANT_MONTHLY_BUDGET_OPENAI",    "20.00"))

tz_mt = timezone(timedelta(hours=-6))
today = date.today()
today_str = today.isoformat()
this_month_prefix = today.strftime("%Y-%m")

# ── Load scraped credit data (real values from billing consoles) ───────────────
# scraped-credits.json is written by: kai ant-scrape (browser automation via Cowork)
# If exists and <48h old → real values. Otherwise → budget-based fallback.
_scraped = None
_scraped_age_h = None
try:
    with open(SCRAPED_CREDITS_FILE) as _f:
        _scraped = json.load(_f)
    _st = datetime.fromisoformat(_scraped["scraped_at"])
    _scraped_age_h = (datetime.now(timezone.utc) - _st.astimezone(timezone.utc)).total_seconds() / 3600
    if _scraped_age_h > 48:
        print(f"[ant-update] scraped-credits.json is {_scraped_age_h:.0f}h old — run 'kai ant-scrape' to refresh", file=sys.stderr)
except Exception:
    _scraped = None

# ── Load records ──────────────────────────────────────────────────────────────
records = []
with open(USAGE_FILE) as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                records.append(json.loads(line))
            except Exception:
                pass

# ── Aggregate ─────────────────────────────────────────────────────────────────
by_provider       = defaultdict(float)
by_date_provider  = defaultdict(lambda: defaultdict(float))
by_agent          = defaultdict(float)
by_model          = defaultdict(lambda: {"calls": 0, "cost": 0.0})
by_month_provider = defaultdict(lambda: defaultdict(float))
by_process        = defaultdict(lambda: {"runs": 0, "total_cost": 0.0, "last_run": ""})

for r in records:
    cost     = float(r.get("cost_usd", r.get("estimated_cost_usd", 0.0)))
    provider = r.get("provider", "openai" if "gpt" in r.get("model", "") else "anthropic")
    d        = r.get("date", r.get("ts", today_str)[:10])
    agent    = r.get("agent", "unknown")
    model    = r.get("model", "unknown")
    process  = r.get("process_name", agent)

    by_provider[provider]            += cost
    by_date_provider[d][provider]    += cost
    by_agent[agent]                  += cost
    by_model[model]["calls"]         += 1
    by_model[model]["cost"]          += cost
    by_month_provider[d[:7]][provider] += cost
    by_process[process]["runs"]      += 1
    by_process[process]["total_cost"]+= cost
    ts = r.get("ts", r.get("date", ""))
    if ts > by_process[process]["last_run"]:
        by_process[process]["last_run"] = ts

# ── MTD spend ────────────────────────────────────────────────────────────────
mtd_anthropic = by_month_provider[this_month_prefix].get("anthropic", 0.0)
mtd_openai    = by_month_provider[this_month_prefix].get("openai", 0.0)

# ── Credits: real (scraped) → budget-based fallback ──────────────────────────
if _scraped and _scraped_age_h is not None and _scraped_age_h <= 48:
    _ant = _scraped.get("anthropic", {})
    _oai = _scraped.get("openai", {})
    _age_label = f"scraped {_scraped_age_h:.0f}h ago"
    credits_data = {
        "anthropic": {
            "remaining":  _ant.get("remaining"),
            "total":      _ant.get("total"),
            "used":       _ant.get("used"),
            "used_mtd":   round(mtd_anthropic, 4),
            "expires":    _ant.get("expires"),
            "source":     f"console.anthropic.com (screen-scraped, {_age_label})",
            "scraped_at": _scraped.get("scraped_at"),
            "note":       "Real account balance from Anthropic console."
        },
        "openai": {
            "remaining":  _oai.get("remaining"),
            "total":      _oai.get("total"),
            "used":       _oai.get("used"),
            "used_mtd":   round(mtd_openai, 4),
            "expires":    _oai.get("expires"),
            "source":     f"platform.openai.com (screen-scraped, {_age_label})",
            "scraped_at": _scraped.get("scraped_at"),
            "note":       "Real account balance from OpenAI platform."
        }
    }
    print(f"[ant-update] Real scraped credits ({_age_label}): Anthropic ${_ant.get('remaining'):.2f}/{_ant.get('total'):.2f} | OpenAI ${_oai.get('remaining'):.2f}/{_oai.get('total'):.2f}", file=sys.stderr)
else:
    credits_data = {
        "anthropic": {
            "monthly_budget": MONTHLY_BUDGET_ANTHROPIC,
            "used_mtd":       round(mtd_anthropic, 4),
            "remaining":      round(max(MONTHLY_BUDGET_ANTHROPIC - mtd_anthropic, 0), 4),
            "total":          MONTHLY_BUDGET_ANTHROPIC,
            "used":           round(mtd_anthropic, 4),
            "source":         "api-usage.jsonl MTD (budget-based fallback)",
            "note":           f"No recent scrape. Run 'kai ant-scrape' to get real balance. Fallback for {this_month_prefix}.",
            "expires":        None
        },
        "openai": {
            "monthly_budget": MONTHLY_BUDGET_OPENAI,
            "used_mtd":       round(mtd_openai, 4),
            "remaining":      round(max(MONTHLY_BUDGET_OPENAI - mtd_openai, 0), 4),
            "total":          MONTHLY_BUDGET_OPENAI,
            "used":           round(mtd_openai, 4),
            "source":         "api-usage.jsonl MTD (budget-based fallback)",
            "note":           "No recent scrape. Run 'kai ant-scrape' from Cowork.",
            "expires":        None
        }
    }
    print("[ant-update] WARNING: No fresh scraped-credits — using budget-based fallback. Run 'kai ant-scrape'.", file=sys.stderr)

# ── 14-day daily history (per provider) ──────────────────────────────────────
# This powers the "Daily Credit Usage" stacked bar chart on HQ Ant tab.
# Each entry: { date, anthropic, openai, total }
history = []
for i in range(13, -1, -1):
    d   = (today - timedelta(days=i)).isoformat()
    ant = by_date_provider[d].get("anthropic", 0.0)
    oai = by_date_provider[d].get("openai", 0.0)
    history.append({"date": d, "anthropic": round(ant, 4), "openai": round(oai, 4), "total": round(ant + oai, 4)})

# ── Burn rate ─────────────────────────────────────────────────────────────────
recent_days  = [(today - timedelta(days=i)).isoformat() for i in range(7)]
recent_costs = [sum(by_date_provider[d].values()) for d in recent_days if by_date_provider[d]]
daily_avg    = sum(recent_costs) / max(len(recent_costs), 1)
today_spend  = sum(by_date_provider[today_str].values())

# ── Alerts ────────────────────────────────────────────────────────────────────
DAILY_ALERT_USD   = 1.00
PROCESS_ALERT_USD = 0.50
alerts = []
if today_spend > DAILY_ALERT_USD:
    alerts.append({
        "level": "WARNING",
        "msg":   f"Today's API spend (${today_spend:.4f}) exceeds daily alert threshold (${DAILY_ALERT_USD:.2f})",
        "ts":    datetime.now(tz_mt).isoformat()
    })
for proc, stats in by_process.items():
    avg = stats["total_cost"] / max(stats["runs"], 1)
    if avg > PROCESS_ALERT_USD:
        alerts.append({
            "level": "WARNING",
            "msg":   f"Process '{proc}' avg ${avg:.4f}/run over {stats['runs']} runs — exceeds ${PROCESS_ALERT_USD:.2f} threshold",
            "ts":    datetime.now(tz_mt).isoformat()
        })

# ── Totals ─────────────────────────────────────────────────────────────────────
total_anthropic = by_provider.get("anthropic", 0.0)
total_openai    = by_provider.get("openai", 0.0)
total_cost      = total_anthropic + total_openai

# ── Revenue: AetherBot P&L ────────────────────────────────────────────────────
aether_pnl = 0.0
aether_balance = 0.0
aether_pnl_pct = 0.0
aether_week_start = ""
try:
    with open(AETHER_METRICS) as af:
        am = json.load(af)
    cw = am.get("currentWeek", {})
    aether_pnl       = cw.get("pnl", 0.0)
    aether_balance   = cw.get("currentBalance", 0.0)
    aether_pnl_pct   = cw.get("pnlPercent", 0.0)
    aether_week_start= cw.get("start", "")
except Exception:
    pass

income_streams = []
if aether_pnl != 0.0:
    income_streams.append({
        "name":       "AetherBot Trading",
        "source":     "aether-metrics.json",
        "weekly_pnl": round(aether_pnl, 2),
        "pnl_pct":    round(aether_pnl_pct, 2),
        "balance":    round(aether_balance, 2),
        "week_start": aether_week_start,
        "note":       "Current week P&L from autonomous trading"
    })
income_total = round(aether_pnl, 2)

# ── Fixed expenses (hardcoded — update when plans change) ─────────────────────
fixed_subscriptions = [
    {"name": "Claude Max", "monthly": 200.00, "actual": 200.00, "category": "AI"},
    {"name": "GPT Plus",   "monthly": 20.00,  "actual": 20.00,  "category": "AI"},
]
api_items = [
    {"name": "Anthropic API", "actual": round(total_anthropic, 4), "category": "API"},
    {"name": "OpenAI API",    "actual": round(total_openai, 4),    "category": "API"},
]
total_fixed        = sum(s["actual"] for s in fixed_subscriptions)
total_all_expenses = total_fixed + total_cost

# ── Build output ──────────────────────────────────────────────────────────────
data = {
    "status":     "active",
    "note":       "Costs from api-usage.jsonl. Revenue from aether-metrics.json. Subscriptions hardcoded.",
    "updatedAt":  datetime.now(tz_mt).isoformat(),
    "dataSource": "api-usage.jsonl + aether-metrics.json",
    "staleness": {
        "lastUpdated":     datetime.now(tz_mt).isoformat(),
        "staleAfterHours": 24,
        "note":            "If updatedAt is >24h ago, Ant data is stale — check ant-update.sh cron"
    },
    "alerts": alerts,
    "costs": {
        "anthropic": {"total": round(total_anthropic, 4), "currency": "USD"},
        "openai":    {"total": round(total_openai, 4),    "currency": "USD"},
        "total":     round(total_cost, 4),
        "today":     round(today_spend, 4)
    },
    "burn": {
        "daily":          round(daily_avg, 4),
        "dailyBudget":    50,
        "pctOfBudget":    round(daily_avg / 50 * 100, 1),
        "trend":          "stable" if len(recent_costs) >= 3 else "insufficient_data",
        "alertThreshold": DAILY_ALERT_USD
    },
    "byProcess": [
        {
            "process":   k,
            "runs":      v["runs"],
            "totalCost": round(v["total_cost"], 6),
            "avgPerRun": round(v["total_cost"] / max(v["runs"], 1), 6),
            "lastRun":   v["last_run"]
        }
        for k, v in sorted(by_process.items(), key=lambda x: -x[1]["total_cost"])
    ],
    "income": {
        "total_monthly": income_total,
        "streams":       income_streams
    },
    "expenses": {
        "subscriptions": fixed_subscriptions,
        "api":           api_items,
        "infrastructure":[],
        "other":         [],
        "total_fixed":   round(total_fixed, 2),
        "total_api":     round(total_cost, 4),
        "total":         round(total_all_expenses, 4)
    },
    # credits: HQ uses remaining/total to draw horizontal bars
    "credits": credits_data,
    "models": [
        {"name": k, "calls": v["calls"], "cost": round(v["cost"], 4)}
        for k, v in sorted(by_model.items(), key=lambda x: -x[1]["cost"])
    ],
    "agents": [
        {"name": k, "cost": round(v, 4)}
        for k, v in sorted(by_agent.items(), key=lambda x: -x[1])
    ],
    # history: 14-day daily usage by provider — used by HQ "Daily Credit Usage" chart
    "history": history
}

out = json.dumps(data, indent=2)
for path in [ANT_FILE, ANT_FILE2]:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(out + "\n")

# ── Monthly ledger ─────────────────────────────────────────────────────────────
monthly_record = {
    "month":        this_month_prefix,
    "generated_at": datetime.now(tz_mt).isoformat(),
    "status":       "open",
    "income": {
        "trading_pnl_wtd":  round(aether_pnl, 2),
        "trading_balance":  round(aether_balance, 2),
        "week_start":       aether_week_start,
        "streams":          income_streams,
        "total_income_mtd": round(income_total, 2)
    },
    "expenses": {
        "subscriptions":     fixed_subscriptions,
        "api_anthropic_mtd": round(mtd_anthropic, 4),
        "api_openai_mtd":    round(mtd_openai, 4),
        "total_fixed":       round(total_fixed, 2),
        "total_api_mtd":     round(mtd_anthropic + mtd_openai, 4),
        "total_expenses":    round(total_fixed + mtd_anthropic + mtd_openai, 4)
    },
    "net_position": round(income_total - total_fixed - mtd_anthropic - mtd_openai, 4),
    "api_credits": {
        "anthropic": credits_data["anthropic"],
        "openai":    credits_data["openai"]
    },
    "notes": []
}
os.makedirs(os.path.dirname(ANT_MONTHLY_FILE), exist_ok=True)
with open(ANT_MONTHLY_FILE, "w") as f:
    json.dump(monthly_record, f, indent=2)
    f.write("\n")

print(f"[ant-update] Written: {ANT_FILE}", file=sys.stderr)
print(f"[ant-update] Monthly ledger: {ANT_MONTHLY_FILE}", file=sys.stderr)
print(f"[ant-update] MTD — Anthropic: ${mtd_anthropic:.4f} | OpenAI: ${mtd_openai:.4f}", file=sys.stderr)
print(f"[ant-update] Today: ${today_spend:.4f} | All-time: ${total_cost:.4f}", file=sys.stderr)
print(f"[ant-update] Credits — Anthropic ${credits_data['anthropic']['remaining']}/{credits_data['anthropic']['total']} | OpenAI ${credits_data['openai']['remaining']}/{credits_data['openai']['total']}", file=sys.stderr)
PYEOF

echo "[ant-update] Done."
