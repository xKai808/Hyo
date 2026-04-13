# v255 BUILD SPEC — Phantom Position Reconciliation
Version: 1.0 (promoted from DRAFT 2026-04-10 23:40 MDT)
Status: **READY FOR OPERATOR REVIEW (Sun 4/12 afternoon). MONDAY 4/13 REOPEN GATED ON APPROVAL.**
Target binary: `/Users/kai/bot.py` on the Mac Mini (live path per `project_bot_binary_path.md`)
Baseline: v254 (confirmed running 2026-04-10 23:02 MDT via live log fingerprints — yes_dollars=13, POS WARNING=2, API 0 local=2)

---

## 0. Why this spec was promoted from DRAFT

The 2026-04-10 DRAFT was blocked on "verify v254 is actually running" because Deep Analysis at 18:18 saw zero `OB_FORMAT_DIAG / HARVEST BLOCKED / TIME_BDI_LOW` across 1891 log lines and concluded v254 wasn't running. Probe 3.2 in the 23:02 simulation retracted that verdict — four v254 symbols were wired-but-not-triggered (window conditions not met today), but three v254 features (yes_dollars, POS WARNING, `API 0 local`) fired live in the same log. The prerequisite is now satisfied. This spec builds on top of v254.

## 1. Problem statement — evidence trail

Three consecutive days of structural gap between claimed P&L and real balance change:

| Date | Claimed P&L (TC sum) | Real Δ balance | Gap | Trend |
|------|----------------------|----------------|-----|-------|
| 4/8  | +$7.55                | -$11.33        | -$18.88 | baseline |
| 4/9  | incomplete reconciliation (3-pass analysis, post-v254 deploy) | ~carried | ~-$18.88 | stable |
| 4/10 | +$30.78 (12 closes — 10 native + 2 carryover) | +$5.65 (84.60 → 90.25) | **-$25.13** | widening |

Probe 3.4 in tonight's simulation flagged this as **P0 — gap widening at ~$6/day**. At the current trajectory, Monday re-open without a fix lands the gap at -$31 by Tuesday and -$37 by Wednesday.

**Single direct observation**, 2026-04-10 03:28:03 log line:
`POS WARNING | T2 PAQ_EARLY_AGG | API 0 local 14 | path=stop_check`

A second POS WARNING fired 19:58:24 (`API 0 local 5` on T9 PAQ0_COLLAPSE) — same code path, same symptom. Both are on stop-attempt code paths. Every non-stop settlement goes unchecked.

## 2. Root cause

The bot maintains `positions[ticker]` as a local dict. Entries are incremented **at order submission** time, not at **fill confirmation** time. Kalshi orders posted into thin order books at extreme prices get partial or zero fills, but the local book records full requested size. At TICKER CLOSE, settlement P&L is computed from `local_contracts * payout`, which produces fictional wins when Kalshi held zero or a fraction of the claimed position.

`POS WARNING` only fires on the stop-check code path (in `check_stops()` before a stop market order is sent). Every other exit — natural expiry, TICKER CLOSE settlement, harvest — skips the API position read. This is why we observed the smoking gun twice but suspect 6–8 other silent occurrences every day.

## 3. Fixes (P0, all required)

### 3.1 Fill-confirmation discipline

After every successful `submit_order()` response:
```
poll_interval = 1.0s
timeout = 10.0s
elapsed = 0
confirmed_fill = None
while elapsed < timeout:
    order = kalshi.get_order(order_id)
    if order.status in ("filled", "canceled", "rejected"):
        confirmed_fill = order.filled_quantity  # 0 if canceled/rejected
        break
    sleep(poll_interval)
    elapsed += poll_interval
if confirmed_fill is None:
    log("FILL UNCONFIRMED | {ticker} | requested {req}c | confirmed 0c | timeout")
    confirmed_fill = 0
positions[ticker] += confirmed_fill   # NOT req
log("FILL CONFIRMED | {ticker} | requested {req}c | confirmed {confirmed_fill}c")
```

**Important:** this replaces the current line that does `positions[ticker] += req` at submit time. Must not double-increment.

### 3.2 Per-settle position reconciliation

At every TICKER CLOSE (whether from stop, expiry, or harvest):
```
api_size = kalshi.get_position(ticker_id)
local_size = positions.get(ticker_id, 0)
if api_size != local_size:
    log("POS RECONCILE FAIL | {ticker} | api {api_size}c | local {local_size}c | path={path}")
    effective_size = api_size   # trust API over local
else:
    effective_size = local_size
settlement_pnl = effective_size * payout_per_contract
```

### 3.3 Hard fail-safe on phantom-only positions

```
if api_size == 0 and local_size > 0:
    log("SETTLE SKIPPED | reason=phantom_position | {ticker} | local {local_size}c | api 0c")
    # Do NOT emit a TICKER CLOSE line with P&L for this trade.
    # Do NOT increment cumulative P&L.
    positions[ticker] = 0   # clean up
    return
```

**Why this matters for the analysis pipeline:** Deep Analysis reads `TICKER CLOSE` lines to compute claimed P&L. If v255 suppresses TICKER CLOSE on phantom trades, claimed P&L will immediately drop toward real P&L and the gap will narrow on its own without any fake corrections.

### 3.4 New log fingerprints to add to the grep set

Add to `playbook.md` Step 2 "Full Log Extraction" grep list:
- `POS RECONCILE FAIL`
- `SETTLE SKIPPED`
- `FILL CONFIRMED`
- `FILL UNCONFIRMED`

And to the `raw_extract_YYYY-MM-DD.txt` output.

## 4. Fixes deferred to v256 (NOT P0)

- **Thin-book size degradation.** At BUY SNAPSHOT time, if `BDI < 200`, halve contract size. Hypothesis is that fill failures correlate with thin-book entries, but today's data has mixed evidence (T2 BDI 355 is high but still had the smoking gun; T5/T6 are mid-BDI). Let v255's reconciliation logs collect clean signal first, then build v256.
- **Harvest-below-entry interaction.** v254's harvest gate checks `best_bid >= anchor - 0.02` before selling. It does NOT check API position size. If the bot tries to harvest a phantom 14c position and gets `api_size=0`, we need the same `SETTLE SKIPPED` path from 3.3 to apply. Covered by 3.2 (harvest is a close path) but worth an integration test.

## 5. Files to modify (against v254 source)

- `bot.py` → `submit_order()` — add fill-confirmation polling loop per 3.1
- `bot.py` → `update_positions()` — remove eager increment, rely on confirmed quantity only
- `bot.py` → `settle_ticker()` (and `check_stops()`, `harvest()`) — add API position read + reconcile per 3.2, phantom fail-safe per 3.3
- `bot.py` → ensure `kalshi.get_position(ticker_id)` and `kalshi.get_order(order_id)` helpers exist; if not, add them
- `bot.py` → new log line format constants for `FILL CONFIRMED`, `FILL UNCONFIRMED`, `POS RECONCILE FAIL`, `SETTLE SKIPPED`

Approximate diff size: 60–120 lines changed, 1 file touched.

## 6. Testing plan

### Pre-deploy (on Mini, before `pkill`)
```bash
cd ~/
python3 -m py_compile bot.py                           # syntax
diff -u bot.py bot.py.v254.bak | head -200             # scope check
grep -cE "FILL CONFIRMED|POS RECONCILE FAIL|SETTLE SKIPPED|FILL UNCONFIRMED" bot.py
# expect: 4 (one per log constant)
```

### Deploy
```bash
cp ~/bot.py ~/bot.py.v254.bak
# edit ~/bot.py in place (operator or cowork bridge)
pkill -f bot.py
sleep 2
nohup /opt/homebrew/bin/python3 ~/bot.py >> ~/bot.log 2>&1 & disown
tail -f ~/Documents/Projects/AetherBot/Logs/AetherBot_$(date +%F).txt
```

### Post-deploy verification — first 2 hours of live trading
- Within the first BUY: look for `FILL CONFIRMED` line matching requested and actual
- Within the first 30 min: at least one `POS RECONCILE FAIL` or zero divergences (both are acceptable — we just need to see the reconcile path executing)
- After the first 2 TICKER CLOSEs: compute `sum(TC claimed P&L)` vs `(SETTLE RECHECK new balance - old balance)` — gap should be ≤ $0.50

### Rollback triggers — any of these → immediate rollback to v254
- Gap > $5 within first 2 hours
- Any `SETTLE SKIPPED` rate > 50% of TICKER CLOSE rate (means phantom rate is catastrophic — investigate before continuing)
- Bot crashes on the fill-confirmation poll (Kalshi SDK version mismatch)
- Log volume spikes > 3× normal (poll loop stuck)

Rollback command:
```bash
pkill -f bot.py; sleep 2
cp ~/bot.py.v254.bak ~/bot.py
nohup /opt/homebrew/bin/python3 ~/bot.py >> ~/bot.log 2>&1 & disown
```

## 7. Effort and timeline

- **Implementation:** 2–4 hours (operator-directed Cowork run, or manual on Mini)
- **Testing:** 2 hours of live trading for verification (cannot compress)
- **Total wall-clock from approval to verified-live:** ~6 hours
- **Recommended schedule:** Sun 4/12 afternoon review → Sun evening implementation → Mon 4/13 09:00 MTN deploy → Mon 11:00 MTN verification complete → continue or rollback

## 8. Projected impact

- Eliminates hallucinated P&L in the log → analyses become trustworthy again
- Removes the structural source of -$18 to -$26 / day in the gap
- Side benefit: real strategy-family P&L surfaces. PAQ_EARLY_AGG currently looks dominant at +$20.93/day claimed — if phantom fills are stripped out, it may reveal as a losing strategy and trigger a larger v256 strategy-mix rebuild. Either answer is valuable.
- Real upside: unknown. The hidden gap is worth $10–20/day recovered. That is the difference between current burn and break-even.

## 9. Cross-checks to run before approval

- [ ] GPT fact-check this spec on Mini: `python3 ~/Documents/Projects/AetherBot/Kai\ analysis/gpt_factcheck.py --spec v255`
- [ ] Confirm v254 source file matches running binary: `shasum ~/bot.py ~/Documents/Projects/AetherBot/bot.py.v254` (both should match)
- [ ] Confirm Kalshi SDK exposes `get_position(ticker_id)` and `get_order(order_id)` on the installed version
- [ ] Confirm fill-polling does not blow through API rate limits at expected order volume (6 orders × 10 polls × 2s worst case = 120 reads / session — well under limit)

## 10. Memory updates after deploy

On successful verification:
- Update `project_aetherbot.md` to v255
- Update `project_aetherbot_phantom_positions.md` to "PATCHED IN v255, verify via POS RECONCILE FAIL count drop"
- Close Issue #11 in `session_brief.md` once 2 consecutive days show gap ≤ $2

---

*This spec is a living document. Revise during Sunday review. If the operator adds or removes requirements, bump to v1.1 and log the change below.*

## Revision log

| Date | Version | Change | Reason |
|------|---------|--------|--------|
| 2026-04-10 18:20 | DRAFT | Initial draft written during Deep Analysis | Smoking gun at 03:28:03 observed |
| 2026-04-10 23:40 | 1.0 | Promoted from DRAFT, v254 prerequisite cleared, added second POS WARNING, expanded test plan with paste commands and rollback triggers, added fingerprint list for analysis grep set | Simulation probe 3.2 confirmed v254 is live; probe 3.4 escalated gap trend to P0 |
