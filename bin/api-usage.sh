#!/usr/bin/env bash
# bin/api-usage.sh — Log and report external API usage
#
# Writes to kai/ledger/api-usage.jsonl — one JSON line per call.
# Used by agents to report their API consumption so we can track daily spend.
#
# Usage:
#   bash bin/api-usage.sh log <provider> <agent> <model> <input_tokens> <output_tokens> [notes]
#   bash bin/api-usage.sh today         # show today's spend by provider
#   bash bin/api-usage.sh week          # show last 7 days
#   bash bin/api-usage.sh summary       # short morning-report line
#
# Providers: anthropic, openai, youtube, github, reddit
# Pricing table is at top of this script — update when prices change.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LEDGER="$ROOT/kai/ledger/api-usage.jsonl"
mkdir -p "$(dirname "$LEDGER")"

SUB="${1:-summary}"
shift || true

# Pricing per 1M tokens (input / output), USD. Source: provider published pricing.
# youtube, reddit, github are free tier usage and cost $0 within quota.
pricing_json='{
  "anthropic": {
    "claude-sonnet-4-6":    {"in": 3.00, "out": 15.00},
    "claude-opus-4-6":      {"in": 15.00, "out": 75.00},
    "claude-haiku-4-5":     {"in": 0.80, "out": 4.00},
    "default":              {"in": 3.00, "out": 15.00}
  },
  "openai": {
    "gpt-4o":               {"in": 2.50, "out": 10.00},
    "gpt-4o-mini":          {"in": 0.15, "out": 0.60},
    "default":              {"in": 2.50, "out": 10.00}
  },
  "youtube":                {"default": {"in": 0, "out": 0}},
  "github":                 {"default": {"in": 0, "out": 0}},
  "reddit":                 {"default": {"in": 0, "out": 0}}
}'

case "$SUB" in
  log)
    PROVIDER="${1:-?}"; AGENT="${2:-?}"; MODEL="${3:-default}"
    IN_TOKENS="${4:-0}"; OUT_TOKENS="${5:-0}"; NOTES="${6:-}"
    NOW=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
    DATE=$(TZ=America/Denver date +%Y-%m-%d)

    python3 - "$LEDGER" "$NOW" "$DATE" "$PROVIDER" "$AGENT" "$MODEL" "$IN_TOKENS" "$OUT_TOKENS" "$NOTES" "$pricing_json" <<'PYEOF'
import json, sys
ledger, now, date, provider, agent, model, tin, tout, notes, pricing_raw = sys.argv[1:11]
tin, tout = int(tin), int(tout)
pricing = json.loads(pricing_raw)
p = pricing.get(provider, {}).get(model) or pricing.get(provider, {}).get("default", {"in": 0, "out": 0})
cost = round((tin / 1_000_000.0) * p["in"] + (tout / 1_000_000.0) * p["out"], 6)

entry = {
    "ts": now,
    "date": date,
    "provider": provider,
    "agent": agent,
    "model": model,
    "input_tokens": tin,
    "output_tokens": tout,
    "cost_usd": cost,
    "notes": notes,
}
with open(ledger, "a") as f:
    f.write(json.dumps(entry) + "\n")
print(f"[api-usage] logged: {provider}/{model} {tin}+{tout} tok = ${cost:.4f}")
PYEOF
    ;;

  today|week|summary)
    if [[ ! -f "$LEDGER" ]]; then
      echo "No API usage logged yet ($LEDGER)"
      exit 0
    fi
    DAYS=1
    [[ "$SUB" == "week" ]] && DAYS=7
    [[ "$SUB" == "summary" ]] && DAYS=1

    python3 - "$LEDGER" "$DAYS" "$SUB" <<'PYEOF'
import json, sys
from datetime import date, timedelta
from collections import defaultdict

ledger_path, days, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
today = date.today()
cutoff = today - timedelta(days=days - 1)

by_provider = defaultdict(lambda: {"cost": 0.0, "calls": 0, "in_tok": 0, "out_tok": 0})
by_agent = defaultdict(lambda: {"cost": 0.0, "calls": 0})
by_date = defaultdict(float)
total_cost = 0.0
total_calls = 0

try:
    with open(ledger_path) as f:
        for line in f:
            if not line.strip():
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            try:
                d = date.fromisoformat(e.get("date", ""))
            except Exception:
                continue
            if d < cutoff:
                continue
            prov = e.get("provider", "?")
            agt = e.get("agent", "?")
            cost = float(e.get("cost_usd", 0))
            by_provider[prov]["cost"] += cost
            by_provider[prov]["calls"] += 1
            by_provider[prov]["in_tok"] += int(e.get("input_tokens", 0))
            by_provider[prov]["out_tok"] += int(e.get("output_tokens", 0))
            by_agent[agt]["cost"] += cost
            by_agent[agt]["calls"] += 1
            by_date[str(d)] += cost
            total_cost += cost
            total_calls += 1
except FileNotFoundError:
    pass

if mode == "summary":
    # One-line summary for morning report
    prov_parts = [f"{p}=${info['cost']:.2f}" for p, info in sorted(by_provider.items(), key=lambda x: -x[1]["cost"])]
    print(f"API spend today: ${total_cost:.2f} ({total_calls} calls) — " + ", ".join(prov_parts) if prov_parts else f"API spend today: $0.00")
    sys.exit(0)

label = "Today" if days == 1 else f"Last {days} days"
print(f"=== API Usage — {label} (${total_cost:.2f} total across {total_calls} calls) ===\n")

if by_provider:
    print("By provider:")
    for p, info in sorted(by_provider.items(), key=lambda x: -x[1]["cost"]):
        print(f"  {p:12s}  ${info['cost']:.4f}  ({info['calls']} calls, {info['in_tok']} in, {info['out_tok']} out)")
    print()

if by_agent:
    print("By agent:")
    for a, info in sorted(by_agent.items(), key=lambda x: -x[1]["cost"]):
        print(f"  {a:12s}  ${info['cost']:.4f}  ({info['calls']} calls)")
    print()

if days > 1 and by_date:
    print("By date:")
    for d in sorted(by_date.keys(), reverse=True):
        print(f"  {d}  ${by_date[d]:.4f}")
PYEOF
    ;;

  *)
    echo "Usage: kai api <log|today|week|summary>" >&2
    exit 1
    ;;
esac
