# Dex Pattern Cluster Report
**Generated:** 2026-06-02
**Total entries analyzed:** 591
**Noise reduction:** 591 entries → 149 clusters (74.8% dedup rate)

## Signal Summary
- Multi-entry clusters: **9** (same root cause, different timestamps)
- Singleton clusters: **140** (unique issues)
- Recurring temporal patterns: **1**
- Highest-volume agent: **ra**
- Largest cluster: **245 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 287 |
| unknown | 154 |
| dex | 50 |
| aether | 40 |
| kai | 23 |
| sam | 20 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 245 entries | **Score:** 269.0 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-06-02
- **Status:** {'active': 245}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 144 entries | **Score:** 147.75 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-06-02
- **Status:** {'active': 144}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 17 entries | **Score:** 24.8 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-06-02
- **Status:** {'active': 17}
- **Sample entries:**
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

### Cluster 4 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 19 entries | **Score:** 22.6 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-06-01
- **Status:** {'active': 19}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 5 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 18.7 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 6 — hyo.world returned HTTP 000000
- **Size:** 4 entries | **Score:** 6.0 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-02
- **Status:** {'active': 4}
- **Sample entries:**
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000
  - /api/health returned HTTP 000000

### Cluster 7 — /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
- **Size:** 2 entries | **Score:** 3.0 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-02
- **Status:** {'active': 2}
- **Sample entries:**
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

### Cluster 8 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 2 entries | **Score:** 2.53 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-05-26
- **Status:** {'active': 2}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 9 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 1.4 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 10 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 1.4 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 11 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 1.32 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 12 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 1.3 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 13 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 1.27 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 14 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 1.23 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 15 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 1.23 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| critical playbook aether old | 17 | 6.0h | 99.6% | 2026-06-02 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (245 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (144 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **aether PLAYBOOK.md is 15d old (>14d critical)** (17 entries, aether)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (19 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **Daily audit: 5 critical issues found** (16 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **hyo.world returned HTTP 000000** (4 entries, sam)
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000

- **/api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)** (2 entries, sam)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

- **morning-report pushed to git but not visible live — check Vercel deploy** (2 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s