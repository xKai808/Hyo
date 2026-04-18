# Aether Data Verification Gate
# SE-016-001 — created after dailyPnl all-zeros + phantom -$884 loss reached HQ
# Every metrics publish MUST answer ALL questions. Any NO = block publish, open P1 ticket.

## Pre-Publish Gate (run before every HQ push)

Ask these questions in order. Stop at the first NO and open a P1 ticket.

---

### Q1. Starting Balance Gate
> Is `startingBalance` sourced from a real AetherBot log file — NOT hardcoded, NOT null, NOT zero?

- YES → continue to Q2
- NO → **BLOCK. Open P1. Fix startingBalance from first AetherBot log of the week before publishing.**
- Check: `startingBalance != 1000.0 AND startingBalance > 0 AND startingBalance is not null`

---

### Q2. Balance Continuity Gate
> Does `startingBalance` + the sum of all daily PnL values equal `currentBalance` within $0.10?

- Compute: `chain = startingBalance + sum(day.pnl for all days up to today)`
- YES (|chain − currentBalance| ≤ 0.10) → continue to Q3
- NO → **BLOCK. Open P1. Balance chain is broken — re-read all AetherBot logs for the week.**

---

### Q3. Daily PnL Non-Zero Gate
> For every day where an AetherBot log file exists: is `balance > 0` AND is `pnl ≠ 0`?

- YES → continue to Q4
- NO (any day has `trades > 0` but `pnl == 0 AND balance == 0`) → **BLOCK. Open P1. dailyPnl was never backfilled — backfill now from logs before publishing.**

---

### Q4. Strategy PnL Sanity Gate
> Is the sum of individual strategy PnLs within 20% of total week PnL?

- Compute: `strat_sum = sum(s.pnl for all strategies)`
- YES, or week PnL < $1 (noise range) → continue to Q5
- LARGE DIVERGENCE (>20% AND |week_pnl| > $5) → **WARN in log. Do not block. Open P2 ticket for Kai review.**
- Note: strategy sum may differ from total because balance math captures premium collection + expiries that TICKER CLOSE misses

---

### Q5. Balance Source Gate
> Was `currentBalance` read from an AetherBot log file dated today or yesterday?

- YES → continue to Q6
- NO (no recent log found, using stale carry-forward) → **WARN. Log that balance is stale. Add `dataSource: stale` flag. Do not block, but open P2.**

---

### Q6. Phantom Loss Gate
> Is the absolute PnL per trade within a plausible range ($0–$50 per trade)?

- Compute: `pnl_per_trade = |week_pnl| / max(total_trades, 1)`
- YES (pnl_per_trade ≤ $50) → **ALL GATES PASS — publish**
- NO (pnl_per_trade > $50) → **BLOCK. Open P1. This signals data corruption — likely wrong startingBalance or balance read from wrong field.**

---

## Enforcement

This gate runs inside `extract_aether_metrics_from_logs()` in `aether.sh`, immediately before the HQ API push.

**On any BLOCK:**
1. `log "GATE FAIL: [Q#] [reason]"`
2. `dispatch flag aether P1 "data gate blocked: [Q#] [reason]"`
3. Do NOT push to HQ API
4. Write `"dataGateStatus": "BLOCKED"` to metrics JSON

**On all PASS:**
1. `log "GATE PASS: all 6 data verification gates passed"`
2. Write `"dataGateStatus": "PASS"` and `"dataGateTimestamp"` to metrics JSON
3. Proceed with HQ push

---

## Error-to-Gate Traceability

| What went wrong | Which gate catches it |
|---|---|
| `startingBalance: 1000` hardcoded on reinit | Q1: Starting Balance |
| `dailyPnl` all zeros | Q3: Daily PnL Non-Zero |
| phantom -$884 loss displayed on HQ | Q1 + Q2 + Q6 |
| balance chain broken mid-week | Q2: Continuity |
| stale balance from previous cycle | Q5: Balance Source |
| strategy sum diverges from total | Q4: Strategy Sanity |

---

## Last Updated
2026-04-17 — SE-016-001
