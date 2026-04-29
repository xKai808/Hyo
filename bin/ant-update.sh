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
# Strategy: use scraped data as the BASE even if stale — then subtract spend SINCE
# the scrape date to get a continuously-updated estimate. Never reset monthly.
# Only fall back to budget-based if no scrape file exists at all.
_scraped = None
_scraped_age_h = None
try:
    with open(SCRAPED_CREDITS_FILE) as _f:
        _scraped = json.load(_f)
    _st = datetime.fromisoformat(_scraped["scraped_at"])
    _scraped_age_h = (datetime.now(timezone.utc) - _st.astimezone(timezone.utc)).total_seconds() / 3600
    if _scraped_age_h > 96:
        print(f"[ant-update] WARNING: scraped-credits.json is {_scraped_age_h:.0f}h old. Run 'kai ant-scrape' for accuracy.", file=sys.stderr)
    else:
        print(f"[ant-update] scraped-credits.json age: {_scraped_age_h:.1f}h", file=sys.stderr)
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

# ── Credits: continuous estimate — never wipe, never reset monthly ────────────
# Formula: remaining = scraped_remaining - spend_since_scrape_date
# This gives a CONTINUOUSLY UPDATED estimate regardless of month boundaries.
# Burn rate: 7-day rolling average for depletion forecast.

def compute_spend_since(records, scrape_date_str, provider_filter):
    """Sum spend from api-usage.jsonl entries after scrape_date."""
    total = 0.0
    for r in records:
        d = r.get("date", r.get("ts", ""))[:10]
        if d < scrape_date_str: continue
        p = r.get("provider", "openai" if "gpt" in r.get("model", "") else "anthropic")
        if p == provider_filter:
            total += float(r.get("cost_usd", r.get("estimated_cost_usd", 0.0)))
    return total

def depletion_forecast(remaining, daily_burn, provider_label):
    """Returns (depletion_date_iso, days_left, confidence) or None if burn=0."""
    if daily_burn <= 0 or remaining is None:
        return None, None, "no_burn_data"
    days_left = remaining / daily_burn
    dep_date = (date.today() + timedelta(days=days_left)).isoformat()
    confidence = "high" if daily_burn > 0.01 else "low"
    return dep_date, round(days_left), confidence

# Burn rate by provider (last 7 days)
recent_7d = [(today - timedelta(days=i)).isoformat() for i in range(7)]
burn_anthropic = sum(by_date_provider[d].get("anthropic", 0.0) for d in recent_7d) / 7
burn_openai    = sum(by_date_provider[d].get("openai",    0.0) for d in recent_7d) / 7

total_anthropic = by_provider.get("anthropic", 0.0)
total_openai    = by_provider.get("openai", 0.0)
total_cost      = total_anthropic + total_openai

if _scraped:
    _ant = _scraped.get("anthropic", {})
    _oai = _scraped.get("openai", {})
    _scrape_date = _scraped.get("scraped_at", "")[:10]
    _age_label = f"scraped {_scraped_age_h:.0f}h ago" if _scraped_age_h else "scraped"
    _confidence = "high" if _scraped_age_h and _scraped_age_h <= 48 else "estimated"

    # Continuous remaining: scraped balance minus spend since scrape
    spend_since_ant = compute_spend_since(records, _scrape_date, "anthropic")
    spend_since_oai = compute_spend_since(records, _scrape_date, "openai")
    remaining_ant = max(round((_ant.get("remaining") or 0) - spend_since_ant, 4), 0)
    remaining_oai = max(round((_oai.get("remaining") or 0) - spend_since_oai, 4), 0)

    dep_date_ant, days_ant, conf_ant = depletion_forecast(remaining_ant, burn_anthropic, "anthropic")
    dep_date_oai, days_oai, conf_oai = depletion_forecast(remaining_oai, burn_openai, "openai")

    credits_data = {
        "anthropic": {
            "remaining":            remaining_ant,
            "total":                _ant.get("total"),
            "used_since_scrape":    round(spend_since_ant, 4),
            "used_all_time":        round(total_anthropic, 4),
            "used_mtd":             round(mtd_anthropic, 4),
            "burn_per_day":         round(burn_anthropic, 4),
            "depletion_date":       dep_date_ant,
            "days_until_depleted":  days_ant,
            "expires":              _ant.get("expires"),
            "source":               f"console.anthropic.com ({_age_label}, adjusted by api-usage.jsonl)",
            "scraped_at":           _scraped.get("scraped_at"),
            "confidence":           _confidence,
            "note":                 f"Remaining = scraped balance minus api-usage.jsonl spend since {_scrape_date}. Run 'kai ant-scrape' to reset baseline.",
        },
        "openai": {
            "remaining":            remaining_oai,
            "total":                _oai.get("total"),
            "used_since_scrape":    round(spend_since_oai, 4),
            "used_all_time":        round(total_openai, 4),
            "used_mtd":             round(mtd_openai, 4),
            "burn_per_day":         round(burn_openai, 4),
            "depletion_date":       dep_date_oai,
            "days_until_depleted":  days_oai,
            "expires":              _oai.get("expires"),
            "source":               f"platform.openai.com ({_age_label}, adjusted by api-usage.jsonl)",
            "scraped_at":           _scraped.get("scraped_at"),
            "confidence":           _confidence,
            "note":                 f"Remaining = scraped balance minus api-usage.jsonl spend since {_scrape_date}.",
        }
    }
    print(f"[ant-update] Credits ({_confidence}): Anthropic ${remaining_ant:.2f} remaining (depletion: {dep_date_ant}, {days_ant}d) | OpenAI ${remaining_oai:.2f} remaining (depletion: {dep_date_oai}, {days_oai}d)", file=sys.stderr)
else:
    # True fallback: no scrape file at all — budget-based only
    dep_date_ant, days_ant, _ = depletion_forecast(MONTHLY_BUDGET_ANTHROPIC - mtd_anthropic, burn_anthropic, "anthropic")
    dep_date_oai, days_oai, _ = depletion_forecast(MONTHLY_BUDGET_OPENAI - mtd_openai, burn_openai, "openai")
    credits_data = {
        "anthropic": {
            "monthly_budget":       MONTHLY_BUDGET_ANTHROPIC,
            "used_mtd":             round(mtd_anthropic, 4),
            "used_all_time":        round(total_anthropic, 4),
            "remaining":            round(max(MONTHLY_BUDGET_ANTHROPIC - mtd_anthropic, 0), 4),
            "total":                MONTHLY_BUDGET_ANTHROPIC,
            "burn_per_day":         round(burn_anthropic, 4),
            "depletion_date":       dep_date_ant,
            "days_until_depleted":  days_ant,
            "source":               "api-usage.jsonl (budget-based — no scrape file)",
            "confidence":           "low",
            "note":                 f"No scraped-credits.json found. Run 'kai ant-scrape' from Cowork to get real balance.",
            "expires":              None
        },
        "openai": {
            "monthly_budget":       MONTHLY_BUDGET_OPENAI,
            "used_mtd":             round(mtd_openai, 4),
            "used_all_time":        round(total_openai, 4),
            "remaining":            round(max(MONTHLY_BUDGET_OPENAI - mtd_openai, 0), 4),
            "total":                MONTHLY_BUDGET_OPENAI,
            "burn_per_day":         round(burn_openai, 4),
            "depletion_date":       dep_date_oai,
            "days_until_depleted":  days_oai,
            "source":               "api-usage.jsonl (budget-based — no scrape file)",
            "confidence":           "low",
            "note":                 "Run 'kai ant-scrape' from Cowork for real balance.",
            "expires":              None
        }
    }
    print("[ant-update] WARNING: No scraped-credits.json — using budget-based fallback.", file=sys.stderr)

# ── Current-month daily history (per provider) ────────────────────────────────
# Powers the "Daily Credit Usage" stacked bar chart on HQ Ant tab.
# Shows every day from the 1st of the current month through today (zero-fill gaps).
# On month rollover (day 1): previous month is closed to monthly-YYYY-MM.json
#   before this runs, so the new month starts clean from day 1.
# Each entry: { date, anthropic, openai, total }
history = []
month_start = today.replace(day=1)
days_in_month = (today - month_start).days + 1
for i in range(days_in_month - 1, -1, -1):
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
# HARD BUDGET CAP — Ant owns enforcement per Hyo directive 2026-04-23
# Target: <$1/day total (automated + Cowork sessions combined)
# Automated scripts alone: target <$0.25/day to leave room for 1-2 sessions
DAILY_HARD_CAP_USD  = 1.00    # Hard limit — flag P0 if exceeded
DAILY_ALERT_USD     = 0.75    # Warn at 75% of cap
DAILY_CRITICAL_USD  = 0.25    # Scripts-only: if automated hits $0.25+ it crowds out sessions
PROCESS_ALERT_USD   = 0.25    # Per-process threshold

alerts = []
if today_spend >= DAILY_HARD_CAP_USD:
    alerts.append({
        "level": "CRITICAL",
        "msg":   f"BUDGET HARD CAP EXCEEDED: ${today_spend:.4f} >= ${DAILY_HARD_CAP_USD:.2f}/day. Hyo must review and reduce. Sessions suspended until resolved.",
        "ts":    datetime.now(tz_mt).isoformat()
    })
elif today_spend > DAILY_ALERT_USD:
    alerts.append({
        "level": "WARNING",
        "msg":   f"Daily API at {today_spend/DAILY_HARD_CAP_USD*100:.0f}% of cap: ${today_spend:.4f} of ${DAILY_HARD_CAP_USD:.2f}. Review if sessions ran today.",
        "ts":    datetime.now(tz_mt).isoformat()
    })
elif today_spend > DAILY_CRITICAL_USD:
    alerts.append({
        "level": "INFO",
        "msg":   f"Automated scripts at ${today_spend:.4f} (${DAILY_HARD_CAP_USD - today_spend:.4f} remaining for Cowork sessions today)",
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

# ── Totals (already computed above before credits block) ──────────────────────

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
        "lastUpdated":        datetime.now(tz_mt).isoformat(),
        "staleAfterHours":    24,
        "creditScrapedAt":    _scraped.get("scraped_at") if _scraped else None,
        "creditScrapeAgeH":   round(_scraped_age_h, 1) if _scraped_age_h else None,
        "creditScrapeStale":  (_scraped_age_h or 999) > 96,
        "note":               "ant-data.json updates nightly 23:45 MT. Credits use scraped baseline + continuous api-usage.jsonl adjustment. Run 'kai ant-scrape' weekly or when credits change."
    },
    "credit_refresh_guide": {
        "how_to_refresh": "kai ant-scrape (browser automation via Cowork session)",
        "recommended_frequency": "weekly or after any credit purchase",
        "last_scraped": _scraped.get("scraped_at") if _scraped else "never",
        "scrape_age_hours": round(_scraped_age_h, 1) if _scraped_age_h else None,
        "action_needed": (_scraped_age_h or 999) > 96
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

# ── Phase 2: Quality gate (hard block — ant-gate.py) ─────────────────────────
echo "[ant-update] Running quality gate (ant-gate.py)..."
python3 "$ROOT/bin/ant-gate.py"
GATE_STATUS=$?

if [ $GATE_STATUS -ne 0 ]; then
    echo "[ant-update] ERROR: Quality gate failed — aborting commit. Check Telegram alert." >&2
    # Write failure to log before exiting
    LOG_DIR="$ROOT/agents/ant/logs"
    LOG_FILE="$LOG_DIR/ant-$(date +%Y-%m-%d).log"
    mkdir -p "$LOG_DIR"
    echo "[ant] $(date -u +%Y-%m-%dT%H:%M:%S%z) GATE FAIL — commit aborted. See ant-gate.py output above." >> "$LOG_FILE"
    exit 1
fi

# ── Phase 3: Daily log ────────────────────────────────────────────────────────
LOG_DIR="$ROOT/agents/ant/logs"
LOG_FILE="$LOG_DIR/ant-$(date +%Y-%m-%d).log"
mkdir -p "$LOG_DIR"

if [ $GATE_STATUS -eq 0 ]; then
    GATE_LINE="PASS"
else
    GATE_LINE="FAIL"
fi

{
    echo "[ant] $(date -u +%Y-%m-%dT%H:%M:%S%z) START"
    python3 -c "
import json
with open('${ANT_FILE}') as f: d = json.load(f)
cr = d.get('credits', {})
ant = cr.get('anthropic', {})
oai = cr.get('openai', {})
hist = d.get('history', [])
max_day = max((h.get('total', 0) for h in hist), default=0)
net = d.get('expenses', {}).get('total', 0) - d.get('income', {}).get('total_monthly', 0)
print(f\"[ant] MTD Anthropic: \${ant.get('used_mtd', 0):.4f} | OpenAI: \${oai.get('used_mtd', 0):.4f}\")
print(f\"[ant] Credits: Anthropic \${ant.get('remaining')} remaining of \${ant.get('total')} ({ant.get('source','?').split('(')[0].strip()}) | OpenAI \${oai.get('remaining')} remaining of \${oai.get('total')}\")
print(f\"[ant] History: {len(hist)} days loaded, max single-day \${max_day:.4f}\")
print(f\"[ant] Monthly ledger: ${ANT_MONTHLY_FILE}\")
"
    echo "[ant] Dual-path write: OK"
    echo "[ant] Gate: $GATE_LINE"
} >> "$LOG_FILE" 2>&1

# ── Phase 4: Update ACTIVE.md ────────────────────────────────────────────────
ACTIVE_FILE="$ROOT/agents/ant/ACTIVE.md"
RUN_TS=$(date +%Y-%m-%dT%H:%M:%S%z)
NEXT_TS=$(date -v+1d +%Y-%m-%d 2>/dev/null && echo "$(date -v+1d +%Y-%m-%d)T23:45:00$(date +%z)" || date -d "tomorrow" +%Y-%m-%dT23:45:00%z 2>/dev/null || echo "tomorrow 23:45 MT")

python3 -c "
import json
with open('${ANT_FILE}') as f: d = json.load(f)
cr = d.get('credits', {})
ant = cr.get('anthropic', {})
oai = cr.get('openai', {})
net = d.get('income', {}).get('total_monthly', 0) - d.get('expenses', {}).get('total', 0)
src_ant = ant.get('source', '?').split('(')[0].strip()
src_oai = oai.get('source', '?').split('(')[0].strip()
print(f'''# Ant — Active Ledger
# Updated automatically by ant-update.sh

**Agent:** Ant (Accountant)
**Last run:** ${RUN_TS}
**Status:** $GATE_LINE
**Protocol version:** 1.2

## Credit status (as of last run)

| Provider   | Remaining | Total | Used MTD | Source |
|------------|-----------|-------|----------|--------|
| Anthropic  | \${ant.get(\"remaining\", \"?\")} | \${ant.get(\"total\", \"?\")} | \${ant.get(\"used_mtd\", 0):.4f} | {src_ant} |
| OpenAI     | \${oai.get(\"remaining\", \"?\")} | \${oai.get(\"total\", \"?\")} | \${oai.get(\"used_mtd\", 0):.4f} | {src_oai} |

## Net position (this month)

- Income: \${d.get(\"income\", {}).get(\"total_monthly\", 0):.2f}
- Expenses: \${d.get(\"expenses\", {}).get(\"total\", 0):.2f}
- **Net: \${net:.2f}**

## Open tickets

| Ticket       | Priority | Description                                          |
|--------------|----------|------------------------------------------------------|
| ANT-GAP-001  | P2       | Screen-scrape requires Cowork; needs Admin API key   |
| ANT-GAP-002  | P3       | No launchd job for monthly close (1st of month)      |
| ANT-GAP-003  | P3       | No failure alert if ant-daily fails overnight        |

## Next scheduled run

${NEXT_TS} (via com.hyo.ant-daily launchd)
''')
" > "$ACTIVE_FILE" 2>/dev/null

echo "[ant] ACTIVE.md: updated" >> "$LOG_FILE"
echo "[ant] $(date -u +%Y-%m-%dT%H:%M:%S%z) END" >> "$LOG_FILE"

# ── Phase 5: Commit and push ──────────────────────────────────────────────────
cd "$ROOT"
MONTH_TAG=$(date +%Y-%m)
git add \
    agents/sam/website/data/ant-data.json \
    website/data/ant-data.json \
    "agents/ant/ledger/monthly-${MONTH_TAG}.json" \
    agents/ant/ACTIVE.md \
    "$LOG_FILE" 2>/dev/null || true

if git diff --cached --quiet; then
    echo "[ant-update] Nothing to commit."
else
    if git commit -m "ant: daily update $(date +%Y-%m-%d)"; then
        if git push origin main; then
            echo "[ant-update] Committed and pushed."
            echo "[ant] $(date -u +%Y-%m-%dT%H:%M:%S%z) Committed and pushed." >> "$LOG_FILE"
        else
            echo "[ant-update] WARNING: git push failed — sending Telegram alert." >&2
            echo "[ant] $(date -u +%Y-%m-%dT%H:%M:%S%z) GIT PUSH FAILED — manual push required via kai exec." >> "$LOG_FILE"
            python3 -c "
import sys
sys.path.insert(0, '${ROOT}/bin')
try:
    from ant_gate import send_telegram_alert
    send_telegram_alert('ant-update.sh: git push failed on $(date +%Y-%m-%d). Run: kai exec \"cd ~/Documents/Projects/Hyo && git push origin main\"')
except Exception as e:
    import urllib.request, json, os
    # Inline fallback alert
    env_file = '${ROOT}/agents/nel/security/env'
    token = ''; chat_id = ''
    try:
        for line in open(env_file):
            k, _, v = line.strip().partition('=')
            # AETHERBOT_TELEGRAM_TOKEN = @xAetherbot (alerts). TELEGRAM_BOT_TOKEN = @Kai_11_bot (conversations).
            if k.strip() == 'AETHERBOT_TELEGRAM_TOKEN': token = v.strip()
            elif k.strip() == 'TELEGRAM_BOT_TOKEN' and not token: token = v.strip()
            if k.strip() == 'TELEGRAM_CHAT_ID': chat_id = v.strip()
    except: pass
    if token and chat_id:
        payload = json.dumps({'chat_id': chat_id, 'text': '[ANT] git push failed on $(date +%Y-%m-%d). Manual push needed.'}).encode()
        urllib.request.urlopen(urllib.request.Request(f'https://api.telegram.org/bot{token}/sendMessage', data=payload, headers={'Content-Type': 'application/json'}), timeout=10)
" 2>/dev/null || true
        fi
    else
        echo "[ant-update] WARNING: git commit failed." >&2
    fi
fi

echo "[ant-update] Done. Gate: $GATE_LINE | Log: $LOG_FILE"
