# Aether Priorities

Agent: aether.hyo  
Updated: 2026-04-13 (post-migration, comprehensive digest)  
Status: RECOVERY MODE (phantom position crisis, halt recommended until v255)

---

## BLOCKING PRIORITY (P0 — Do not resume trading without these)

1. **Halt AetherBot until v255 reconciliation patch deployed and validated**
   - Current issue: Phantom positions causing claimed P&L ≠ real balance change
   - Gap on Apr 10: -$25.96 (claimed +$28.91, actual +$2.95)
   - Root cause: POS WARNING shows `API 0 local 14` — position never filled but logged as win
   - Recommendation: Let bot idle through weekend (already in place). Do NOT restart Monday without fix.
   - Timeline: v255 build + test on real logs, Kai approval required before live deployment

2. **Deploy v254 confirmed fixes (3 ready to build, 1 awaiting approval)**
   - **Harvest gate bug (Issue #3):** Gate on anchor ±0.02 instead of entry_price ±0.05. Confirmed 2 sessions (Apr 8-9) selling below entry. Build confidence: HIGH.
   - **BDI=0 hold removal (Issue #2):** Remove forced exit delay. Confirmed 2 sessions showing zero value from hold, only slippage cost. Build confidence: HIGH.
   - **Harvest anchor refresh (Issue #3 part 2):** Refresh anchor after 3 consecutive COOL cycles to prevent indefinite locks. Confirmed in analysis. Build confidence: HIGH.
   - **COUNTER sizing override (Issue #5):** Cap risk_multiplier to 1.00 on COUNTER trades. Evidence: 3 trades showing identical -$26.75 catastrophic losses. Simulation shows +$20.25 savings on one trade. Build confidence: MEDIUM-HIGH (3 trades = approaching threshold, pattern is deterministic). **Awaiting Kai approval.**

3. **Specification for v255 phantom position reconciliation fix**
   - POS WARNING must emit on ALL settle paths, not just stop-attempt paths
   - Settlement P&L computed from API position size (not local book)
   - Hard fail-safe: if API position diverges from local by >1c, log "RECONCILE FAIL" and do NOT apply the settlement P&L
   - Test spec against Apr 8-10 logs: expect reconciliation gap to close significantly
   - Estimated build time: 4-6 hours for implementation + testing
   - Kai approval required before merge

---

## IMMEDIATE (P1 — This week, start after halt is confirmed)

4. **Test v254 on offline logs (Apr 7-12 trading data)**
   - Simulate harvest gate fix against all Apr 7-12 trades
   - Simulate BDI=0 removal against all stop events
   - Simulate anchor refresh against COOL streak patterns
   - Verify no collateral damage (secondary effects on other strategies)
   - Generate net EV improvement report for Kai review

5. **Build v254 from master source**
   - Read `~/Documents/Projects/AetherBot/Code versions/AetherBot_MASTER_v254.py`
   - Apply 3 confirmed fixes (harvest gate, BDI=0, anchor refresh)
   - Run ast.parse() validation
   - Run BUILD_AUDIT (30 checks)
   - Increment version string to v254 (confirm it matches output filename)
   - Deploy to Mini, tail logs for v254-specific signatures (OB_FORMAT_DIAG, yes_dollars)
   - **Approval gate:** Kai must approve before this build runs

6. **Build v255 from v254 base (prerequisite: v254 confirmed live)**
   - Extend POS WARNING to all settle/close events
   - Change settlement P&L calculation to use API position size
   - Add fail-safe: `if API_pos_size diverges from local_pos_size by >1c: log "RECONCILE FAIL", skip P&L`
   - Test against Apr 8-10 logs: verify reconciliation gap closes
   - ast.parse() + BUILD_AUDIT validation
   - **Approval gate:** Kai must approve before this build runs

7. **Kai approval loop for both builds**
   - Submit v254 build spec (3 fixes, simulation results, secondary effects analysis)
   - Await Kai APPROVED/DISAPPROVED
   - Submit v255 build spec (phantom position fix, reconciliation closure proof, secondary effects)
   - Await Kai APPROVED/DISAPPROVED
   - Log all approvals to `agents/aether/ledger/kai-aether-log.jsonl`

---

## NEAR-TERM (P2 — Next 1-2 weeks, after v254+v255 deployed)

8. **Monitor for harvest algorithm improvement in evening sessions**
   - Apr 10 evening: 8/8 harvest success vs 3/81 earlier in day (267% improvement)
   - Hypothesis: book thickness increased in evening, or harvest gating changed naturally
   - Action: Extract evening harvest metrics for Apr 11-12 (if trading restarts)
   - Goal: Understand what changed and apply learning to daytime harvest gating

9. **Expand EU_MORNING data collection (Issue #1 monitoring)**
   - Currently: 1 trade (Apr 8, BCDP_FAST_COMMIT +$0.71)
   - Need: 3+ clean sessions before proposing strategy gating
   - Action: Track EU_MORNING trades for next 2 weeks, aggregate W/L by sub-strategy (BCDP vs PAQ)
   - Decision gate: If W/R ≥ 75% across 3+ sessions, consider EU_MORNING gating proposal

10. **Expand EVENING window analysis (Issue 2 monitoring)**
    - Currently: 1 slippage event (Apr 8, -$0.70 on 7c over 7 attempts)
    - Need: 3+ EVENING stop events with slippage data before proposing fix
    - Action: Track EVENING stops for next 2 weeks, calculate average slippage, book thickness at stop time
    - Decision gate: If avg slippage > 0.1% in >50% of stops, propose EVENING_SOFT_EXIT gating for v256

11. **Implement CCXT exchange API integration (blocked on Hyo providing keys)**
    - Current status: Demo mode only, no live trade capture
    - Prerequisite: Hyo provides read-only exchange API keys (Binance, Coinbase, OKX)
    - Action: Install CCXT, implement trade fetch + import logic, test against live exchange
    - Expected timeline: 2-3 hours implementation once keys provided
    - Benefit: Trades flow into ledger automatically instead of manual posting

12. **Add circuit breaker + retry logic for HQ push failures**
    - Current: If HQ push fails (non-200), log error but continue silently
    - Risk: Silent metric loss, HQ dashboard stale
    - Action: Implement exponential backoff (3 retries max), then escalate P1 flag to Kai
    - Expected timeline: 1 hour

13. **Implement concurrent write safety for metrics.json**
    - Current: Atomic move (write temp, rename final) — safe but not stress-tested
    - Future: Consider moving to Vercel KV for transactional safety
    - Action: Stress-test current atomic move approach under high concurrency (simulate 4 overlapping 15-min cycles)
    - Decision: Keep atomic move or migrate to KV based on test results

---

## RESEARCH (P3 — Strategic, when time permits)

14. **Investigate conviction scoring at session boundaries**
    - Analysis files don't deeply explore: does conviction scoring differ at 15-min window transitions?
    - Hypothesis: Entries at T-5min (near window end) may have different conviction behavior than T-10min
    - Action: Extract all April trades by window position (T-15 to T0), compare conviction distributions
    - Rationale: Session-boundary behavior could explain why some windows have higher loss rates

15. **Position sizing review across strategy families**
    - Current: bps_premium avg 10c, PAQ_EARLY_AGG avg 17c
    - Question: Is position sizing correlated with conviction? With strategy family?
    - Action: Build sizing matrix (strategy × conviction × session window), analyze P&L by cell
    - Rationale: May reveal opportunities to resize aggressively in high-edge cells

16. **Slippage analysis across all exit mechanisms**
    - Current: 1 event (EVENING stop slippage -$0.70)
    - Data needed: For EVERY exit (harvest, stop, trailing, settle), calculate execution_price - market_at_entry
    - Action: Build slippage ledger for Apr 7-12, weekly report
    - Benefit: Identify which exit mechanism costs most; gate accordingly

17. **Weekly win-rate trend analysis (week-over-week degradation detection)**
    - Once Aether goes live with metrics collection (every 15-min cycle)
    - Action: Every Monday, compare current week WR vs prior week WR
    - Decision threshold: If WR degradation > 10 percentage points, flag P1 to Kai
    - Rationale: Early warning system for strategy drift or market regime shift

18. **Harvest success rate by book-thickness regime**
    - Hypothesis: Harvest MISS rate correlates with order book thinness
    - Data needed: For each harvest attempt, record bid spread at time of attempt
    - Action: Categorize harvests into thick/medium/thin book, compare success rates
    - Benefit: Inform future harvest gating on book thickness signals

---

## Monitoring Metrics (continuous, weekly review)

**Daily Aether Check (review first thing Monday):**
- [ ] Balance: is it ≥ $90.25 starting point?
- [ ] Tickers resolved: is it ≥ 80/day?
- [ ] Win rate: is it ≥ 50%?
- [ ] Reconciliation gap: is it < $5 (< $10 is P0)?
- [ ] Largest single-trade loss: is any trade > -$4? Why?

**Weekly Aether Review (every Monday morning):**
- [ ] Compare current week PnL vs prior week
- [ ] Win rate trend: up or down?
- [ ] Harvest success rate: up or down?
- [ ] Strategy mix: which families are active? Why?
- [ ] Conviction scoring: is it calibrated? Any drift?
- [ ] Session window performance: which windows underperform?

**Monthly Aether Retrospective (1st of month):**
- [ ] Trade ledger data integrity: any corruption? Any gaps?
- [ ] Dashboard metrics: accurate? Any drift from real balance?
- [ ] HQ push reliability: 99%+ success rate?
- [ ] Build quality: any regressions since last deploy?
- [ ] Research findings: anything actionable for next month?

---

## Success Criteria (Recovery Phase)

- [x] Historical data migration complete (41 analysis files digested)
- [x] Comprehensive playbook updated (Apr 7-12 trading reality documented)
- [ ] v254 fixes approved by Kai and deployed to test environment
- [ ] v255 phantom position fix approved by Kai and deployed
- [ ] Offline log testing shows reconciliation gap closes significantly
- [ ] Live restart approved by Kai (only after both builds validated)
- [ ] First week post-restart shows PnL ≥ $5/day average
- [ ] Harvest success rate ≥ 30% (improvement from 12.4%)
- [ ] Win rate ≥ 55% (improvement from recent underperformance)
- [ ] Reconciliation gap < $5 (all sessions)

---

## Timeline Estimate

**This week (Apr 13-18):**
- [x] Playbook + Priorities rewrite (DONE)
- [ ] v254 offline testing (4-6 hours)
- [ ] v254 build + deploy (2-3 hours)
- [ ] Kai review cycle (2-3 days)

**Next week (Apr 20-25):**
- [ ] v255 build + test (6-8 hours)
- [ ] Kai review cycle (1-2 days)
- [ ] Live restart approval
- [ ] First trading week data collection

**Ongoing (parallel):**
- [ ] EU_MORNING + EVENING monitoring (daily)
- [ ] CCXT integration (2-3 hours, blocked on Hyo keys)
- [ ] Circuit breaker + retry logic (1 hour)
- [ ] Concurrent write safety testing (1 hour)


<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
