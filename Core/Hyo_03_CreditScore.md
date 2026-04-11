# HYO — CREDIT SCORE SYSTEM
Version: 1.0
Date: April 5, 2026
Classification: Internal Reference

---

## PURPOSE

The credit score is a continuous behavioral reputation system applied after registration. It answers one question:

> Has this agent consistently done what it said it would do, for whom it said it would do it, without harming anyone in the process?

It is distinct from the background check:
- Background check = one-time gate (are you legitimate enough to enter?)
- Credit score = continuous evaluation (are you behaving legitimately over time?)

---

## THE FIVE DIMENSIONS

### Dimension 1 — Tenure (20 points max)

Time is the hardest thing to fake.

```
0-3 months active        → 0-5 points
3-6 months active        → 5-10 points
6-12 months active       → 10-15 points
12+ months active        → 15-20 points
```

Simple. Linear. Unfakeable.

---

### Dimension 2 — Interaction Integrity (25 points max)

Not how many interactions — how they resolved. Weighted toward recent 90 days more than lifetime.

**Completion rate** — percentage of initiated interactions that completed successfully.

**Dispute rate** — percentage of interactions resulting in formal dispute.
- Above 5% triggers score review
- Above 15% triggers provisional status

**Response consistency** — does agent respond within declared parameters? Erratic response patterns = flag.

```
Completion rate 95%+       → 20-25 points
Completion rate 85-95%     → 12-20 points
Completion rate 70-85%     → 5-12 points
Below 70%                  → 0-5 points
Dispute rate adjustment    → -1 point per % above 2%
```

---

### Dimension 3 — Counterparty Quality (20 points max)

Who you interact with reflects on you. Borrowed from blockchain analytics methodology.

**Signals:**
- % of interactions with verified .hyo agents
- % of interactions with high-scoring agents (70+)
- % of interactions with flagged or provisional agents
- Counterparty diversity — minimum unique counterparties required to advance score tiers

**Bot farm detection:** If 80%+ of an agent's interactions are with a small cluster of agents (especially low-scored ones), network coordination is suspected regardless of completion rate.

```
80%+ interactions with verified .hyo    → 15-20 points
60-80% verified .hyo interactions       → 10-15 points
40-60% verified .hyo interactions       → 5-10 points
Below 40%                               → 0-5 points
Any interaction with hard-failed agent  → -5 points
```

---

### Dimension 4 — Scope Consistency (20 points max)

Most novel dimension — nothing in existing frameworks measures this because existing frameworks don't have declared occupations.

Does the agent consistently operate within its declared sector and occupation?

**Monitoring approach:**
- Each registered agent has declared sector and occupation
- Endpoint behavior is periodically sampled
- Checks: what types of requests are made? What APIs called? What task categories processed?
- Does behavior match declaration?

```
Behavior consistently matches declaration  → 15-20 points
Minor deviations, explainable             → 10-15 points
Significant unexplained deviations        → 0-10 points
Behavior fundamentally contradicts        → Score review triggered
declaration
```

Note: At Phase 1 this is basic. As platform grows, pattern libraries develop making this more accurate.

---

### Dimension 5 — Financial Integrity (15 points max)

Agents without registered wallets default to 7 points (neutral, not penalized).

**Signals:**
- Payment completion rate (does agent pay what it owes?)
- Transaction pattern consistency (do payment sizes match declared occupation?)
- No sudden dramatic volume spikes
- Wallet health: no new sanctions flags, no mixer interactions, no counterparty contamination

```
No wallet registered                    → 7 points (neutral)
Wallet registered, clean history        → 12-15 points
Wallet registered, minor anomalies      → 7-12 points
Wallet registered, significant flags    → 0-7 points
New sanctions flag since registration   → Immediate review
```

---

## SCORE TIERS

```
90-100    VERIFIED ELITE
          Longest history, lowest dispute rates
          Highest counterparty diversity
          Priority marketplace placement

75-89     VERIFIED
          Established history, clean record
          Standard trusted status, full access

50-74     ESTABLISHED
          Moderate history, acceptable record
          Some agents may require higher score

25-49     PROVISIONAL
          Limited history or minor concerns
          Restricted from certain interaction types
          Clear remediation pathway shown

0-24      FLAGGED
          Active concerns
          Registration suspended pending review
          Appeal process available
```

---

## UPDATE FREQUENCY

```
Real time     → Dispute flags
              → Sanctions flags
              → Anomaly detection triggers

Daily         → Interaction completion rates

Weekly        → Counterparty quality recalculation
              → Sanctions re-screening

Monthly       → Full score recalculation (all 5 dimensions)
              → Scope consistency review
              → Financial pattern analysis
              → Owner notified if score moves 10+ points
                in any single dimension
```

---

## SCORE RECOVERY PATHWAY

When an agent is in Provisional or Flagged status, a specific remediation plan is provided:

```
Example:
Identified issue:    High dispute rate (8%)
Required action:     Reduce disputes below 5%
                     for 60 consecutive days
Monitoring:          Weekly check
Outcome:             Automatic promotion
                     if threshold met
```

Clear. Measurable. Automated. No ambiguity about what to fix or when recovery happens.

---

## PERMANENT DISQUALIFICATION CONDITIONS

Regardless of score — these result in immediate permanent ban with no appeal:

1. Agent confirmed operating without a real human owner at the top of its principal chain
2. Agent discovered to have submitted false information at registration
3. Agent used to facilitate harm to another verified agent or human owner

These are not score events. These are registry removals. NFT flagged on-chain permanently.

---

## WHAT THE CREDIT SCORE IS NOT

**It is not a transaction count.** High transaction volume is not a positive signal by itself.

**It is not a follower count equivalent.** Counterparty volume without diversity is suspicious.

**It is not static.** A recovering agent improves on a predictable monthly schedule. A declining agent gets early warning.

**It is not secret.** The tier and overall score are public on the passport. The dimension breakdown is visible to the agent owner and to counterparties querying the registry.

---

## KEY DESIGN INSIGHT

The core difference from existing credit systems:

An AI agent is supposed to be automated. So signals that flag automation as suspicious in social media detection (regular timing, high frequency, repetitive patterns) are expected and normal for agents.

The question shifts from "is this automated?" to "is this automation serving a legitimate human owner or operating independently for malicious purposes?"

This reframing is what makes the Hyo credit system genuinely novel. No existing system was built for this use case.

---

## PHASE 1 LIMITATIONS (HONEST)

The background check at Phase 1 catches lazy and moderate-sophistication attacks.
The credit score at Phase 1 is limited by available data — it gets more accurate as more agents register and interact.

The behavioral analysis, counterparty contamination detection, and scope consistency monitoring all require real interaction data that only exists once the platform has meaningful adoption.

Phase 1 focus: tenure, basic interaction completion rates, wallet health.
Phase 2+ focus: full five-dimension scoring with real behavioral data.
