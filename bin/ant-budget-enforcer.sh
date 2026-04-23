#!/usr/bin/env bash
# bin/ant-budget-enforcer.sh — Ant's budget enforcement gate
#
# Hyo directive 2026-04-23: <$1/day hard limit. No exceptions.
# Ant owns finance. If over budget, Ant escalates immediately.
#
# Called by: ant-update.sh after computing today's spend
# Also called by: kai-autonomous.sh Phase 7 (health check)

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
DAILY_LIMIT=1.00

# Read today's automated spend from api-usage.jsonl
TODAY_SPEND=$(python3 -c "
import json, sys
from collections import defaultdict
records = []
try:
    with open('$ROOT/kai/ledger/api-usage.jsonl') as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line.strip()))
except: pass
today_cost = sum(float(r.get('cost_usd',0)) for r in records if r.get('date','')=='$TODAY' or r.get('ts','')[:10]=='$TODAY')
print(f'{today_cost:.4f}')
" 2>/dev/null || echo "0")

PCT=$(python3 -c "print(f'{float(\"$TODAY_SPEND\")/float(\"$DAILY_LIMIT\")*100:.0f}')" 2>/dev/null || echo "0")

echo "[ant-budget] Today: \$$TODAY_SPEND (${PCT}% of \$$DAILY_LIMIT daily limit)"

# Hard cap: open P0 if automated scripts alone exceed limit
if python3 -c "import sys; sys.exit(0 if float('$TODAY_SPEND') >= float('$DAILY_LIMIT') else 1)" 2>/dev/null; then
    echo "[ant-budget] ⛔ HARD CAP EXCEEDED — automated scripts alone hit limit"
    if [[ -f "$ROOT/bin/ticket.sh" ]]; then
        HYO_ROOT="$ROOT" bash "$ROOT/bin/ticket.sh" create \
            --agent "ant" \
            --title "BUDGET HARD CAP: automated API spend \$$TODAY_SPEND >= \$$DAILY_LIMIT/day limit on $TODAY" \
            --priority "P0" --type "budget" --created-by "ant-budget-enforcer" 2>/dev/null || true
    fi
    # Log to Hyo inbox
    python3 - "$ROOT/kai/ledger/hyo-inbox.jsonl" "$NOW_MT" "$TODAY_SPEND" "$DAILY_LIMIT" << 'PYEOF'
import json, sys
path, ts, spend, limit = sys.argv[1:5]
entry = {"ts": ts, "from": "ant-budget-enforcer", "status": "unread",
         "subject": f"BUDGET ALERT P0: ${spend}/day (limit ${limit})",
         "body": f"Automated API spend ${spend} has reached the ${limit}/day hard cap. Review and reduce immediately. Ant owns this — no exceptions."}
with open(path, 'a') as f:
    f.write(json.dumps(entry) + '\n')
print(f"[ant-budget] P0 escalation filed to Hyo inbox")
PYEOF
    exit 1
elif python3 -c "import sys; sys.exit(0 if float('$TODAY_SPEND') >= 0.75 else 1)" 2>/dev/null; then
    echo "[ant-budget] ⚠ Warning: ${PCT}% of daily limit — sessions today will push over \$$DAILY_LIMIT"
fi

exit 0
