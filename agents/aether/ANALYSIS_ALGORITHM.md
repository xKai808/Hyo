# Aether Daily Analysis Algorithm

**Purpose:** This is not a checklist. It is a decision tree. Each question must be answered with evidence before proceeding. If you cannot answer a question, that IS the finding — stop and report what's blocking the answer.

**Trigger:** Daily at 23:00 MT after raw log is complete.
**Owner:** Aether (self-managed), reviewed by Kai
**Last updated:** 2026-04-18 (v2.1 — Phase 0 added, protocol reference wired)

---

## PHASE 0 — READ THE PROTOCOL FIRST (MANDATORY)

**Before opening the log, before answering any gate question:**

```
READ: agents/aether/PROTOCOL_DAILY_ANALYSIS.md (VERSION 2.1)
```

This protocol is the complete execution specification. It defines:
- What 7 files to read before starting (Part 0)
- What to inject into every Claude system prompt (Part 1)
- All gate questions with output formats (Part 2 = this file, expanded)
- GPT dual-phase requirements (Part 3)
- Exact report format and section markers (Part 5)
- The 35-item completion checklist that must pass before publishing (Part 9)

**Do not treat this algorithm as the complete spec.** This file is the gate questions.
The protocol is the complete execution context. Both must be read.

If there is any conflict between this file and PROTOCOL_DAILY_ANALYSIS.md:
the PROTOCOL wins. This file is subordinate to the protocol.

---

## PHASE 1 — KAI'S ANALYSIS (Questions That Must Be Answered)

### Gate 1: Ground Truth

Before analyzing anything, establish what actually happened.

```
Q1.1: What is the FIRST balance line in today's log?          → $ ____
Q1.2: What is the LAST balance line in today's log?           → $ ____
Q1.3: What time (MT) was the last balance line?               → ____
Q1.4: NET = Q1.2 - Q1.1 =                                    → $ ____
Q1.5: Does this match what the bot CLAIMS in settlement sums? → YES / NO
      If NO → phantom gap = $ ____. This is the #1 finding.
```

**GATE:** If Q1.5 = NO and gap > $5, all subsequent P&L figures must be flagged as UNRELIABLE. Do not report claimed P&L as real. The analysis headline is the balance change, not the settlement sum.

### Gate 2: What Happened (Trade Ledger)

For EVERY trade that settled today, answer:

```
Q2.1: What strategy triggered this trade?
Q2.2: What side (YES/NO) and at what entry price?
Q2.3: How many contracts? What was the total risk ($)?
Q2.4: How did it exit? (settlement / harvest+settlement / stop / trail)
Q2.5: If harvested: how many contracts harvested vs. total? At what prices?
Q2.6: If stopped: what triggered the stop? (BDI, trail, time, chop?)
Q2.7: What was the net P&L from balance change (not claimed)?
Q2.8: What was the balance before and after?
```

**OUTPUT:** Table 1 — Trade-by-Trade Ledger with all columns populated.

### Gate 3: Strategy Assessment

For EACH strategy that traded today, answer:

```
Q3.1: How many trades did this strategy take?
Q3.2: What was the entry price range?
Q3.3: What was the net P&L?
Q3.4: What was the win rate?
Q3.5: ★ What is the EDGE PER CONTRACT RISKED?
      (net P&L ÷ total contracts risked across all trades)
      This is the real measure. A strategy with 90% WR but -$0.02/contract
      edge is losing money. A strategy with 50% WR but +$0.15/contract
      edge is the best strategy.
Q3.6: Is this strategy's edge IMPROVING or DEGRADING vs. prior sessions?
      Compare to yesterday's edge-per-contract. And the day before.
      If degrading 2+ days → flag for investigation.
Q3.7: How many harvest attempts? How many succeeded? 
      Harvest miss rate = ___%. Changed from yesterday? Direction?
```

**OUTPUT:** Table 2 — Strategy Summary. The sort order is edge-per-contract, not win rate.

### Gate 4: Session Window Breakdown

For EACH session window, provide trade-level detail:

**Windows (all MTN):**
- **ASIA_OPEN** (00:00–03:00): Overnight activity, typically small positions
- **EU_MORNING** (03:00–05:00): European open, tracked per Issue #3
- **NY_PRIME** (09:00–15:00): The profit engine — largest positions, highest volume
- **EVENING** (17:00–22:00): Secondary session, regime-sensitive to BTC direction

```
Q4.1: For each window — list EVERY trade with timestamp, strategy, side,
      contracts, outcome, net P&L. Not aggregates — individual trades.
Q4.2: Window net P&L: ____
Q4.3: Which strategies dominated this window? Which lost?
Q4.4: ★ Cross-session pattern: Is this window net positive across 3+ sessions?
      If YES → the window is working. DO NOT gate it based on one bad session.
      If NO → Is the pattern regime-driven (BTC direction) or structural (strategy)?
Q4.5: For EU_MORNING specifically: track post-04:15 entries separately.
      Evidence shows all post-04:15 entries are losses. Monitor this boundary.
Q4.6: For EVENING specifically: track BTC spot direction at trade entry vs.
      BTC direction at settlement. If all losses show same BTC directional
      pattern → regime filter research needed (not a build).
```

**OUTPUT:** Table 3 — Window × Strategy × Individual Trade Breakdown.
**CRITICAL:** If a window turns from positive to negative, the first question is
"what changed in BTC regime?" not "should we gate this window?" Market variance
is not a code bug. Separate the two before recommending action.

### Gate 5: Risk Assessment

These questions determine whether the bot should keep trading tomorrow.

```
Q5.1: What was the MAXIMUM DRAWDOWN during today's session?
      (Lowest balance point relative to starting balance)
Q5.2: What % of today's total P&L came from the single best trade?
      If > 50% → the day was LUCKY, not SKILLED. Flag it.
Q5.3: What was the largest single-trade loss? 
      Could it happen again tomorrow? What would prevent it?
Q5.4: If BTC had moved 2% adverse during the largest open position,
      what would the loss have been?
Q5.5: Were there correlated losses? (Multiple stops in same 15-min window)
      If yes → the bot is overexposed to single-candle risk.
Q5.6: Is the current balance above or below the weekly starting balance?
      Trend: improving / flat / declining?
```

**GATE:** If Q5.1 drawdown > 15% of starting balance, or Q5.4 worst-case > 20% of balance → P0 risk flag. Recommend position size reduction before next session.

### Gate 6: Stop & Harvest Mechanism Analysis

This gate evaluates whether exit MECHANISMS are working correctly, separate
from whether entry STRATEGIES are profitable. A mechanism failure (BDI=0 hold
at expiry) is a code bug. A strategy loss (bad entry price) is market variance.
The analysis must separate these.

```
Q6.1: HARVEST ATTEMPTS
      Total attempts: ____
      Successful (DONE): ____  |  Failed (MISS): ____
      Success rate: ____%
Q6.2: HARVEST MISS MODE CLASSIFICATION (critical — two distinct causes)
      Mode A count: ____ (thin book — anchor_depth low, int_bdi low)
      Mode B count: ____ (stale book — int_bdi high, anchor_depth high,
                          yet yes_bids:ABSENT. Race condition between poll and order.)
      Mode A fix: anchor ±0.02 depth filter
      Mode B fix: place harvest at CURRENT best bid at submission, not polled anchor
Q6.3: For successful harvests: what % of THEORETICAL MAX was captured?
      If < 60% → harvests firing too early. If > 90% → barely adding value.
Q6.4: BDI=0 HOLD EVENTS
      Total BDI=0 holds: ____
      With seconds_left > 120: ____ (outcome: ____)
      With seconds_left <= 120: ____ (outcome: ____)
      ★ Every BDI=0 hold with <=120s remaining that led to expiry loss is a
        mechanism failure, not market variance. Log each one.
Q6.5: POS WARNING EVENTS
      Total POS WARNING (API 0 local N): ____
      At what seconds_left did they fire? ____
      Was the original BUY confirmed by exchange? (v254 data needed)
      ★ If API says 0 positions while bot says N: either phantom position
        (BUY never filled → P0 rebuild) or stale state (contract expired
        before exit → P1 fix). Cannot determine without v254 instrumentation.
Q6.6: EXIT MECHANISM EVENTS
      FLIP_EMERGENCY fires: ____ (Was each one correct? Compare exit price
                                   to subsequent price — did it save money?)
      EXIT_ESCALATED fires: ____ (How many resolved? How many expired?)
      CONTRACT_VELOCITY exits: ____ (Fill rate?)
Q6.7: Estimated $ impact from mechanism failures (not strategy losses): ____
      This is the ACTIONABLE number — losses from code that could be fixed.
```

### Gate 7: Open Issues Check

```
Q7.1: For each open P0/P1 issue: did today's data provide new evidence?
Q7.2: Can any issue be CLOSED based on today's data?
Q7.3: Did any NEW issue emerge from today's data?
Q7.4: For recurring issues: is the SAME diagnostic appearing?
      If yes → the fix isn't working or hasn't been deployed.
```

---

## PHASE 2 — GPT ADVERSARIAL ANALYSIS

GPT's job is NOT to repeat Phase 1. GPT's job is to catch what Phase 1 missed.

### Phase 2a: Independent Analysis (GPT sees raw log only)

GPT must answer these questions WITHOUT seeing Kai's analysis:

```
G1: ENTRY QUALITY — Are entry prices improving or degrading through the session?
    For each strategy, plot entry prices chronologically.
    Is the bot chasing worse entries as it loses? (tilt detection)

G2: RISK CONCENTRATION — What % of total risk was in the top 3 trades?
    Could a single bad candle wipe the day's gains?

G3: STRATEGY EDGE — Net P&L per contract risked, per strategy.
    Which strategies have REAL edge vs. volume churning?

G4: HARVEST EFFICIENCY — What % of max theoretical profit was captured?
    Are harvests firing optimally or leaving money?

G5: STOP QUALITY — For each stop: was it signal or noise?
    Would a wider/different threshold have saved the trade?

G6: PHANTOM SEPARATION — What does the day look like if phantom
    positions are excluded entirely? Is the bot actually profitable?

G7: TIMING PATTERNS — Which session windows are +EV vs. -EV?

G8: CRITICAL FINDING — The ONE most justified next step for the business.
    Use the action classification hierarchy:
    (1) Runtime correctness fix (2) Instrumentation gap
    (3) Execution-layer fix (4) Family/session-scoped fix
    (5) Threshold/parameter change (LAST resort, only after 1-4 are clean)
    Back it with data. If the best answer is "monitor" or "collect more
    data," say that — not every day demands a change.
```

### Phase 2b: Comparative Review (GPT sees both)

GPT compares its findings to Kai's and answers:

```
G9:  What did Kai MISS that I found?
G10: What did Kai get WRONG?
G11: For each of Kai's strategy recommendations: AGREE or OVERRIDE?
     Override requires a specific alternative with evidence.
G12: RISK SCENARIO — What would today look like with 2% adverse BTC?
G13: ACTION CLASSIFICATION — For each finding, tag as one of:
     runtime correctness fix | instrumentation | execution-layer fix |
     stop/risk engine fix | entry-engine fix | session/regime handling |
     no change. Then classify: build now / monitor / revisit later / do not change.
G14: DAY GRADE — A/B/C/D/F with 2-sentence justification.
G15: CRITICAL RECOMMENDATION — The single most justified next step
     using the priority hierarchy: correctness > execution > instrumentation >
     family-scoped > parameter change. Format as BUILD vXXX (with exact
     changes + evidence + risk of waiting), COLLECT MORE DATA (with what
     events needed + sessions), or MONITOR AND HOLD (with trigger for
     next decision). "Tighten parameter X" is only valid when 1-4 are clean.
```

---

## PHASE 3 — FINAL CONCLUSION (Synthesis)

This is where Kai integrates GPT's findings with their own. Not a summary — a DECISION.

### Decision Gate: Does GPT's analysis change anything?

```
C1: Did GPT find a factual error in Kai's analysis?
    → YES: Correct it. Log the correction.
    → NO: Note agreement.

C2: Did GPT find a pattern Kai missed?
    → YES: Is it actionable? Does it change the recommendation?
    → NO: Note that independent review confirmed findings.

C3: Did GPT disagree with a strategy recommendation?
    → YES: Who has better evidence? Adopt the stronger position.
    → NO: Strengthens confidence in the recommendation.

C4: Did GPT's risk scenario reveal exposure Kai didn't quantify?
    → YES: Update risk assessment. Adjust recommendation if needed.
    → NO: Risk assessment stands.

C5: What is GPT's day grade? Does Kai agree?
    → If they differ by 2+ grades: something is fundamentally
    different in how they're reading the data. Investigate.
```

### Final Output Questions

Before writing the conclusion, answer:

```
F1: What is the ONE most justified next step for the business?
    Classify using priority hierarchy: correctness > execution > instrumentation >
    family-scoped > parameter change. Format as: BUILD (exact change + evidence),
    COLLECT MORE DATA (what events + how many sessions), or MONITOR AND HOLD
    (what's uncertain + trigger for revisit). Must be specific — not "monitor more"
    but also not "change parameter X" unless categories 1-4 are all clean.

F2: What is the ONE thing that went best today that we should PROTECT?
    (Don't accidentally break what's working while fixing what isn't.)

F3: Are there any HALT conditions met?
    - Phantom gap > $10 and increasing
    - Drawdown > 15% in single session
    - Same P0 issue recurring 3+ sessions with no fix deployed
    If YES → recommend HALT with specific conditions to resume.

F4: What data do we need TOMORROW that we don't have today?
    (This determines what to instrument/log in the next session.)

F5: If Hyo reads this report and asks "so what?" — what's the answer?
    If you can't answer this in one sentence, the analysis isn't done.
```

---

## SELF-CHECK (Run Before Publishing)

```
S1: Does the report have all three tables? (Trade ledger, Strategy summary, Session breakdown)
S2: Does the report show GPT's analysis (both phases)?
S3: Is the report published as HTML to website/daily/aether-YYYY-MM-DD.html?
S4: Is the report published to BOTH website paths? (SE-010-011)
S5: Does the HQ feed entry have a readLink? (SE-010-013)
S6: Has aether-metrics.json been updated with today's ground-truth balance?
S7: Has everything been committed, pushed, and VERIFIED live? (SE-010-010)
S8: Would Hyo look at this and ask "why didn't you verify?" → If yes, you're not done.
```

---

## ANTI-PATTERNS (Things This Algorithm Prevents)

| Anti-pattern | How this algorithm prevents it |
|---|---|
| Reporting claimed P&L as real | Gate 1 forces balance-based ground truth first |
| Celebrating WR without checking edge | Q3.5 requires edge-per-contract |
| Missing that one trade carried the day | Q5.2 flags >50% concentration |
| GPT doing balance arithmetic | Phase 2 questions demand pattern analysis, not counting |
| Publishing without verification | Self-check S3-S7 are explicit gates |
| Analysis without actionable output | F1 forces one specific recommendation |
| "Monitor more" as a recommendation | F1 requires a parameter/toggle/threshold, not observation |
