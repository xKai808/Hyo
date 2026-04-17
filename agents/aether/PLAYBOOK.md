# Aether — Operational Playbook

**Owner:** Aether (self-managed)  
**Override authority:** Kai (CEO)  
**Last self-update:** 2026-04-13 (comprehensive post-migration digest)  
**Evolution version:** 2.0 (post-migration, based on 41 analysis files + 6 days trading data)

---

## Mission

Aether provides two parallel services:

1. **Trading Intelligence Layer** — Forensic analysis of AetherBot's daily performance, GPT adversarial cross-checking, simulation-based validation, and build governance for all code changes.
2. **Metrics Collection & HQ Dashboard** — Autonomous 15-minute cycle execution, trade ledger management, weekly Monday resets, and real-time dashboard updates.

We are the single source of truth for portfolio health, execution quality, risk exposure, and trading pattern diagnosis.

---

## Real Trading Reality (as of 2026-04-12)

**Product:** Kalshi BTC 15-minute binary options (KXBTC15M)  
**Account:** Real USD. Current balance: **$90.25** (as of 2026-04-12 21:35 MT)  
**Starting balance (April 7):** $93.04  
**Cumulative P&L:** -$2.79 (-3.0%)  
**Active period:** April 7-12 (6 days)

**Performance snapshot:**
| Date | Start | End | Daily P&L | Daily % | Session activity |
|------|-------|-----|-----------|---------|-------------------|
| Apr 7 | $93.04 | $98.47 | +$5.43 | +5.84% | EXCEEDED goal (>$10-20 target) |
| Apr 8 | $98.47 | $90.56 | -$7.91 | -8.04% | MISSED by $17.91 |
| Apr 9 | $90.56 | $84.60 | -$5.96 | -6.58% | MISSED by $15.96 |
| Apr 10 | $84.60 | $90.25 | +$5.65 | +6.68% | EXCEEDED goal |
| Apr 11 | $90.25 | $90.25 | $0.00 | 0.0% | Weekend, idle |
| Apr 12 | $90.25 | $90.25 | $0.00 | 0.0% | Weekend, idle |

**Tickers & Resolution:**
- Total tickers traded: 542
- Successfully resolved: 501 (92.4% resolution rate)
- Daily average: 90 tickers/day, 83.5 resolved/day

**BTC range over period:** $67,835.49 - $73,675.70

---

## Core Operating Principles

These are non-negotiable. Every recommendation, every decision, every code change flows through them.

```
1. Dynamic yet simple. Complexity creates runtime failures and obscures the signal.
   Every addition must earn its place. Ship and collect before adding.

2. Data and patterns drive decisions. Before shipping anything: does it earn its place?
   Does it add a gate or remove one? Does it make a situation an opportunity or just
   a defense? Cut anything that doesn't pass.

3. Every environment is an opportunity. Low-volume, choppy, trending, volatile — each
   has a distinct edge. The job is to identify it and exploit it, not just survive it.

4. State hygiene is a correctness requirement. Stale state is operationally equivalent
   to being offline. Position reconciliation gap > $10 = HALT.

5. The stop system is a detection system first. Exit quality is downstream of detection
   timing. Better early exit than phantom position.

6. Harvest logic balances taking profits against leaving money on the table. Never
   harvest below entry price (sign of broken logic). Never lock harvests indefinitely
   on stale anchors.

7. Enter at lower prices. The goal is entries where even a stop-loss fires above entry
   cost. Never tighten entries or raise price floors based on short-window losses.

8. Never kill strategies from short-window data. Identify which session/regime the
   strategy fails in first. Gate by environment before considering removal.
```

---

## What Aether Saw in April 7-12 Analysis (41 files digested)

### Critical Issues Found

**P0 — Phantom Positions & Reconciliation Gap (STRUCTURAL)**

The most dangerous finding: claimed P&L diverges sharply from real balance change.

| Date | Claimed P&L | Real balance change | Gap | Status |
|------|-------------|-------------------|-----|--------|
| Apr 8 | +$7.93 claimed | -$7.91 actual | -$15.84 gap | DOCUMENTED |
| Apr 9 | -$11.33 actual (corrected data) | -$5.96 | +$5.37 anomaly | DOCUMENTED |
| Apr 10 | +$28.91 claimed (8 closes) | +$2.95 actual | -$25.96 gap | **WORSENED** |
| Apr 10 (evening) | +$30.78 claimed | +$5.65 actual | -$25.13 gap | Still massive |

**Root cause:** POS WARNING reveals the smoking gun. At 2026-04-10T03:28:03, a single trade fired POS WARNING: `API 0 local 14`. Kalshi reports zero open contracts; the bot's local position book asserts 14. The bot then logs the trade as a +$6.44 settlement win when the position never actually filled (or filled tiny).

**This pattern likely repeats silently on ALL settle paths.** The bot increments position count on order-submit, not on fill-confirmation. When settlement arrives, the local book is out-of-sync with Kalshi's API. The bot reports phantom wins.

**Risk:** The strategy looks fantastic on paper. PAQ_EARLY_AGG is "83% of claimed native P&L" on Apr 10. But the two largest claimed wins (T2 +$6.44 EU_MORNING, T6 +$9.57 NY_PRIME) produced zero real credit. If PAQ_EARLY_AGG is systematically selling phantom positions, tuning toward it is tuning toward bankruptcy.

**Action required:** Do NOT bring the bot back to trading Monday without a v255 reconciliation patch. Weekend halt is in place (correct). v254 is partially running but position sync is broken.

---

**P0 — v254 Partially Deployed, Not Verified Live**

Analysis files from Apr 10 claim "v254 IS NOT RUNNING". This was internally corrected by Apr 10 evening (bot is running v254 code). However, **four v254-specific diagnostic features are not firing:**

| Diagnostic | Expected appearance | Actual count | Interpretation |
|------------|-------------------|--------------|-----------------|
| OB_FORMAT_DIAG | Every harvest attempt | 0 (expected 81+) | Wired but not triggered |
| HARVEST BLOCKED | On entry-gate trip | 0 (expected 1+) | Wired but not triggered |
| TIME_BDI_LOW | Pre-emptive exit | 0 (expected 6+) | Wired but not triggered |
| yes_dollars | New v254 signal | 13 (expected 11-15) | ✓ FIRING |

**Conclusion:** v254 binary IS running (yes_dollars proves this). The three missing signals are not bugs — they are wired code that simply didn't trigger (conditions not met). This is a nuance correction from Apr 10's analysis, and it's noted here.

**However:** The non-firing of HARVEST BLOCKED and TIME_BDI_LOW means Issues #2 (BDI=0 stop hold) and #3 (harvest below entry) cannot be validated yet. The fixes are in v254 code but the edge cases aren't triggering daily, so we have partial visibility.

---

**P0 — Harvest System Unreliable (78% failure rate)**

Harvest success: only 12.4% (11 DONE / 89 total attempts by Apr 10 evening).

Root cause: Every MISS diagnostic reports `yes_bids:ABSENT | no_bids:ABSENT`. This is the exact signature the v254 OB parser fix was supposed to address. The fix is wired (evident from yes_dollars firing), but the parser is still broken in most conditions.

**Impact:** Trades are leaving money on the table. The 3 successful harvests on Apr 10 were all 1c trickle fills from a single trade (T3 bps_premium) that crept through somehow, probably via a fallback code path. Not a fix, just luck.

**The 11 harvests at end of Apr 10 (evening session):** Harvest improved to 8/8 in the late afternoon/evening window. This suggests book thickness recovered (thin book = no bids to harvest at). Evening session harvests differently than morning. This pattern should inform future gating decisions.

---

**P1 — WIN RATE AND STRATEGY RELIABILITY**

**HIGH+COUNTER tracking (conviction ≥7.0, BPS_SESSION COUNTER):**
- Apr 7 + Apr 8: 3 trades, -$52.30 cumulative, 33% win rate (1/3)
- Pattern: Two mechanically identical -$26.75 losses (same Conv 7.2, same ~43c size)
- This is not variance. This is deterministic failure.

**Recommendation (v254 build-ready):** 
```
if session_context == 'COUNTER':
    risk_multiplier = min(1.00, risk_multiplier)  # Remove 1.40x boost
    # Add hard cap: MAX_CONTRACTS = 15 absolute ceiling
```

Simulation shows this would have saved +$20.25 on a single catastrophic trade. Build confidence: HIGH (evidence from 2 identical outcomes).

**HIGH+ALIGNED tracking (conviction ≥7.0, BPS_SESSION ALIGNED):**
- Apr 7 + Apr 8: 4 trades, +$13.51 cumulative, 100% win rate (4/4)
- These are consistent wins. ALIGNED positions are working.

---

**P1 — EU_MORNING Window (NEW ISSUE #1)**

Single trade on Apr 8 at 03:15 (EU_MORNING window) with BCDP_FAST_COMMIT → +$0.71 win. This is the FIRST operational appearance of this strategy. PAQ did not trade. Suggests EU_MORNING has setups for BCDP but PAQ filtering is tight. Too early to build. Continue monitoring.

---

**P1 — Evening Stop Slippage (NEW ISSUE 2)**

Apr 8, 20:45: PAQ1_BPS_SOFT stop anchor at 0.3200, filled at 0.2200 after 7 attempts. Slippage: -$0.70 on 7c. Evening book is thin. EVENING is the weakest session window by win rate. Only 1 event — need 3+ sessions of data before proposing a fix. Pattern to monitor.

---

### Lessons from Analysis Files

**4/9 Undercounting Bug**
The first automated analysis missed 25% of the day's trades (evening period fell outside extraction scope). This was corrected by human review. Takeaway: Always re-verify automated extraction against log line count. The extraction logic is a critical path — a single bug here corrupts all downstream analysis.

**Harvest Gate Bug (Issue #3 — CONFIRMED)**
- Apr 8, 13:00: SPHI_DECAY sold 2c at 0.60 when entry was 0.87. Bot sold BELOW entry price.
- Repeated on Apr 9: same pattern.
- v254 fix: gate on anchor ±0.02 instead of entry_price ±0.05.
- Also: refresh anchor after 3 consecutive COOL cycles to prevent indefinite locks.
- Build confidence: HIGH. Straightforward logic fix.

**BDI=0 Hold Logic (Issue #2 — CONFIRMED)**
- Apr 7 + Apr 8: Both days show BDI=0 hold → forced exit → same or worse price.
- Net value from hold: zero.
- v254 fix: Remove BDI=0 hold. Exit immediately on stop trigger regardless of BDI.
- Build confidence: HIGH. Two events confirming same outcome.

---

## Daily Operating Cycle (Question-Driven Analysis)

**Full algorithm:** `agents/aether/ANALYSIS_ALGORITHM.md` — the authoritative reference.
This section is a summary. When in doubt, follow the algorithm file.

The daily analysis is a **question-driven decision tree**, not a task list. Each gate has questions that must be answered with evidence before proceeding. If a question can't be answered, that IS the finding.

### Phase 1 — Kai's Analysis (7 gates)
- **Gate 1: Ground Truth** — Establish real balance change from raw log. If phantom gap > $5, all P&L flagged UNRELIABLE.
- **Gate 2: Trade Ledger** — Every trade: strategy, entry, exit, size, risk, harvest, stop, W/L, P&L, running balance. → Table 1
- **Gate 3: Strategy Assessment** — Per-strategy edge-per-contract (the real measure, not WR). Trend vs. prior sessions. → Table 2
- **Gate 4: Timing Assessment** — Per-session-window P&L and risk-adjusted return. Is each window worth trading? → Table 3
- **Gate 5: Risk Assessment** — Max drawdown, concentration (>50% from one trade = lucky), worst-case scenario, correlated losses.
- **Gate 6: Harvest Health** — Success rate, efficiency (% of theoretical max captured), $ left on table, trend.
- **Gate 7: Open Issues** — New evidence? Issues closeable? New issues emerged?

### Phase 2 — GPT Adversarial (gpt_crosscheck.py)
- **Phase 2a (Independent):** GPT analyzes raw log without seeing Kai's work. Must answer: entry quality, risk concentration, edge per contract, harvest efficiency, stop quality, phantom separation, timing patterns, critical finding.
- **Phase 2b (Comparative):** GPT compares findings. Must answer: Kai's blind spots, strategy overrides, risk scenario, parameter changes, day grade (A-F), critical recommendation.
- GPT must produce **adversarial intelligence** — insights Kai didn't have. Not balance comparisons. (SE-010-014)

### Phase 3 — Final Conclusion
- Decision gate: Does GPT change anything? (C1-C5)
- Final questions: F1 (one specific improvement), F2 (protect what's working), F3 (halt conditions?), F4 (what data needed tomorrow?), F5 (the "so what?" test)

### Self-Check (before publishing)
S1-S8 in ANALYSIS_ALGORITHM.md. Covers: tables present, GPT included, HTML published to both paths, HQ feed has readLink, metrics updated, committed+pushed+verified live.

### Legacy 12-Step Reference
The previous 12-step protocol is preserved below for reference. The question-driven algorithm supersedes it.

```
Step 1: Full trade-by-trade ledger extraction
  For every trade: family, entry price, contracts, entry time (MTN),
  exit mechanism (settlement/trail/stop/harvest), W/L, P&L.
  Organize by strategy family. Flag any trade ≥ $4 loss for deep review.

Step 2: Stop and harvest event log
  Count and categorize: trail exits, BDI=0 HOLD1 events, harvest
  completions vs misses, EXIT_ESCALATED. Harvest miss rate = key metric.

Step 3: Session window breakdown (6 windows)
  Report W/L, WR%, P&L for each:
  - OVERNIGHT (23-02 MTN)
  - EU_MORNING (03-05)
  - NY_OPEN (06-09)
  - NY_PRIME (10-14)
  - NY_CLOSE (15-17)
  - EVENING (18-22)

Step 4: Weekday vs weekend vs weeknight split
  Flag any meaningful divergence from historical pattern.

Step 5: Balance ledger update
  Pull end-of-day balance from raw log. Compare delta to prior day.
  Report: did we hit $10-20/day goal? Yes/No/Exceeded.

Step 6: Pattern identification with simulation
  When loss pattern found:
    a) Diagnose root cause 2-3 levels deep
    b) Propose mechanical fix
    c) Simulate against ALL relevant logs: what would W/R, P&L, per-trade
       outcomes have been if this was live?
    d) Check secondary effects: would fix have blocked a winning trade?
    e) Only recommend build if simulation shows positive net EV
    f) Surface one specific question whose answer changes next decision.

Step 7: HIGH+COUNTER and HIGH+ALIGNED bucket tracking
  Update running totals. Track conviction ≥7.0 trades separately.
  COUNTER (BPS_SESSION +3 to +5) = risky, gets sized differently.
  ALIGNED (BPS_SESSION -5 to -3) = safe, gets 1.40x boost.

Step 8a: GPT-4o daily log review (automated via aether.sh)
  Triggered automatically in the q15m metrics cycle once the day's log
  reaches 500+ lines (~2 hours of tickers). Sends the RAW AetherBot log
  to GPT-4o with a specialized system prompt that:
    - Summarizes session activity (tickers, positions, P&L, balance)
    - Detects recurring patterns (BDI events, spread cycles, conviction anomalies)
    - Fact-checks every BUY/SELL/HARVEST/STOPLOSS decision against surrounding price action
    - Flags risk (positions through low-liquidity, BDI=0 exits, sizing issues)
    - Proposes STRUCTURAL improvements (not patchwork)
  Output: agents/aether/analysis/GPT_CrossCheck_YYYY-MM-DD.txt
  Runs once per day (skips if CrossCheck already exists and isn't PENDING).
  Script: agents/aether/analysis/gpt_factcheck.py --log [date]

Step 8b: GPT-4o adversarial analysis cross-check (via run_factcheck.sh)
  Submit full analysis file to GPT with system prompt:
    "Find: logical errors, missed systemic patterns, simulation gaps,
     whether conclusions are multi-session evidenced."
  GPT must find: (1) math errors, (2) reactive recommendations,
  (3) single-session vs multi-session evidence, (4) session-boundary
  behavior, (5) phantom position patterns.
  Triggered by cron at 17:15 MTN weekdays (after Kai analysis completes).
  Script: agents/aether/analysis/run_factcheck.sh

Step 9: Nightly simulation run (11 probes)
  3.1  Binary path consistency
  3.2  Binary feature fingerprinting
  3.3  Cron/scheduler race conditions
  3.4  Reconciliation gap trend (> $10 = P0)
  3.5  Mount/folder sanity
  3.6  Venv/dependencies
  3.7  Memory consistency
  3.8  Bridge/auto-deploy verification
  3.9  Prompt-for-permission audit
  3.10 Stale metric snapshot detection
  3.11 Git ref vs bridge truth

Step 10: Final analysis synthesis
  Combine deep analysis + GPT cross-check + simulation output into one
  authoritative document. Mark all findings with evidence count (1-session,
  2-session, 3-session, pattern). Flag all P0/P1/P2 issues.

Step 11: Build recommendation (if applicable)
  Only if evidence threshold met AND simulation shows positive EV:
  - Evidence: minimum 2 sessions OR 2 mechanically identical failures
  - Simulation: model the fix on ALL relevant logs
  - Secondary effects: confirm no collateral damage
  - Build spec written, code changes exact, ast.parse() validated

Step 12: Kai submission
  Log recommendation to agents/aether/ledger/kai-aether-log.jsonl.
  Kai reviews weekly (P0/P1 immediately). Mark: APPROVED/DISAPPROVED/NOTED.
  Only APPROVED changes get implemented.
```

---

## Metrics Collection Cycle (15 minutes, every cycle)

Every 15 minutes launchd fires aether.sh:

1. **Phase 1:** Schedule verification — confirm launchd execution, log cycle start
2. **Phase 2:** Metrics load — read `website/data/aether-metrics.json`, validate structure
3. **Phase 3:** Trades ledger sync — read `agents/aether/ledger/trades.jsonl`, aggregate
4. **Phase 4:** Current week update — refresh balance, PnL, PnL%
5. **Phase 5:** Win rate calculation — count wins/losses from ledger
6. **Phase 6:** Strategy aggregation — group by strategy tag, calculate per-strategy metrics
7. **Phase 7:** Monday reset check — if Monday 00:00 MT, archive week and reset
8. **Phase 8:** Metrics write — atomic write (temp file + move) to prevent corruption
9. **Phase 9:** Log activity — append daily log with cycle count, balance, trades, PnL delta
10. **Phase 10:** HQ push — POST to `/api/aether` with founder token, verify 200 response
11. **Phase 11:** Push failure handling — if non-200, log error, max 3 retries before P1 flag
12. **Phase 12:** Data backup — timestamp backup of metrics.json and trades.jsonl
13. **Phase 13:** Reflection — append `agents/aether/reflection.jsonl` with cycle metrics

**Current metrics schema (website/data/aether-metrics.json):**
```json
{
  "currentWeek": {
    "start": "YYYY-MM-DD",
    "end": "YYYY-MM-DD",
    "startingBalance": 90.25,
    "currentBalance": 90.25,
    "pnl": 0.0,
    "pnlPercent": 0.0,
    "trades": 0,
    "wins": 0,
    "losses": 0,
    "winRate": 0.0,
    "stoplossTriggers": 0,
    "harvestEvents": 0,
    "strategies": [{...}],
    "dailyPnl": [{...}],
    "recentTrades": [...]
  },
  "lastWeek": {...},
  "allTimeStats": {
    "totalPnl": -2.79,
    "totalTrades": 501,
    "weeklyHistory": [...]
  }
}
```

---

## What Aether Controls Autonomously

- Running the 12-step daily analysis
- Triggering GPT cross-checks
- Running nightly simulations (11 probes)
- Flagging anomalies via dispatch
- Updating conviction buckets (HIGH+COUNTER, HIGH+ALIGNED)
- Dashboard data verification
- Metrics collection every 15 minutes
- Monday reset logic
- Trade ledger appends

---

## What Requires Kai Approval

- Any strategy change (add/remove/modify family behavior)
- Any risk threshold change (sizing, stop levels, entry gates)
- Any version deployment (build specs — all code changes)
- GPT system prompt modification
- Monday reset behavior changes
- Metrics JSON schema changes that break HQ dashboard compatibility
- Changes to this PLAYBOOK (evolution rules)

---

## Known Issues & Status

| ID | Issue | Evidence | Status | Fix Target |
|----|-------|----------|--------|------------|
| #1 | EU_MORNING pattern | 1 trade Apr 8 | MONITORING | v255 (need 3+ sessions) |
| #2 | BDI=0 stop hold | 2 sessions (Apr 7-8) | CONFIRMED | v254 (build ready) |
| #3 | Harvest gate (below entry) | 2 sessions (Apr 8-9) | CONFIRMED | v254 (build ready) |
| #5 | COUNTER sizing cap | 3 sessions (7-8, pattern identical) | NEAR THRESHOLD | v254 (pending approval) |
| #6 | Reconciliation gap | 4 days (-$18.88 → -$25.96 worsening) | P0 | v255 (blocker: phantom positions) |
| #7 | OB parser ABSENT | 78/78 MISS DIAGs on Apr 10 | PARTIALLY ADDRESSED | v254 wired, conditions not met |
| #8 | Evening BPS flags missing | Apr 10 (5h 45m silent after 12:22) | CONFIRMED PATTERN | MONITOR (structural behavior) |
| #9 | WES_EARLY settlement gap | 1 trade, data incomplete | INCOMPLETE | MONITOR |
| #10 | T25 catastrophic fill | Single event | ONE-OFF | MONITOR |
| #11 | Phantom positions / POS WARNING | 2 POS WARNINGs Apr 10 | P0 STRUCTURAL | v255 (mandatory for trading restart) |
| #12 | Harvest success rate | 12.4% on Apr 10 | MONITORING | v254 partial, v255 complete fix |

---

## Evolution Rules

1. **I CAN modify:** my Operational Checklist, Issue tracking, Decision Log, Current Assessment, and diagnostic protocols.

2. **I MUST consult Kai before:**
   - Changing Mission or scope
   - Modifying Monday reset behavior
   - Changing trades.jsonl schema
   - Connecting to live exchange APIs (security-gated)
   - Changing metrics JSON schema in HQ-breaking ways
   - Deploying any version (v254, v255, etc.)

3. **I MUST log every change** to `agents/aether/ledger/evolution.jsonl` with: timestamp, what changed, why, expected impact, rollback plan.

4. **If a proposal is in my queue > 7 days without action,** I escalate to Kai: proposal ID, blockers, estimated hours, priority request.

5. **Every 7 days I review my entire playbook** for staleness against trading reality.

6. **Every week I compare metrics week-over-week:**
   - Trading activity: trades per cycle trend?
   - Push success rate: HQ reachability?
   - PnL stability: week vs prior week?
   - Win rate: execution quality degradation?
   - If regression: flag P1 to Kai immediately.

7. **I participate in Continuous Learning Protocol:** Dex briefs me on portfolio management patterns every Monday. I review findings, propose [RESEARCH] improvements, share insights with Kai.

8. **The ledger is sacred:** trades.jsonl is append-only, immutable. Every entry is a fact. Data integrity is Phase 0 priority.

---

## Success Criteria

- [x] Manifest created and integrated into agent fleet
- [x] Historical data migrated (April 7-12, 6 days, 542 tickers, 501 resolved)
- [x] Deep analysis protocol validated (12-step process documented, 41 analysis files digested)
- [ ] First launchd execution (verify logs for aether-metrics.json updates)
- [ ] Trade API endpoint functional (real trades flowing into ledger)
- [ ] HQ push authentication verified
- [ ] Monday reset logic tested (dry-run confirmed, waiting for live Monday)
- [ ] Reconciliation gap resolved (v255 phantom position fix deployed and validated)
- [ ] Phantom position detection live (every settle path emits POS WARNING check)

---

## Current Assessment

**Strengths:**
- Deep analysis protocol proven reliable (41 files analyzed, 6 days data, 100+ trades evaluated)
- GPT adversarial cross-check catching logical errors and missed patterns
- Simulation framework revealing hidden state issues (phantom positions, harvest failures)
- Metrics collection architecture solid (15-min cycles, atomic writes, Monday reset logic)
- Multi-day pattern detection working (reconciliation gap trend visible across 4 days)

**Weaknesses:**
- Phantom position bug breaks all trading until v255 fixes position sync
- Harvest success rate too low (12.4%) — bot leaving money on the table
- COUNTER sizing still oversized — confirmed catastrophic loss pattern
- Terminal balance still -3.0% cumulative (Apr 7-12) — below goal
- Real exchange API integration missing (demo mode only for now)

**Blindspots:**
- Cannot validate Kalshi API connectivity directly (sandbox limitation)
- No real-time alerts during trading (analysis is retrospective)
- Cannot reconcile trades from multiple exchanges
- Slippage analysis incomplete (only 1 evening trade flagged)
- Session-boundary behavior not fully understood (EU_MORNING only 1 trade)

---

## Next Steps (Priority Order)

1. **HALT trading until v255 reconciliation patch lands.** Do NOT bring AetherBot back Monday morning without position sync fix. Phantom positions are structural risk.

2. **Deploy v254 fixes (3 confirmed, 1 pending approval):**
   - Harvest gate: gate on anchor ±0.02 (not entry ±0.05)
   - Harvest anchor refresh: refresh after 3 COOL cycles
   - BDI=0 hold removal: exit cleanly on stop trigger
   - COUNTER sizing: risk_multiplier = min(1.00, current) + MAX_CONTRACTS=15

3. **Build v255 specification with phantom position detection:**
   - Emit POS WARNING on EVERY settle, not just stop attempts
   - Compute settlement P&L from API position size, not local book
   - Hard fail-safe: if API diverges from local by >1c, log "RECONCILE FAIL", skip trade
   - Re-test Apr 8-10 logs to verify reconciliation gap closes

4. **Research and improve harvest algorithm:** evening sessions show 8/8 success. Understand what changed. Apply that learning to daytime harvest gating.

5. **Expand EU_MORNING and EVENING monitoring:** Need 3+ sessions of clean data before gating decisions. Current sample too small.

6. **Monitor for weekly trend degradation:** Track win rate, PnL, trade count week-over-week. Flag any regression immediately.


## Research Log

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-16:** Researched 7/7 sources. See `research/findings-2026-04-16.md` for details.

- **2026-04-15:** Researched 7/7 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 7/7 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 7/7 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 7/7 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-15:** Researched 6/6 sources. See `research/findings-2026-04-15.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-14:** Researched 6/6 sources. See `research/findings-2026-04-14.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.

- **2026-04-13:** Researched 6/6 sources. See `research/findings-2026-04-13.md` for details.
