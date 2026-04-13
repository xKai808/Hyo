# v255 BUILD SPEC — DRAFT (DEFERRED until v254 verified live)
Created: 2026-04-10 18:20 MDT by Kai
Status: **DRAFT — DO NOT BUILD UNTIL v254 IS CONFIRMED RUNNING ON MINI**

## Why this is a draft, not a build

Per playbook step 10, I am supposed to immediately build code from a build
spec when one is warranted. I am not building today because the prerequisite
is broken: today's log proves v254 is not actually running on the Mini
(0 OB_FORMAT_DIAG, 0 HARVEST BLOCKED, 0 TIME_BDI_LOW across 1891 lines).
Writing v255 code on top of an unknown binary risks producing a deploy that
silently lands on v253 source, multiplying the divergence we're trying to
fix. Land v254 first; then convert this draft into a real spec.

## Problem statement (multi-day evidenced)

| Date | Claimed P&L | Real Δ balance | Gap |
|------|-------------|----------------|-----|
| 4/8  | TC P&L +$7.55 | balance -$11.33 | -$18.88 |
| 4/9  | TC P&L (incl post-v254) | balance reconciliation incomplete | ~-$18.88 carry |
| 4/10 | +$28.91 | +$2.95 | **-$25.96** |

Two consecutive days of widening gap. Single direct observation today
(POS WARNING line at 03:28:03, T2 trade): `API 0 local 14`. Local position
book asserts 14 contracts; Kalshi API reports zero. Bot logs settlement
P&L from local book regardless. Other 4-5 trades show identical "claim
without credit" pattern but emit no warning, because POS WARNING fires
only on stop-attempt code paths.

## Root cause hypothesis

The bot maintains a local `positions[ticker]` dict that is incremented at
order-submit time, not at fill-confirm time. Kalshi orders into thin
order books at extreme prices (0.84 NO, 0.88 NO, 0.67 NO) get partial or
zero fills. Local book stays at full requested size. At settlement, the
bot computes P&L from local book × payout, producing fictional wins.

## Required fixes (P0)

1. **Fill-confirmation discipline**
   - After every order submission, poll the Kalshi order/position endpoint
     until either (a) the order returns a confirmed fill quantity, or
     (b) a timeout (e.g. 10s) elapses.
   - Update `positions[ticker]` to the *confirmed* fill quantity, not the
     requested quantity.
   - If timeout: log `FILL UNCONFIRMED | ticker | requested Nc | confirmed
     0c` and treat the position as not-held.

2. **POS WARNING on every settle, not just stops**
   - At every TICKER CLOSE, before computing settlement P&L, query
     Kalshi for the actual position size on that ticker.
   - If `api_size != local_size`, emit `POS RECONCILE FAIL | ticker |
     api Nc | local Mc` and use api_size for the P&L calculation.
   - Add `POS RECONCILE FAIL` to the analysis grep set so future deep
     analyses see all divergences, not just stop-side ones.

3. **Hard fail-safe**
   - If `api_size == 0 && local_size > 0`: do NOT emit a settlement P&L
     line. Instead emit `SETTLE SKIPPED | reason=phantom_position |
     local Nc | api 0c`. Cumulative P&L tracker should NOT add this trade.
   - This prevents future deep analyses from inheriting hallucinated P&L
     into running totals.

4. **Optional: degrade size on thin books**
   - At BUY SNAPSHOT time, if `BDI < 200`, halve requested contract size.
     The phantom-fill failure mode correlates with thin-book entries
     (T2 BDI 355 — high — but T5 BDI 164, T6 BDI 230 are mid, and the
     largest losses-without-credit look concentrated where order size
     >= 14c). Need more data to validate; defer to v256.

## Files to modify (estimate, against v254 source)

- `bot.py` — `submit_order()`, `update_positions()`, `settle_ticker()`
- `bot.py` — add `query_kalshi_position(ticker_id)` helper if not present
- `bot.py` — log line constants for POS RECONCILE FAIL, SETTLE SKIPPED,
  FILL UNCONFIRMED

## Testing plan

Pre-deploy:
- python3 -m py_compile bot.py
- diff against v254 to confirm only the targeted code paths changed

Post-deploy verification (in first 2 hours of live trading):
- tail log for POS RECONCILE FAIL, SETTLE SKIPPED, FILL UNCONFIRMED
- compute claimed-vs-real gap on the first 2 closes; should be ≤$0.50
- if gap > $5 within 2 hours: ROLLBACK immediately

## Effort

~2-4 hours to implement and test against v254 source. Cannot proceed until
v254 source is the actual running binary on the Mini.

## Impact (projected)

- Eliminates hallucinated P&L → analyses become trustworthy again
- Removes the structural source of -$18 to -$26 / day in gap
- Side benefit: surfaces real strategy P&L so PAQ_EARLY_AGG dominance
  can be re-evaluated honestly (it may turn out to be a *losing* strategy
  once phantom fills are stripped out)
- Real upside: unknown, but capturing $10-20/day of currently-hidden
  reality is the difference between break-even and target

## Action items before this becomes a real build

- [ ] Verify v254 is actually the running binary on Mini
- [ ] Re-deploy v254 if needed, confirm OB_FORMAT_DIAG fires
- [ ] Convert this DRAFT to v255_Build_Spec.md and start implementation
- [ ] GPT cross-check this spec for missed edge cases before coding
