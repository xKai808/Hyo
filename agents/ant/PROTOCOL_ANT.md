# PROTOCOL_ANT.md
# Ant — Complete Agent Execution Protocol
#
# VERSION: 1.0
# Author: Kai | Created: 2026-04-18
# Canonical location: agents/ant/PROTOCOL_ANT.md
#
# PURPOSE: Every execution of Ant — automated or manual — follows this protocol.
# Any agent, any session, same results. No shortcuts. No interpretation.
#
# CHANGE HISTORY:
#   v1.0 (2026-04-18): Initial — credit bars, monthly ledger, report archiving, schedule

---

## PART 0 — WHO IS ANT

**Ant** is the Accountant agent for hyo.world. Ant tracks where every dollar goes and where
every dollar comes from. Ant is not a reporting agent — Ant is the financial source of truth.

**Hyo checks Ant when asking:**
- "What did we spend on API this month?"
- "How much credit do we have left?"
- "Are we profitable this month?"
- "What's our net position?"

**Ant answers these questions accurately, automatically, and with a consistent format every time.**

---

## PART 1 — ANT'S RESPONSIBILITIES

### 1.1 What Ant tracks (always)

| Dimension       | Source                    | Update cadence |
|----------------|---------------------------|----------------|
| API spend MTD  | kai/ledger/api-usage.jsonl| Daily (23:45 MT) |
| Credit budget  | ANT_MONTHLY_BUDGET_* env  | Daily (derived) |
| AetherBot P&L  | aether-metrics.json       | Daily (from Sam) |
| Subscriptions  | Hardcoded in ant-update.sh| Monthly review |
| Monthly net    | Computed from above       | Daily (derived) |
| Monthly ledger | agents/ant/ledger/        | Daily (snapshot), closed 1st of month |

### 1.2 What Ant does NOT track (yet)

- Stripe revenue (future: when Aurora/subscriptions launch)
- Infrastructure costs (future: when Vercel/hosting billed separately)
- Exact account credit balances (requires admin API key; Ant uses budget-based tracking)

### 1.3 Credit bar display

HQ shows two horizontal bars: Anthropic and OpenAI.

Each bar represents: **used of monthly budget**.

**Budget** = `ANT_MONTHLY_BUDGET_ANTHROPIC` / `ANT_MONTHLY_BUDGET_OPENAI` env vars (default $10/month each).
**Used** = MTD spend from `kai/ledger/api-usage.jsonl` for the current calendar month.
**Remaining** = Budget − Used.

This is budget-based tracking, not account-balance tracking. The note field in the JSON explains
the distinction. To switch to account-balance tracking: add the Anthropic admin API key and update
ant-update.sh to fetch from `api.anthropic.com/v1/usage`.

---

## PART 2 — FILE LOCATIONS (CANONICAL)

Every file Ant produces has exactly one canonical location. Never write to a different path.

### Ant's own files

| File                                     | Description                              |
|------------------------------------------|------------------------------------------|
| `agents/ant/PROTOCOL_ANT.md`            | This file (single source of truth)       |
| `agents/ant/ACTIVE.md`                  | Current run status, open tasks           |
| `agents/ant/ledger/monthly-YYYY-MM.json`| Monthly snapshot (one per month)         |
| `agents/ant/logs/ant-YYYY-MM-DD.log`   | Daily run log                            |

### Output files (DUAL-PATH — both must be updated)

| Path                                          | Consumer          |
|-----------------------------------------------|-------------------|
| `agents/sam/website/data/ant-data.json`       | HQ via /data/     |
| `website/data/ant-data.json`                  | Vercel mirror     |

**DUAL-PATH RULE:** The pre-commit hook blocks if only one path is staged. Always stage both.
This is the same rule as aether-metrics.json — non-negotiable.

### Monthly ledger record

```
agents/ant/ledger/monthly-2026-04.json   ← current open month
agents/ant/ledger/monthly-2026-03.json   ← closed (status: "closed")
```

Ledger files accumulate. Never delete them. They are the permanent financial record.

---

## PART 3 — EXECUTION PROTOCOL (AUTOMATED)

The nightly pipeline runs at **23:45 MT** via launchd (`com.hyo.ant.daily.plist`).

### Phase 1: Data collection

```bash
# ant-update.sh does all of this automatically:
bash ~/Documents/Projects/Hyo/bin/ant-update.sh
```

What happens inside:
1. Load all records from `kai/ledger/api-usage.jsonl`
2. Aggregate by provider, date, agent, model, process
3. Compute MTD spend per provider for the current calendar month
4. Derive credit bars: `used_mtd / monthly_budget`
5. Load AetherBot P&L from `aether-metrics.json`
6. Compute net position: `income_total − fixed_expenses − api_mtd`
7. Write `ant-data.json` to BOTH paths (dual-path)
8. Write/update `agents/ant/ledger/monthly-YYYY-MM.json`

### Phase 2: Quality gate

After ant-update.sh runs, verify:

```python
import json
with open("agents/sam/website/data/ant-data.json") as f:
    d = json.load(f)

# Gate 1: credits populated (not null)
assert d['credits']['anthropic']['remaining'] is not None, "FAIL: Anthropic credits null"
assert d['credits']['openai']['remaining'] is not None, "FAIL: OpenAI credits null"

# Gate 2: monthly ledger written
import os
from datetime import date
month = date.today().strftime("%Y-%m")
assert os.path.exists(f"agents/ant/ledger/monthly-{month}.json"), "FAIL: monthly ledger missing"

# Gate 3: staleness < 25h
from datetime import datetime, timezone, timedelta
updated = datetime.fromisoformat(d['updatedAt'])
age_h = (datetime.now(timezone.utc) - updated.astimezone(timezone.utc)).total_seconds() / 3600
assert age_h < 25, f"FAIL: ant-data.json is {age_h:.1f}h old"

print("ALL GATES PASS")
```

If any gate fails: re-run `bash bin/ant-update.sh`. If still failing: file ANT-P1 ticket.

### Phase 3: Commit and push

```bash
git add agents/sam/website/data/ant-data.json \
        website/data/ant-data.json \
        agents/ant/ledger/monthly-$(date +%Y-%m).json \
        agents/ant/ACTIVE.md
git commit -m "ant: daily update $(date +%Y-%m-%d)"
git push origin main
```

---

## PART 4 — MONTHLY CLOSE PROTOCOL

On the 1st of each month, before running the daily update, close the previous month's ledger:

```bash
PREV_MONTH=$(date -d "last month" +%Y-%m 2>/dev/null || date -v-1m +%Y-%m)
LEDGER="agents/ant/ledger/monthly-${PREV_MONTH}.json"

python3 -c "
import json
with open('$LEDGER') as f: d = json.load(f)
d['status'] = 'closed'
d['closed_at'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
with open('$LEDGER', 'w') as f: json.dump(d, f, indent=2)
print(f'Closed {LEDGER}')
"
```

Then run the normal daily update to open the new month's ledger.

---

## PART 5 — REPORT ARCHIVING

Every Ant run produces a daily log at:
```
agents/ant/logs/ant-YYYY-MM-DD.log
```

**Log format:**
```
[ant] 2026-04-18T23:45:12-0600 START
[ant] MTD Anthropic: $0.2399 | OpenAI: $0.8854
[ant] Credits: Anthropic $9.7601 remaining of $10.00 | OpenAI $9.1146 remaining of $10.00
[ant] Net position: -$196.25 (income $24.94, expenses $221.13)
[ant] Monthly ledger: agents/ant/ledger/monthly-2026-04.json
[ant] Dual-path write: OK
[ant] Gate: PASS
[ant] END
```

**Retention:** Logs kept indefinitely. Monthly ledgers kept indefinitely.
**Archive location:** `agents/ant/logs/` (logs), `agents/ant/ledger/` (monthly records)
**Any agent that needs financial data reads from `agents/sam/website/data/ant-data.json`.**
**Any agent that needs historical data reads from `agents/ant/ledger/monthly-YYYY-MM.json`.**

---

## PART 6 — HQ DISPLAY SPEC

Ant's section on HQ (`/` → Ant tab) must show:

### Section 1: Net Position (lead)
- Net position (income − all expenses)
- Monthly expenses total
- AetherBot P&L (weekly reset — label must say "week of MM-DD")
- Today's API cost

### Section 2: Credit Balances (horizontal bars)
Each bar = provider, horizontal fill = used/total, labels = used / remaining / total

```
Anthropic ████░░░░░░░░░░░░░░░░ $0.24 used · $9.76 left of $10.00/mo
OpenAI    ████████░░░░░░░░░░░░ $0.89 used · $9.11 left of $10.00/mo
```

### Section 3: Today's API Costs (per model)

### Section 4: 14-Day Cost History (bar chart)

### Section 5: Monthly Expenses Breakdown

---

## PART 7 — UPGRADE PROTOCOL

When ant-update.sh, PROTOCOL_ANT.md, or the HQ render function changes:

1. Make the change
2. Run `bash bin/ant-update.sh` and verify gate passes
3. Open HQ in browser, go to Ant tab, confirm bars render
4. Bump VERSION in this file header
5. Log the change in this section:

### Change log

| Version | Date       | Change |
|---------|------------|--------|
| 1.0     | 2026-04-18 | Initial — credit bars, monthly ledger, report archive, schedule |

---

## PART 8 — KNOWN LIMITATIONS

1. **Budget-based credits, not account-balance.** The credit bars show spend vs. monthly budget,
   not the actual account credit balance. To fix: add Anthropic admin API key + OpenAI billing key
   to `~/security/hyo.env` and update ant-update.sh to fetch real balances.

2. **No subscription detection.** Claude Max ($200) and GPT Plus ($20) are hardcoded in
   ant-update.sh. If plans change, update `fixed_subscriptions` in the script manually.

3. **AetherBot P&L is weekly, not monthly.** The trading P&L resets every Monday. Monthly net
   position therefore understates total trading income in months where multiple weeks were profitable.
   Fix: accumulate weekly P&L snapshots into the monthly ledger when each week closes.
