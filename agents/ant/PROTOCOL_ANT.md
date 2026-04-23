# PROTOCOL_ANT.md
# Ant — Complete Agent Execution Protocol
#
# VERSION: 1.4
# Author: Kai | Created: 2026-04-18 | Updated: 2026-04-22
# Canonical location: agents/ant/PROTOCOL_ANT.md
#
# PURPOSE: Every execution of Ant — automated or manual — follows this protocol.
# Any agent, any session, same results. No shortcuts. No interpretation.
#
# CHANGE HISTORY:
#   v1.0 (2026-04-18): Initial — credit bars, monthly ledger, report archiving, schedule
#   v1.1 (2026-04-18): Added screen-scrape workflow (Part 9), daily usage chart (Part 6 update),
#                      heredoc fix in ant-update.sh (quoted heredoc + env-var paths)
#   v1.2 (2026-04-18): MAJOR — protocol holes audit; HQ layout spec locked (Part 6);
#                      schedule table verified from real plists (Part 11); agent independence
#                      tiers documented (Part 12); known failure modes with gates (Part 13);
#                      git push rule, ACTIVE.md update, log-writing requirement, 17 holes closed
#   v1.3 (2026-04-19): ant-gate.py standalone hard-block script (bin/ant-gate.py, 5 gates,
#                      exit 1 on fail, Telegram alert); ant-update.sh Phase 2 now calls
#                      ant-gate.py instead of inline Python; git push failure sends Telegram
#                      alert; scraped-credits >24h staleness flagged in gate; ANT-GAP-003
#                      (failure alert) resolved via Telegram integration
#   v1.4 (2026-04-22): SCHEMA ENFORCEMENT — after a session rewrote ant-data.json without
#                      reading this protocol, breaking the daily credit chart (history entries
#                      missing anthropic/openai fields). Added hard schema gate. Any script
#                      or agent rewriting ant-data.json MUST read Part 10 schema first.
#                      Gate question: "Did I verify history[] has {date,anthropic,openai,total}?"
#                      NO → do not write. Credits factchecked: Anthropic $30.67 remaining,
#                      OpenAI $17.94 remaining (scraped 2026-04-18, adjusted for spend).

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
| Credit budget  | scraped-credits.json (preferred) or ANT_MONTHLY_BUDGET_* env | Daily (derived) |
| AetherBot P&L  | aether-metrics.json       | Daily (from Sam) |
| Subscriptions  | Hardcoded in ant-update.sh| Monthly review |
| Monthly net    | Computed from above       | Daily (derived) |
| Monthly ledger | agents/ant/ledger/        | Daily (snapshot), closed 1st of month |

### 1.2 What Ant does NOT track (yet)

- Stripe revenue (future: when Aurora/subscriptions launch)
- Infrastructure costs (future: when Vercel/hosting billed separately)
- Exact account credit balances without screen-scrape or Admin API key

### 1.3 Credit bar display

HQ shows two horizontal bars: Anthropic and OpenAI.

Each bar represents: **account balance remaining** (if scraped-credits.json is fresh) OR
**used of monthly budget** (fallback when scraped data is stale/missing).

**Budget fallback** = `ANT_MONTHLY_BUDGET_ANTHROPIC` / `ANT_MONTHLY_BUDGET_OPENAI` env vars.
Default values: `$40 Anthropic / $20 OpenAI` (matching current grant sizes as of 2026-04-18).

**Source always labeled** in `credits.*.source` field of ant-data.json so HQ can display
"real balance" vs "budget estimate" to Hyo. Never hide which tier is in use.

---

## PART 2 — FILE LOCATIONS (CANONICAL)

Every file Ant produces has exactly one canonical location. Never write to a different path.

### Ant's own files

| File                                     | Description                              |
|------------------------------------------|------------------------------------------|
| `agents/ant/PROTOCOL_ANT.md`            | This file (single source of truth)       |
| `agents/ant/ACTIVE.md`                  | Current run status, open tasks           |
| `agents/ant/ledger/monthly-YYYY-MM.json`| Monthly snapshot (one per month)         |
| `agents/ant/ledger/scraped-credits.json`| Real account balances (48h TTL)          |
| `agents/ant/logs/ant-YYYY-MM-DD.log`   | Daily run log                            |

### Output files (DUAL-PATH — both MUST be updated every run)

| Path                                          | Consumer          |
|-----------------------------------------------|-------------------|
| `agents/sam/website/data/ant-data.json`       | HQ via /data/     |
| `website/data/ant-data.json`                  | Vercel mirror     |

**DUAL-PATH RULE — NON-NEGOTIABLE:**
The pre-commit hook (`agents/nel/hooks/pre-commit`) blocks the commit if only one path is staged.
This is identical behavior to aether-metrics.json dual-path enforcement.

**To stage correctly:**
```bash
git add agents/sam/website/data/ant-data.json \
        website/data/ant-data.json \
        agents/ant/ledger/monthly-$(date +%Y-%m).json \
        agents/ant/ACTIVE.md
```

**If `website/hq.html` was also modified**, copy before staging:
```bash
cp agents/sam/website/hq.html website/hq.html
git add agents/sam/website/hq.html website/hq.html
```

### Monthly ledger record

```
agents/ant/ledger/monthly-2026-04.json   ← current open month
agents/ant/ledger/monthly-2026-03.json   ← closed (status: "closed")
```

Ledger files accumulate. Never delete them. They are the permanent financial record.

---

## PART 3 — EXECUTION PROTOCOL (AUTOMATED)

The nightly pipeline runs at **23:45 MT** via launchd (`com.hyo.ant-daily.plist`).
**This is 23:45, not 23:59.** The plist fires at Hour=23 Minute=45.

### Phase 1: Data collection

```bash
# ant-update.sh does all of this automatically:
bash ~/Documents/Projects/Hyo/bin/ant-update.sh
```

What happens inside:
1. Load all records from `kai/ledger/api-usage.jsonl`
2. Aggregate by provider, date, agent, model, process
3. Compute MTD spend per provider for the current calendar month
4. Check `agents/ant/ledger/scraped-credits.json` — use if `scraped_at` is within 48h
5. If scraped data is fresh: credit bars use real account balance; source labeled "console.*"
6. If scraped data is stale/missing: credit bars use budget-based fallback; source labeled "budget-based"
7. Load AetherBot P&L from `aether-metrics.json`
8. Compute net position: `income_total − fixed_expenses − api_mtd`
9. Build `history[]` array: 14 days of per-provider daily API costs (from api-usage.jsonl)
10. Write `ant-data.json` to BOTH paths (dual-path)
11. Write/update `agents/ant/ledger/monthly-YYYY-MM.json`
12. Write daily log to `agents/ant/logs/ant-YYYY-MM-DD.log`
13. Update `agents/ant/ACTIVE.md` with run timestamp and status

### Phase 2: Quality gate (ant-gate.py — HARD BLOCK)

**The quality gate is `bin/ant-gate.py` — a standalone hard-block script (v1.3).**
It is called by ant-update.sh Phase 2. On failure: exits 1, sends Telegram alert,
ant-update.sh aborts before commit. No broken data reaches HQ.

```bash
# ant-update.sh calls this automatically — manual invocation for debugging:
python3 bin/ant-gate.py
```

**5 gates (all must pass):**

| Gate | Check                                        | Failure action                        |
|------|----------------------------------------------|---------------------------------------|
| 1    | credits.anthropic.remaining and .openai.remaining not null | Telegram alert + exit 1 |
| 2    | history[] array is non-empty                 | Telegram alert + exit 1               |
| 3    | updatedAt is within last 60 minutes          | Telegram alert + exit 1               |
| 4    | Both ant-data.json paths exist, sizes match  | Telegram alert + exit 1               |
| 5    | At least one history day has non-zero values | Telegram alert + exit 1               |

If gate fails: check Telegram alert. Then re-run `bash bin/ant-update.sh`. If still
failing: file ANT-P1 ticket and check api-usage.jsonl for valid records.

### Phase 3: Commit and push

**CRITICAL: Both git commit AND git push must happen. Commit alone is NOT done.**

```bash
# In the Hyo repo on the Mini (not in Cowork sandbox):
git add agents/sam/website/data/ant-data.json \
        website/data/ant-data.json \
        agents/ant/ledger/monthly-$(date +%Y-%m).json \
        agents/ant/ACTIVE.md
git commit -m "ant: daily update $(date +%Y-%m-%d)"
git push origin main
```

**If running from Cowork sandbox:** The sandbox has a 403 proxy block on GitHub.
Use `mcp__claude-code-mini__Bash` (the Mini's Bash MCP) to run the push, NOT the Cowork Bash tool.
Or use the queue: `kai exec "cd ~/Documents/Projects/Hyo && git push origin main"`

**Push failure = P1 ticket. Do not move to the next task until push is confirmed.**

### Phase 4: ACTIVE.md update (mandatory after every run)

Update `agents/ant/ACTIVE.md` with:
```
Last run: YYYY-MM-DDT23:45:XX-06:00
Status: OK | FAIL
Credits: Anthropic $XX.XX remaining ($YY.YY used MTD) | OpenAI $XX.XX remaining ($YY.YY used MTD)
Source: scraped (Xh ago) | budget-based
Net position: $XX.XX
Next run: YYYY-MM-DDT23:45:00-06:00
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

**Note:** There is no automated launchd job for monthly close. This runs manually or via
`kai exec` on the 1st. Add `com.hyo.ant-monthly.plist` (triggers on Day=1, Hour=00, Min=05)
as a future improvement.

---

## PART 5 — REPORT ARCHIVING

Every Ant run produces a daily log at:
```
agents/ant/logs/ant-YYYY-MM-DD.log
```

**Log format (exact — do not deviate):**
```
[ant] 2026-04-18T23:45:12-0600 START
[ant] MTD Anthropic: $0.2399 | OpenAI: $0.8854
[ant] Credits: Anthropic $30.79 remaining of $40.00 (real balance) | OpenAI $18.64 remaining of $20.00 (real balance)
[ant] Net position: -$196.25 (income $24.94, expenses $221.19)
[ant] History: 14 days loaded, max single-day $0.75
[ant] Monthly ledger: agents/ant/ledger/monthly-2026-04.json
[ant] Dual-path write: OK
[ant] Gate: PASS
[ant] ACTIVE.md: updated
[ant] END
```

**If any phase fails**, the log must record which phase failed and why:
```
[ant] Gate: FAIL — history array empty
[ant] Action: re-run triggered
```

**Retention:** Logs kept indefinitely. Monthly ledgers kept indefinitely.

---

## PART 6 — HQ DISPLAY SPEC (LOCKED — DO NOT CHANGE WITHOUT BUMPING PROTOCOL VERSION)

This section is the canonical spec for the Ant tab on HQ. Any agent modifying `hq.html`
**must** follow this spec exactly. Deviations require a protocol version bump.

### Layout order (top to bottom — fixed)

1. Net Position (lead card row)
2. Credit Balances (horizontal bar section)
3. Today's API Costs (per model table)
4. Daily Credit Usage (14-day stacked bar chart)
5. Monthly Expenses Breakdown (expense table)

### Section 1: Net Position

Four stat cards in a row:
- **Net Position** — `data.net_position` — label: "Net This Month"
- **Monthly Expenses** — `data.expenses.total` — label: "Monthly Expenses"
- **AetherBot P&L** — `data.income.streams[name=AetherBot].amount` — label: "AetherBot (week of MM-DD)"
  - The weekly label must include the reset date: `"week of " + data.income.streams[0].week_of`
- **Today's API Cost** — `data.costs.today` — label: "Today's API Cost"

### Section 2: Credit Balances

Each bar is a horizontal fill. Two bars: Anthropic then OpenAI.

**Anthropic bar:**
- Fill color: `#a855f7` (purple-500)
- Fill % = `(data.credits.anthropic.used / data.credits.anthropic.total) * 100`
- Label: `$X.XX used · $X.XX left of $X.XX/mo`
- Source note: render `data.credits.anthropic.source` in small gray text below the bar
- If source contains "budget-based": prepend ⚠️ to source note

**OpenAI bar:**
- Fill color: `#06b6d4` (cyan-500)
- Fill % = `(data.credits.openai.used / data.credits.openai.total) * 100`
- Label: `$X.XX used · $X.XX left of $X.XX/mo`
- Source note: render `data.credits.openai.source` in small gray text below the bar
- If source contains "budget-based": prepend ⚠️ to source note

**DO NOT swap colors.** Purple = Anthropic, Cyan = OpenAI. This is consistent with the
chart legend in Section 4. Hard-coded. Non-negotiable.

### Section 3: Today's API Costs

Table: Model | Calls | Cost
- Source: `data.costs.by_model[]` array
- Each entry: `{ model, calls, cost }`
- If array empty: show "No API calls today"
- Footer: total cost = `data.costs.today`

### Section 4: Daily Credit Usage (14-day stacked bar chart)

**Field path:** `data.history[]` — NOT `data.costs.dailyHistory` (that field does not exist).

Each entry: `{ date: "YYYY-MM-DD", anthropic: 0.XX, openai: 0.XX, total: 0.XX }`

Chart spec:
- 14 bars (or fewer if <14 days of data)
- Each bar is stacked: bottom = Anthropic (purple `#a855f7`), top = OpenAI (cyan `#06b6d4`)
- Bar height = total/maxTotal * maxBarHeightPx
- X-axis labels: last 2 chars of date (day number, e.g., "16", "17", "18")
- Legend: ■ Anthropic  ■ OpenAI (using same hex colors)
- If `data.history` is missing or empty: render section header + "No history data yet"

**Do not render "Daily Credit Usage" from any other field.** If the field doesn't exist in the
JSON, the section shows the empty state, not an error.

### Section 5: Monthly Expenses Breakdown

Table: Category | Amount
- Fixed subscriptions (from `data.expenses.fixed[]`)
- Variable API (from `data.expenses.api_mtd`)
- Footer: total = `data.expenses.total`

### Section header style

All Ant sections use:
```javascript
function antSection(title, content) {
    return `<div class="ant-section">
        <h3 class="section-title">${title}</h3>
        ${content}
    </div>`;
}
```

Do not change the `antSection()` function signature or CSS class names.

---

## PART 7 — UPGRADE PROTOCOL

When ant-update.sh, PROTOCOL_ANT.md, or the HQ render function changes:

1. Make the change
2. Run `bash bin/ant-update.sh` and verify gate passes
3. Open HQ in browser, go to Ant tab, confirm all 5 sections render
4. Check browser console for JavaScript errors: look for SyntaxError, undefined, null
5. **If hq.html was modified**: always check for duplicate `const` declarations in `renderAnt()`
   before committing. Run: `grep -n "const incomeStreams\|const expenses\|const credits" agents/sam/website/hq.html`
6. Bump VERSION in this file header
7. Log the change in the table below

### Change log

| Version | Date       | Change |
|---------|------------|--------|
| 1.0     | 2026-04-18 | Initial — credit bars, monthly ledger, report archive, schedule |
| 1.1     | 2026-04-18 | Screen-scrape workflow, daily usage chart, heredoc fix |
| 1.2     | 2026-04-18 | Protocol holes audit, HQ layout locked, schedule table, independence tiers, 17 holes closed |

---

## PART 8 — KNOWN LIMITATIONS

1. **Screen-scrape requires Cowork session.** Credit scraping (Part 9) requires browser automation
   with a logged-in user session. It cannot run headlessly overnight without the Admin API key fix
   described in ANT-GAP-001. See Part 12 for the independence tier matrix.

2. **No subscription detection.** Claude Max ($200) and GPT Plus ($20) are hardcoded in
   ant-update.sh. If plans change, update `fixed_subscriptions` in the script manually.

3. **AetherBot P&L is weekly, not monthly.** The trading P&L resets every Monday. Monthly net
   position therefore understates total trading income in months where multiple weeks were profitable.
   Fix: accumulate weekly P&L snapshots into the monthly ledger when each week closes.

4. **No auto-alert on failure.** If ant-daily fails overnight, no notification is sent to Hyo.
   The 07:00 MT report-check (`com.hyo.report-check.plist`) should catch it via staleness check,
   but a dedicated ANT failure alert has not been wired yet. Future: add `dispatch alert` call
   in the failure branch of ant-update.sh.

5. **Monthly close is manual.** No launchd job exists for the 1st-of-month close. Must be
   triggered manually or via `kai exec`. See Part 4.

---

## PART 9 — SCREEN-SCRAPE WORKFLOW (real credit balances)

Ant uses browser automation via Cowork computer-use to scrape real credit balances from
the Anthropic and OpenAI billing consoles. This replaces budget-based estimates with
actual account balances — required for accurate bookkeeping.

### 9.1 Trigger

Run `kai ant-scrape` from a Cowork session with computer-use access. Schedule: nightly
before `com.hyo.ant-daily` (23:45 MT) — ideally around 23:30 MT so fresh values are
picked up by the daily update. **Currently manual — requires active Cowork session with a
logged-in user.** See Part 12 for the full independence tier matrix.

Automate when Anthropic Admin API key is obtained (ticket ANT-GAP-001).

### 9.2 Anthropic credits

Navigate to: `https://console.anthropic.com/settings/credits`

Capture:
- Total credit balance (USD)
- Credits used (USD)
- Credits remaining (USD)
- Expiry date of each grant
- Grant amounts and dates

**Login requirement:** The browser session must be authenticated as the Anthropic account
owner. If the console shows a login screen, the scrape cannot proceed — ant-update.sh will
fall back to budget-based tracking and log a WARNING.

### 9.3 OpenAI credits

Navigate to: `https://platform.openai.com/settings/organization/billing/credit-grants`

Capture:
- Total granted (USD)
- Remaining balance (USD)
- Grant expiry dates

### 9.4 Output format

Write to `agents/ant/ledger/scraped-credits.json`:

```json
{
  "scraped_at": "2026-04-18T23:30:00-06:00",
  "scraped_by": "computer_use_browser",
  "anthropic": {
    "remaining": 30.79,
    "total": 40.00,
    "used": 9.21,
    "expires": "2027-04-09",
    "grants": [{"amount": 20.00, "date": "2026-04-08"}, {"amount": 20.00, "date": "2026-04-08"}]
  },
  "openai": {
    "remaining": 18.64,
    "total": 20.00,
    "used": 1.36,
    "expires": "2027-04-30",
    "grants": [{"amount": 20.00, "received": "2026-03-31", "state": "Available", "expires": "2027-04-30"}]
  }
}
```

### 9.5 Freshness rule

`ant-update.sh` uses scraped values if `scraped_at` is within 48 hours of run time.
If stale or missing: logs a WARNING and falls back to budget-based tracking.
**No silent failures** — the source is always labeled in `credits.*.source` in ant-data.json.

**Staleness check logic:**
```python
from datetime import datetime, timezone, timedelta
import json, os

scraped_path = os.path.join(ROOT, "agents/ant/ledger/scraped-credits.json")
use_scraped = False
if os.path.exists(scraped_path):
    with open(scraped_path) as f:
        sc = json.load(f)
    scraped_at = datetime.fromisoformat(sc["scraped_at"])
    age_h = (datetime.now(timezone.utc) - scraped_at.astimezone(timezone.utc)).total_seconds() / 3600
    if age_h <= 48:
        use_scraped = True
    else:
        print(f"[ant] WARNING: scraped-credits.json is {age_h:.1f}h old — falling back to budget")
else:
    print("[ant] WARNING: scraped-credits.json not found — falling back to budget")
```

### 9.6 Daily credit usage chart

The `history` field in ant-data.json contains 14 days of per-provider daily API costs
from `api-usage.jsonl`. HQ renders these as stacked bars (Anthropic=purple, OpenAI=cyan)
in the "Daily Credit Usage" section of the Ant tab.

**Field path:** `data.history[]` — NOT `data.costs.dailyHistory` (that field does not exist;
using it causes a silent non-render with no JavaScript error).

Each entry: `{ date, anthropic, openai, total }` (all in USD).

---

## PART 10 — TECHNICAL NOTES

### ant-update.sh heredoc pattern

`ant-update.sh` uses a **quoted heredoc** (`<< 'PYEOF'`) to embed the Python script.
This prevents bash from expanding `${var:format}` inside Python f-strings, which
would cause `bad substitution` errors. All bash variables are exported as env vars
(`ANT_ROOT`, `ANT_USAGE_FILE`, etc.) and read in Python via `os.environ`.

**Always use `<< 'PYEOF'` (quoted). Never use `<< PYEOF` (unquoted).**
Unquoted heredoc breaks any Python f-string containing `{var:.Nf}` format specs.

Pattern:
```bash
export ANT_ROOT="$ROOT"
export ANT_USAGE_FILE="$USAGE_FILE"
# ... export all paths ...

python3 << 'PYEOF'
import os
ROOT = os.environ["ANT_ROOT"]
USAGE_FILE = os.environ["ANT_USAGE_FILE"]
# ... f-strings like f"${mtd:.4f}" are now safe
PYEOF
```

### ant-data.json schema (canonical — do not add/remove top-level keys without version bump)

```json
{
  "updatedAt": "YYYY-MM-DDTHH:MM:SS.ffffff-06:00",
  "credits": {
    "anthropic": {
      "remaining": float,
      "total": float,
      "used": float,
      "used_mtd": float,
      "expires": "YYYY-MM-DD",
      "source": "string (labeled, never null)",
      "scraped_at": "ISO timestamp or null",
      "note": "string"
    },
    "openai": { "same structure" }
  },
  "costs": {
    "today": float,
    "mtd_anthropic": float,
    "mtd_openai": float,
    "by_model": [{"model": str, "calls": int, "cost": float}]
  },
  "expenses": {
    "total": float,
    "fixed": [{"name": str, "amount": float}],
    "api_mtd": float
  },
  "income": {
    "total_monthly": float,
    "streams": [{"name": str, "amount": float, "week_of": "MM-DD or null"}]
  },
  "net_position": float,
  "history": [
    {"date": "YYYY-MM-DD", "anthropic": float, "openai": float, "total": float}
  ],
  "monthly_ledger_path": "agents/ant/ledger/monthly-YYYY-MM.json"
}
```

**`history` is at the TOP LEVEL of the JSON object, not nested under `costs`.**

**SCHEMA GATE (added v1.4 — non-negotiable):**
Before writing ant-data.json by any means (script, manual edit, session rewrite):
1. Read this schema.
2. Confirm history[] entries contain ALL FOUR fields: date, anthropic, openai, total.
3. Confirm credits.anthropic and credits.openai exist and are non-null.
4. Run ant-gate.py after writing — it checks history[] non-empty and credits non-null.
Gate question: "Does every history entry have anthropic AND openai fields?" NO → do not commit.

---

## PART 11 — SCHEDULE VERIFICATION (verified from real plist files, 2026-04-18)

This table was generated by reading every `.plist` file in the repo. Times are Mountain Time.

### Ant-specific schedules

| Label (plist)              | Time (MT)          | Path                                         |
|----------------------------|--------------------|----------------------------------------------|
| com.hyo.ant-daily          | **23:45 daily**    | agents/ant/com.hyo.ant-daily.plist           |

**Ant-daily fires at 23:45, not 23:59.** The scrape (Part 9) should ideally run by 23:30.

### Full system schedule (all plists, sorted by time)

| Time (MT)             | Label                          | Path                                                    |
|-----------------------|--------------------------------|---------------------------------------------------------|
| every 15min           | com.hyo.aether                 | agents/aether/com.hyo.aether.plist                      |
| every 15min           | com.hyo.healthcheck            | kai/launchd/com.hyo.healthcheck.plist                   |
| every 30min           | com.hyo.business-monitor       | kai/launchd/com.hyo.business-monitor.plist              |
| every 1h              | com.hyo.escalate-blocked       | kai/launchd/com.hyo.escalate-blocked.plist              |
| every 6h              | com.hyo.nel-qa                 | agents/nel/com.hyo.nel-qa.plist                         |
| 01:00                 | com.hyo.consolidation          | agents/nel/consolidation/com.hyo.consolidation.plist    |
| 01:15                 | com.hyo.memory-consolidation   | kai/memory/agent_memory/com.hyo.memory-consolidation.plist |
| 02:30                 | com.hyo.memory-compact         | kai/launchd/com.hyo.memory-compact.plist                |
| 03:00                 | com.hyo.aurora (Ra newsletter) | agents/ra/com.hyo.aurora.plist                          |
| 04:30                 | com.hyo.sam                    | agents/sam/com.hyo.sam.plist                            |
| 06:00 (Sat only)      | com.hyo.weekly-report          | kai/queue/com.hyo.weekly-report.plist                   |
| 06:05                 | com.hyo.podcast                | kai/launchd/com.hyo.podcast.plist                       |
| 07:00                 | com.hyo.report-check           | kai/queue/com.hyo.report-check.plist                    |
| 10:00                 | com.hyo.hyo-agent              | kai/launchd/com.hyo.hyo-agent.plist                     |
| 16:02                 | com.hyo.dispatch-sync          | kai/queue/com.hyo.dispatch-sync.plist                   |
| 22:00                 | com.hyo.nel-daily              | kai/queue/com.hyo.nel-daily.plist                       |
| 22:30                 | com.hyo.sam-daily              | kai/queue/com.hyo.sam-daily.plist                       |
| 22:45                 | com.hyo.aether-daily           | kai/queue/com.hyo.aether-daily.plist                    |
| 23:00                 | com.hyo.aether-analysis        | agents/aether/com.hyo.aether-analysis.plist             |
| 23:00                 | com.hyo.dex ⚠️ exit 2         | agents/dex/com.hyo.dex.plist                            |
| 23:30                 | com.hyo.simulation ⚠️ exit 1  | agents/nel/consolidation/com.hyo.simulation.plist       |
| 23:30                 | com.hyo.kai-daily              | kai/queue/com.hyo.kai-daily.plist                       |
| 23:45                 | **com.hyo.ant-daily**          | agents/ant/com.hyo.ant-daily.plist                      |
| on-demand (daemons)   | com.hyo.queue-worker           | kai/queue/com.hyo.queue-worker.plist                    |
| on-demand (daemons)   | com.hyo.bridge                 | kai/bridge/com.hyo.bridge.plist                         |
| on-demand (daemons)   | com.hyo.mcp-tunnel             | agents/sam/mcp-server/com.hyo.mcp-tunnel.plist          |
| on-demand (daemons)   | com.hyo.mcp-server             | agents/sam/mcp-server/com.hyo.mcp-server.plist          |

### Failing jobs as of 2026-04-18 (from launchctl list)

| Job                    | Exit code | Action required         |
|------------------------|-----------|-------------------------|
| com.hyo.bore-tunnel    | exit 1    | Check tunnel logs       |
| com.hyo.dex            | exit 2    | Check dex runner        |
| com.hyo.simulation     | exit 1    | Check simulation runner |

These are NOT Ant failures. Logging here for cross-reference. Open investigation tickets.

---

## PART 12 — AGENT INDEPENDENCE TIERS

This section answers: **Can an agent run Ant without Cowork computer-use? Without a human present?**

### Tier 1 — Fully autonomous (no screen required)

Everything in this tier runs headlessly via launchd at 23:45 MT.

| Capability                        | Method                                   | Independence |
|-----------------------------------|------------------------------------------|--------------|
| Read API usage by day             | Read `kai/ledger/api-usage.jsonl`        | ✅ Full      |
| Compute MTD spend per provider    | Python aggregation in ant-update.sh      | ✅ Full      |
| Build 14-day history chart data   | Aggregate jsonl by date                  | ✅ Full      |
| Read AetherBot P&L                | Read `aether-metrics.json`               | ✅ Full      |
| Compute net position              | Arithmetic from jsonl + hardcoded subs   | ✅ Full      |
| Write ant-data.json (dual-path)   | Python file write + cp                   | ✅ Full      |
| Write monthly ledger              | Python file write                        | ✅ Full      |
| Write daily log                   | Shell echo to log file                   | ✅ Full      |
| Git commit + push                 | Via queue worker (`kai exec`)            | ✅ Full      |
| Update ACTIVE.md                  | Shell echo                               | ✅ Full      |

### Tier 2 — Requires Cowork session (screen or API key)

| Capability                        | Current method            | Why blocked              | Resolution path (ANT-GAP-001) |
|-----------------------------------|---------------------------|--------------------------|-------------------------------|
| Real Anthropic credit balance     | Screen-scrape via browser | No Admin API key         | Get Anthropic Admin API key → fetch from `api.anthropic.com/v1/usage` |
| Real OpenAI credit balance        | Screen-scrape via browser | No billing API key       | Get OpenAI API key with billing scope → fetch from OpenAI billing API |

**Fallback behavior when Tier 2 is unavailable:**
- ant-update.sh detects `scraped-credits.json` is missing or stale (>48h)
- Uses budget-based tracking: `used_mtd / ANT_MONTHLY_BUDGET_ANTHROPIC`
- Labels the source field clearly: `"budget-based (scraped data unavailable)"`
- Logs WARNING to the daily log file
- HQ renders ⚠️ next to the source label
- **The entire Tier 1 pipeline still runs and produces valid output**

### What an agent can and cannot do without a screen

✅ **Can do without screen:**
- Run the full nightly update
- Produce correct ant-data.json with today's MTD costs and 14-day history
- Commit and push to GitHub
- Pass the quality gate (Gates 1-5)
- Answer "What did we spend on API this month?" accurately
- Answer "What's our net position?" accurately

⚠️ **Cannot do without screen (unless API keys obtained):**
- Know the exact remaining account credit balance (account balance, not MTD spend)
- Verify grant amounts and expiry dates
- Detect if a credit grant was added or expired since last scrape

---

## PART 13 — KNOWN FAILURE MODES AND GATES

Every failure mode from prior sessions is listed here with a gate question.
Before any Ant-related work, scan this list.

### Failure mode inventory

| ID         | Failure                                      | Gate question before proceeding                              |
|------------|----------------------------------------------|--------------------------------------------------------------|
| ANT-F-001  | Wrong field path (`costs.dailyHistory`)      | Did I verify the field path against the actual JSON schema in Part 10? |
| ANT-F-002  | Unquoted heredoc breaks Python f-strings     | Did I use `<< 'PYEOF'` (quoted) in ant-update.sh?           |
| ANT-F-003  | Duplicate `const` declaration in renderAnt() | Did I grep for duplicate const declarations before committing? |
| ANT-F-004  | DUAL-PATH gate blocks commit                 | Did I stage both `agents/sam/website/data/` AND `website/data/` paths? |
| ANT-F-005  | Git push fails from Cowork sandbox           | Am I using Mini Bash MCP or kai exec for push (not Cowork Bash)? |
| ANT-F-006  | ACTIVE.md not updated after run              | Did I update agents/ant/ACTIVE.md with run timestamp + status? |
| ANT-F-007  | No ant log written                           | Did ant-update.sh write to `agents/ant/logs/ant-YYYY-MM-DD.log`? |
| ANT-F-008  | Scraped-credits.json stale, no warning shown | Does ant-update.sh log WARNING and label source when scrape is stale? |
| ANT-F-009  | hq.html copied but website/ copy not synced  | Did I `cp agents/sam/website/hq.html website/hq.html` before staging? |
| ANT-F-010  | history[] array empty, chart blank           | Does the jsonl file contain records for the current month?   |
| ANT-F-011  | Vercel deploys from push, not from build cmd | Did I verify deployment via `get_deployment` API after push? |
| ANT-F-012  | HQ shows login screen instead of Ant tab    | Did I verify ant-data.json directly, not just via screenshot? |
| ANT-F-013  | Monthly ledger not written                   | Does the monthly-YYYY-MM.json file exist after running ant-update.sh? |
| ANT-F-014  | Default budgets too low ($10 default)        | Are ANT_MONTHLY_BUDGET_ANTHROPIC=$40 and OPENAI=$20 set or defaulted? |
| ANT-F-015  | Commit without push                          | Did I confirm push with `git log origin/main..HEAD` returning empty? |
| ANT-F-016  | hq.html JS SyntaxError crashes entire tab    | Did I open browser console and check for SyntaxError before declaring done? |
| ANT-F-017  | Tab context stale in browser MCP             | Did I call tabs_context_mcp before browser_batch to refresh context? |
| ANT-F-018  | Quality gate fails but commit still happens  | Was `python3 bin/ant-gate.py` returning exit 1? ant-update.sh must abort on non-zero. |
| ANT-F-019  | Telegram alert not sent on gate failure      | Is TELEGRAM_BOT_TOKEN in agents/nel/security/env? Check ant-gate.py can read it. |
| ANT-F-020  | git push fails silently overnight            | ant-update.sh now sends Telegram alert on push failure. Check Telegram. |

---

## PART 14 — TICKETS

Open tickets related to Ant. Keep this section current.

| Ticket ID    | Status   | Priority | Description                                                      |
|--------------|----------|----------|------------------------------------------------------------------|
| ANT-GAP-001  | OPEN     | P2       | Screen-scrape requires Cowork session; needs Admin API key for full automation |
| ANT-GAP-002  | OPEN     | P3       | No launchd job for monthly close (1st of month) — currently manual |
| ANT-GAP-003  | RESOLVED | P3→done  | Failure alert on ant-daily fail — resolved v1.3 via ant-gate.py Telegram integration |
| ANT-GAP-004  | OPEN     | P3       | No weekly P&L accumulation — detect Monday rollover, archive prior week to monthly ledger |
| ANT-GAP-005  | OPEN     | P3       | scraped-credits >24h staleness not surfaced in 07:00 report-completeness-check.sh |
| ANT-BUG-001  | RESOLVED | —        | Duplicate incomeStreams SyntaxError (fixed commit 79cae18)       |
| ANT-BUG-002  | RESOLVED | —        | Daily chart used wrong field path costs.dailyHistory (fixed commit 34e8263) |
| ANT-BUG-003  | RESOLVED | —        | Unquoted heredoc bad substitution (fixed in ant-update.sh rewrite) |
