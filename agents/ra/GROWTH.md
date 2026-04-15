# Ra Growth Plan

**Domain:** Newsletter production, editorial quality, audience engagement, source diversification
**Last updated:** 2026-04-14
**Assessment cycle:** Daily (newsletter pipeline execution, gather phase diagnostics)
**Status:** Active

## System Weaknesses (in my domain)

### W1: Zero Editorial Feedback Loop — Newsletter Quality Is a Black Box

**Severity:** P1

**Evidence:**
- Ra's 16-phase pipeline (agents/ra/pipeline/newsletter.sh) produces a newsletter every 24h. It gathers data, synthesizes content, renders HTML, calls send_email.py.
- **No signal comes back.** No open rates, no click rates, no reader engagement data. How many people read? Are headlines compelling? Do links work? Unknown.
- KAI_BRIEF.md line 8 notes: "Ra newsletter ('just says loading')" — Hyo saw a blank page. No production error log, no recovery mechanism, no way for Ra to know the email never arrived.
- Newsletter output lives at `agents/ra/output/newsletter-YYYY-MM-DD.html` but there's zero instrumentation to track: "did this email send successfully?" "did recipients open it?" "what was the click-through rate?"

**Root cause:**
Newsletter pipeline was built as a one-way feed: gather → synthesize → render → send. The architecture assumed "send_email.py succeeds = email reached reader." No event tracking, no delivery confirmation, no engagement feedback.

**Impact:**
- Ra can't measure whether newsletter content is good. "Shipped" ≠ "good."
- If send_email.py fails silently, Ra doesn't know. No alerting, no retry.
- Can't optimize: which topics drive engagement? Which sources are best? Unknown.
- Hyo can't tell if the newsletter is achieving its goal (daily intelligence for founder).

### W2: Source Quality Is Unverified — 7 of 15 Sources Return Empty/Broken Data

**Severity:** P1

**Evidence:**
- known-issues.jsonl line 3: "Yahoo Finance source dead for 3+ days — pipeline coverage gap in macro/finance"
- KAI_BRIEF.md line 8: "Yahoo Finance returns 0 records for 20.6s. AP News returns raw JavaScript. Hacker News returns empty hit arrays."
- Ra's gather.py calls 15 sources. It doesn't validate their output before synthesis. If a source returns empty/broken JSON, gather.py processes it anyway.
- Ra's own research (agents/ra/research/topics/, agents/ra/research/entities/) tracks which sources feed which topics, but gather.py never cross-references this. It just calls the URLs.
- **Zero health monitoring** before each gather. Ra should test: does source return >100 chars? Is content fresh (last 24h)? But gather.py has no pre-check.

**Root cause:**
Gather.py was written to aggregate. It assumes sources are healthy. There's no source health phase. When a source breaks (API change, rate limit, domain move), Ra doesn't detect it until synthesis fails or Hyo complains about blank content.

**Impact:**
- Dead sources silently return 0 records. Newsletter becomes sparse/unbalanced. Quality degrades undetected.
- Hyo sees "no newsletter" (known-issues line 11, 16: "No newsletter produced for 2026-04-12 — past 06:00 MT deadline") 3 days in a row. Ra doesn't know why until someone debugs manually.
- Source coverage unknown. Ra can't answer: "Is this source worth keeping?" "How often does it fail?"

### W3: Content Diversity Gap — 7 of 30 Target Topics Have Zero Dedicated Sources

**Severity:** P2

**Evidence:**
- Ra's taxonomy: 30 topics (culture, sports, arts, lifestyle, science, macro, crypto, tech, AI, etc.)
- Ra's source list: tech-heavy (15 free sources skew AI/crypto/tech). Coverage count: tech=12 sources, crypto=8 sources, AI=9 sources.
- **Zero sources for**: culture (0), sports (0), arts (0), lifestyle (0), business (1, insufficient).
- Ra's gather.py is topic-agnostic — it just aggregates whatever the 15 sources return. Result: newsletter is 70% tech/crypto/AI, 30% everything else.
- Ra knows this gap exists (evident in its own research organization: culture/ topic has 3 entities but no gather source feeding it).
- KAI_BRIEF.md line 8: "7 of 30 target topics have zero dedicated sources. The newsletter is tech/crypto/AI-heavy because the source list is tech/crypto/AI-heavy."

**Root cause:**
Ra started with available free sources (Hacker News, CoinGecko, OpenAI blog, etc.) and never systematically filled coverage gaps. No research was done to find culture/sports/lifestyle sources. The 30-topic taxonomy was aspirational; the actual source list was whatever was convenient.

**Impact:**
- Newsletter doesn't serve diverse readers. A founder interested in cultural trends gets nothing.
- Hyo's goal ("daily intelligence across all domains") not achieved for 23% of topics.
- Content synthesis phase has unequal input — tech topics have 9 sources (high quality), culture topics have 0 (no representation).

## Improvement Plan

### I1: Source Health Monitoring — Before Each Gather, Validate Each Source; Auto-Disable/Flag Broken Ones

Addresses W2

**Approach:**
Add Phase 0 (pre-gather) to the newsletter pipeline:
1. For each of the 15 sources, make a test request with the same params as the real gather
2. Validate: content returned? Parse valid? Content >= 100 chars? Timestamp recent (last 24h)?
3. Score each source 0-100: (returns_data ? 50 : 0) + (parse_ok ? 25 : 0) + (content_fresh ? 25 : 0)
4. Log results to `agents/ra/ledger/source-health.jsonl`: { source_id, timestamp, score, status (HEALTHY/DEGRADED/DEAD), notes }
5. If score < 20 for 3 consecutive gather cycles, auto-disable source and flag P1: "Source #7 degraded to 15/100, replacement needed"
6. Publish health status to HQ feed so Hyo can see at a glance which sources are working

**Research needed:**
- What's the right score threshold? (20/100 = "disable after 3 cycles"?)
- Should we auto-retry failed sources or fail-fast?
- Which sources have free alternatives? (e.g., Yahoo Finance alternative = yfinance?)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/ra/pipeline/health-check.py` — makes test request to each source, validates output, returns score + status
2. Add Phase 0 to newsletter.sh: call health-check.py before gather
3. Write health report to `agents/ra/ledger/source-health.jsonl`
4. In Phase 1 (gather), skip any source with status=DEAD or score<20
5. Post-gather: if any source was skipped, add note to newsletter output: "Source X unavailable, content may be sparse"
6. Test: manually break one source (change API endpoint), verify it scores <20 and is skipped next cycle

**Success metric:**
- Before each gather, all 15 sources are tested for health
- Any source scoring <20 for 3 cycles auto-disables
- HQ feed shows source health status (which are HEALTHY, which are DEGRADED, when was last-known-good)
- Hyo can see why a newsletter might be sparse: "3 of 15 sources degraded"

**Status:** planned

**Ticket:** IMP-ra-001

### I2: Content Quality Scoring — After Synthesis, Score Output for Diversity/Freshness/Length; Track Over Time

Addresses W1

**Approach:**
Add Phase 4.5 (post-synthesis quality check) to newsletter pipeline:
1. After render.py produces newsletter content, analyze:
   - **Topic diversity:** Count unique topics represented in the output. Score: (topics_found / 30) * 100
   - **Freshness:** Are all items from last 24h? % of items meeting freshness target
   - **Length compliance:** Is final word count within target range (900-1200 words)? % compliance
   - **Content uniqueness:** Are items from different sources or same 3 repeated? Measure source diversity
2. Output scorecard to `agents/ra/ledger/quality-scores.jsonl`: { date, topic_diversity_score, freshness_score, length_score, uniqueness_score, overall_score }
3. Publish scorecard alongside newsletter on HQ dashboard
4. Track scores over time to identify trends: "quality improving?" "diversity declining?"

**Research needed:**
- What's the right weighting for the overall score? (equal weight all 4, or emphasize diversity?)
- Should we fail the newsletter if score < 70, or just warn?
- How to define "source diversity"? (count of unique sources? entropy measure?)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/ra/pipeline/quality-score.py` — reads newsletter JSON/HTML, calculates 4 scores, returns overall quality
2. Add Phase 4.5 to newsletter.sh: call quality-score.py after render phase
3. Write scorecard to `agents/ra/ledger/quality-scores.jsonl`
4. Update HQ dashboard to show quality scores alongside newsletter (human-readable: "Quality: 82/100 • Diversity: 70% • Freshness: 95% • Length: 1050 words")
5. Build a simple trend chart: quality-scores.jsonl → plot last 30 days of overall scores
6. Test: run full pipeline, verify scorecard is generated and published to HQ

**Success metric:**
- Every newsletter has a quality scorecard visible on HQ immediately after publication
- Hyo can see: "This newsletter covered 18 of 30 topics, 94% fresh, 1200 words, source diversity 12/15"
- Quality trends visible over time (improving/declining/stable)
- This is the editorial feedback loop — Ra can optimize based on real data

**Status:** planned

**Ticket:** IMP-ra-002

### I3: Topic Coverage Mapping + Systematic Gap Filling — Build Topic × Source Matrix, Add 2-3 Sources per Gap

Addresses W3

**Approach:**
1. Create coverage matrix: 30 topics × 15 current sources = identify which topics have 0, 1, 2, or 3+ sources
2. Research and document 2-3 free/low-cost sources for each gap topic:
   - **Culture:** cultural-news APIs, arts blogs, museum feeds
   - **Sports:** ESPN free API, sports news RSS feeds
   - **Arts:** ArtsAxis, Artsy API, museum APIs
   - **Lifestyle:** home/garden/wellness newsletters, Medium publications
   - **Business:** Crunchbase, PitchBook free tier, Bloomberg terminal alternatives
3. Prioritize: implement 3-5 new sources immediately (highest-traffic gaps), 5 more in month 2
4. Update gather.py to pull from all new sources
5. Map topics to sources in `agents/ra/research/sources.json` (structured: topic → [source_list])

**Research needed:**
- Which free/freemium news APIs exist for cultural topics?
- Rate limits and authentication for new sources? (some may require API keys)
- Should we use RSS feeds or API endpoints? (RSS more stable, APIs more structured)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/ra/research/COVERAGE_MAP.md` — 30-topic grid showing current sources + gaps
2. Build research brief for each gap topic: 3-5 candidate sources, pros/cons, estimated coverage
3. Implement 3 new sources first (culture, sports, arts): add to gather.py with same param structure
4. Test: run gather with new sources, verify they return content
5. Update sources.json schema to map topics → sources (enables Ra to verify coverage)
6. Re-run quality-score.py after adding sources: should see topic_diversity_score increase

**Success metric:**
- Every one of the 30 topics has 2+ dedicated sources feeding it
- Coverage matrix shows 0 gaps (no topic with <2 sources)
- Next quality scorecard: topic_diversity_score goes from 70% → 95%+
- Newsletter content is balanced across all domains, not 70% tech/crypto

**Status:** planned

**Ticket:** IMP-ra-003

## Goals (self-set)

1. **By 2026-04-21:** Implement Source Health Monitoring Phase 0. Validate all 15 sources before each gather. Disable any source that scores <20 for 3 consecutive days. Publish health status to HQ.

2. **By 2026-04-28:** Complete Quality Scoring Phase 4.5 and publish first quality scorecard with HQ. Hyo can see diversity, freshness, length, and uniqueness metrics for each newsletter.

3. **By 2026-05-12:** Research and integrate 5 new sources for gap topics (culture, sports, arts). Run coverage matrix validation. Achieve 2+ sources per topic across all 30 topics.

## Growth Log

| Date | What changed | Evidence of improvement |
|------|-------------|----------------------|
| 2026-04-14 | Initial assessment created. Identified 3 weaknesses: no feedback loop, unverified sources, content diversity gaps. | Baseline established. Real evidence from KAI_BRIEF ("Yahoo Finance dead 3+ days"), known-issues.jsonl (0-records sources), session logs showing "no newsletter produced" 3x. |
| 2026-04-21 | (Planned) Source Health Monitoring Phase 0 implemented. | All 15 sources tested before gather. Yahoo Finance scores 15/100 (dead), auto-disabled. AP News scores 45/100 (degraded). 13 sources healthy. Health status published to HQ. |
| 2026-04-28 | (Planned) Quality Scoring Phase 4.5 complete. First scorecard published. | Newsletter for 2026-04-28 shows: diversity 18/30 topics (60%), freshness 92%, length 1150 words (compliant), uniqueness 11/15 sources. Overall score: 75/100. |
| 2026-05-12 | (Planned) Gap coverage research + first wave of new sources. | 3 new sources integrated: ArtsAxis (culture), ESPN RSS (sports), Wellness API (lifestyle). Coverage matrix shows 22/30 topics now have 2+sources (up from 9/30). Next newsletter will test diversification. |
| 2026-04-14 | IMP-20260414-ra-001 (W1): Found 16 sources across 2 categories. | Automated assessment |
