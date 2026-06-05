# Dex Pattern Cluster Report
**Generated:** 2026-06-05
**Total entries analyzed:** 676
**Noise reduction:** 676 entries → 149 clusters (78.0% dedup rate)

## Signal Summary
- Multi-entry clusters: **10** (same root cause, different timestamps)
- Singleton clusters: **139** (unique issues)
- Recurring temporal patterns: **4**
- Highest-volume agent: **ra**
- Largest cluster: **265 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 310 |
| unknown | 178 |
| dex | 52 |
| aether | 52 |
| sam | 44 |
| kai | 23 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 265 entries | **Score:** 280.18 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-06-05
- **Status:** {'active': 265}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 156 entries | **Score:** 154.65 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-06-05
- **Status:** {'active': 156}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 29 entries | **Score:** 41.23 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-06-05
- **Status:** {'active': 29}
- **Sample entries:**
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

### Cluster 4 — hyo.world returned HTTP 000000
- **Size:** 28 entries | **Score:** 41.1 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'active': 28}
- **Sample entries:**
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000
  - /api/health returned HTTP 000000

### Cluster 5 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 21 entries | **Score:** 24.1 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-06-03
- **Status:** {'active': 21}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 6 — /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
- **Size:** 14 entries | **Score:** 20.55 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'resolved_fp': 10, 'active': 4}
- **Sample entries:**
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

### Cluster 7 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 17.5 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 8 — morning report generated but git push failed — report not live
- **Size:** 4 entries | **Score:** 5.17 | **Agent:** ra
- **Range:** 2026-05-05 → 2026-06-04
- **Status:** {'active': 4}
- **Sample entries:**
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

### Cluster 9 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 2 entries | **Score:** 2.38 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-05-26
- **Status:** {'active': 2}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 10 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 1.25 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 11 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 1.25 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 12 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 1.25 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 13 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 1.2 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 14 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 1.15 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 15 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 1.15 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| aether old critical playbook | 29 | 6.1h | 99.5% | 2026-06-05 |
| returned http api/health | 14 | 6.1h | 100.0% | 2026-06-05 |
| api/hq expected action http | 14 | 6.1h | 100.0% | 2026-06-05 |
| returned http world hyo | 14 | 6.1h | 100.0% | 2026-06-05 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (265 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (156 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **aether PLAYBOOK.md is 15d old (>14d critical)** (29 entries, aether)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

- **hyo.world returned HTTP 000000** (28 entries, sam)
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (21 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **/api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)** (14 entries, sam)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

- **Daily audit: 5 critical issues found** (16 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **morning report generated but git push failed — report not live** (4 entries, ra)
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

- **morning-report pushed to git but not visible live — check Vercel deploy** (2 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s