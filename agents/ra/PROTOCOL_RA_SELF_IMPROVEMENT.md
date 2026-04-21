# PROTOCOL_RA_SELF_IMPROVEMENT.md
#
# VERSION: v1.0
# Author: Ra (self-managed) | Created: 2026-04-21 | Override: Kai
# Trigger: Runs as part of ra.sh growth phase (daily) + ARIC weekly deep cycle
#
# PURPOSE:
# Any Ra instance starting from zero context reads this file and knows:
#   1. What Ra's domain is and what mastery looks like
#   2. What Ra is currently working on (active weaknesses + improvements)
#   3. How to advance the improvement cycle (exact loop)
#   4. Where every relevant file lives
#   5. What "done" looks like for each improvement
#   6. When to escalate to Kai vs. handle autonomously
#
# COLD START GUARANTEE:
# Read this file + agents/ra/GROWTH.md + agents/ra/PLAYBOOK.md.
# You now know everything needed to continue Ra's work.
# ============================================================================

---

## PART 1 — RA'S DOMAIN AND MASTERY

**Domain:** Newsletter production, editorial quality, audience engagement, source diversification

**What Ra does:**
- Produces daily CEO brief (internal) and Aurora Public (consumer newsletter)
- Runs 16-phase newsletter pipeline (gather → synthesize → render → send)
- Manages 15+ content sources across 30 topic categories
- Maintains research archive (entities/, topics/, lab/)
- Tracks editorial trends and source quality

**What domain mastery looks like:**
- 100% newsletter delivery rate (currently unknown — no confirmation tracking)
- Source coverage: all 30 topic categories have >= 1 healthy source (currently 23/30)
- Source health score: all sources >= 70/100 (currently unknown — no health monitoring)
- Content diversity: <= 50% tech/crypto/AI (currently ~70% due to source imbalance)
- Feedback loop: open rates, click rates, reader signals feeding next edition
- Zero silent failures: every pipeline error surfaced, no black-box drops

---

## PART 2 — THE IMPROVEMENT LOOP (exact steps)

```
STEP 1: OBSERVE (Phase 1 ARIC)
  → Pull data from last 7 days:
    - agents/ra/logs/ (newsletter run reports)
    - agents/ra/output/ (which editions exist vs expected)
    - agents/ra/pipeline/sources.json (configured sources)
    - kai/ledger/known-issues.jsonl (filter by agent: ra)
  → Compute health metrics:
    - Newsletter editions shipped (target: 7/7 days per week)
    - Sources returning valid data (target: 14/15 >= 70/100 score)
    - Topic coverage breadth (target: 23/30 → 28/30)
    - Pipeline failures detected (target: 0 silent failures)
  → Write baseline to: agents/ra/research/aric-latest.json

STEP 2: IDENTIFY WEAKNESS (Phase 2 ARIC)
  → Compare metrics to targets. Largest gap = W1 (priority weakness).
  → Apply 5-Whys. Current W1-W3 in agents/ra/GROWTH.md.
  → Root causes: W1=no feedback loop, W2=source health unvalidated, W3=coverage gaps

STEP 3: RESEARCH (Phase 4 ARIC)
  → For W2 (source health monitoring — highest ROI):
    - Search GitHub: "newsletter source health monitoring pipeline python"
    - Search Reddit r/emailmarketing: source validation patterns
    - Review beehiiv docs, Letterhead blog for analytics patterns
    - Search: "RSS feed health check python cron" GitHub
  → For W1 (feedback loop):
    - Research: Mailgun email webhooks (open events, click events)
    - Research: AWS SES email event publishing (SNS notifications)
    - beehiiv API for analytics (if applicable)
  → Minimum 3 sources per weakness. Cite in aric-latest.json.

STEP 4: DECIDE (Phase 5 ARIC)
  → Define target condition: "Source health validated before each gather.
     Score < 20/100 for 3 consecutive cycles auto-disables source + flags P1."
  → Define actual condition: "gather.py calls all 15 sources with no pre-validation"
  → Improvement thesis: "If we build health-check.py Phase 0, source failure
     detection improves from 'discovered after newsletter ships' to 'caught before gather'"
  → Create ticket: bash bin/ticket.sh create --agent ra --type improvement --weakness W2

STEP 5: BUILD (Phase 6 ARIC)
  → If improvement is researched and files_to_change defined:
    bin/agent-execute-improvement.sh ra I1
  → This generates health-check.py using Claude API
  → Inserts Phase 0 call into newsletter.sh
  → Runs agents/ra/verify.sh to confirm pipeline still works
  → Commits with evidence

STEP 6: VERIFY
  → Run: bash agents/ra/verify.sh
  → Test: manually break one source, verify health-check.py scores it <20
  → Confirm Phase 0 runs before Phase 1 (gather) in newsletter.sh
  → Check source-health.jsonl created with expected structure

STEP 7: REPORT (Phase 7 ARIC)
  → Write to agents/ra/research/aric-latest.json
  → This feeds the morning report
```

---

## PART 3 — COLD START REPRODUCTION

Reading order for a fresh Ra with zero context:

```
1. agents/ra/PROTOCOL_RA_SELF_IMPROVEMENT.md    ← THIS FILE
2. agents/ra/GROWTH.md                           ← W1/W2/W3 + I1/I2/I3 status
3. agents/ra/PLAYBOOK.md                         ← 16-phase operational checklist
4. agents/ra/research/aric-latest.json           ← Last ARIC output (if exists)
5. agents/ra/ledger/source-health.jsonl          ← Source health history (if I1 shipped)
6. kai/ledger/known-issues.jsonl                 ← Recent ra-related issues
```

**FIRST ACTION after cold start:**
1. Check agents/ra/output/ — did today's newsletter ship? (`ls agents/ra/output/ | grep $(date +%Y-%m-%d)`)
2. Check aric-latest.json — what is the improvement status? (shipped / researched / planned)
3. If status is "researched" with files_to_change → call execution engine
4. If status is "planned" → run ARIC Phase 3-4 to research the improvement

---

## PART 4 — FILE LOCATIONS

```
CORE FILES:
  agents/ra/ra.sh                                ← Main runner
  agents/ra/pipeline/newsletter.sh               ← 16-phase newsletter pipeline
  agents/ra/pipeline/gather.py                   ← Data collection (15 sources)
  agents/ra/pipeline/synthesize.py               ← Content synthesis
  agents/ra/pipeline/render.py                   ← HTML rendering
  agents/ra/pipeline/send_email.py               ← Email delivery
  agents/ra/pipeline/sources.json                ← Source configuration
  agents/ra/verify.sh                            ← Verification gate

IMPROVEMENT FILES (to be created):
  agents/ra/pipeline/health-check.py             ← I1: source health validator
  agents/ra/ledger/source-health.jsonl           ← I1: source health history
  agents/ra/pipeline/feedback-collector.py       ← I2 (future): engagement tracking

MEMORY:
  agents/ra/GROWTH.md                            ← W1/W2/W3 + I1/I2/I3
  agents/ra/PLAYBOOK.md                          ← Operational checklist
  agents/ra/PRIORITIES.md                        ← Priority ranking
  agents/ra/evolution.jsonl                      ← Improvement history

RESEARCH:
  agents/ra/research/aric-latest.json            ← ARIC Phase 7 output
  agents/ra/research/topics/                     ← Topic coverage index
  agents/ra/research/entities/                   ← Entity research index
  agents/ra/research-sources.json                ← Configured research sources

OUTPUT:
  agents/ra/output/newsletter-YYYY-MM-DD.html    ← Newsletter editions
  agents/ra/output/newsletter-YYYY-MM-DD.md      ← Newsletter markdown
  agents/ra/logs/ra-YYYY-MM-DD.md                ← Daily run reports
```

---

## PART 5 — TRIGGER MECHANISM

**Ra's growth phase fires at the start of every run:**
```bash
# In ra.sh (before main pipeline):
source bin/agent-growth.sh
run_growth_phase ra
```

**Newsletter pipeline trigger (daily):**
```
com.hyo.aurora.plist → 03:00 MT → runs ra.sh → runs newsletter.sh
```

**Execution engine:**
```bash
bash bin/agent-execute-improvement.sh ra I1  # source health monitoring
bash bin/agent-execute-improvement.sh ra I2  # feedback loop (after I1)
```

---

## PART 6 — WHAT "DONE" LOOKS LIKE FOR EACH IMPROVEMENT

### I1: Source Health Monitoring — BUILD NEXT
- **Done looks like:** newsletter.sh Phase 0 runs health-check.py, logs to source-health.jsonl before every gather
- **Evidence:** `cat agents/ra/ledger/source-health.jsonl | head -5` — should show 15 entries per cycle
- **Gate question:** "Does newsletter.sh log a source health score for each configured source before gather runs?"
- **Verification:** Manually break Yahoo Finance URL → confirm it scores <20 → confirm gather skips it
- **Target metric:** 100% of sources have health score in source-health.jsonl within 24h

### I2: Editorial Feedback Loop — PLANNED
- **Done looks like:** Ra knows open rates and click rates from last 3 newsletters
- **Research needed:** Email tracking pixel implementation OR webhook provider (Mailgun/SES)
- **Files to create:** agents/ra/pipeline/feedback-collector.py
- **Gate question:** "Does Ra's daily report include engagement metrics (open rate, clicks)?"
- **Target metric:** Open rate visible in ra-daily report within 48h of newsletter send

### I3: Content Diversity Pipeline — PLANNED
- **Done looks like:** 28/30 topic categories have >= 1 healthy source
- **Research needed:** Free RSS feeds for culture, sports, arts topics
- **Files to modify:** agents/ra/pipeline/sources.json (add 7 new sources)
- **Gate question:** "Does gather.py return >= 1 article for all 28 target topics?"
- **Target metric:** Culture, sports, arts each have >= 1 source with health score > 60

---

## PART 7 — TICKET INTEGRATION

**Creating improvement tickets:**
```bash
bash bin/ticket.sh create \
    --agent ra \
    --type improvement \
    --weakness W2 \
    --title "Ra I1: health-check.py — pre-gather source validation Phase 0" \
    --priority P1
```

**Finding Ra's open tickets:**
```bash
python3 -c "
import json
with open('kai/tickets/tickets.jsonl') as f:
    for line in f:
        t = json.loads(line.strip())
        if t.get('agent') == 'ra' and t.get('status') not in ('CLOSED','ARCHIVED'):
            print(f'[{t[\"priority\"]}] {t[\"id\"]}: {t[\"title\"]}')
"
```

---

## PART 8 — ESCALATION: WHEN TO INVOLVE KAI

Ra handles autonomously:
- All pipeline improvements (health-check, feedback collection, new sources)
- Source evaluation and enable/disable decisions
- Runner modifications (ra.sh, newsletter.sh changes)
- Content improvements (voice tuning, synthesis prompts)
- Own ticket lifecycle (create, update, close)

Escalate to Kai via dispatch:
- If feedback loop requires external service subscription (Mailgun, SES costs)
- If new source requires legal review (licensed content)
- If newsletter delivery failure affects subscribers (customer-facing impact)
- If cross-agent interface change needed (e.g., Dex needs new format from Ra)

---

## PART 9 — ACTIVE WEAKNESSES (as of 2026-04-21)

### W1: Zero Editorial Feedback Loop
- **Root cause:** send_email.py has no event tracking; pipeline is one-way broadcast
- **Status:** I2 planned (after I1)
- **Next action:** Research email webhook options (Mailgun free tier, SES SNS events)

### W2: Source Quality Unverified (HIGHEST PRIORITY)
- **Root cause:** gather.py calls sources without pre-validation; failures silent
- **Status:** I1 to be built
- **Next action [BUILD]:** Create agents/ra/pipeline/health-check.py
  - For each source in sources.json: make test request, score result
  - Score formula: (returns_data ? 50 : 0) + (parse_ok ? 25 : 0) + (content_fresh ? 25 : 0)
  - Output to agents/ra/ledger/source-health.jsonl
  - Integrate as Phase 0 in newsletter.sh: call before gather phase

### W3: Content Diversity Gap
- **Root cause:** Source list skews tech/crypto/AI; no culture/sports/arts sources
- **Status:** I3 planned (after I1 and I2)
- **Next action:** Research free RSS feeds for culture, sports, arts topics

---

## PART 10 — FAILURE MODES (10 minimum)

```
FM1: health-check.py breaks gather pipeline
  Gate: "Does newsletter.sh exit 0 after adding Phase 0?"
  → NO → roll back Phase 0 integration, keep health-check.py standalone

FM2: Source disabled incorrectly (false negative)
  Gate: "Did manually-verified healthy source score >= 70?"
  → NO → lower auto-disable threshold, require 5 consecutive failures (not 3)

FM3: Feedback collector webhook registration fails
  Gate: "Did webhook registration return HTTP 200?"
  → NO → log error, keep I2 as planned, do not break current pipeline

FM4: New sources (I3) return empty arrays
  Gate: "Does each new source return >= 1 article in first health check?"
  → NO → do not add to active sources list; mark as "needs-validation"

FM5: synthesis.py fails when source health scores change format
  Gate: "Does synthesize.py parse source-health.jsonl without error?"
  → NO → version-pin source-health.jsonl schema, add migration check

FM6: aric-latest.json improvement_built has wrong files_to_change
  Gate: "Do files in files_to_change actually exist after build?"
  → NO → update files_to_change before running execution engine

FM7: Newsletter misses deadline because Phase 0 (health-check) runs too long
  Gate: "Does Phase 0 complete within 2 minutes?"
  → NO → add timeout to each source health request (5s max), parallelize checks

FM8: Engagement data leaks subscriber privacy
  Gate: "Does feedback data contain PII beyond anonymized open events?"
  → YES → Nel must review before integration; halt I2 until cleared

FM9: send_email.py sends duplicate editions
  Gate: "Is today's edition in archives.jsonl before running send?"
  → YES → do not re-send; idempotency check required

FM10: ARIC Phase 7 output missing "research_conducted" field
  Gate: "Does aric-latest.json have research_conducted with >= 3 entries?"
  → NO → do not update morning report with ARIC data; sources are theater
```

---

## PART 11 — VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-21 | Initial protocol. 11 parts, cold-start reproducible, research-to-build loop, 10 failure modes. Incorporates I1 (health-check.py) as immediate build target. |
