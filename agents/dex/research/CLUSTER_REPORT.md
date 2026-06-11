# Dex Pattern Cluster Report
**Generated:** 2026-06-11
**Total entries analyzed:** 770
**Noise reduction:** 770 entries → 149 clusters (80.6% dedup rate)

## Signal Summary
- Multi-entry clusters: **10** (same root cause, different timestamps)
- Singleton clusters: **139** (unique issues)
- Recurring temporal patterns: **4**
- Highest-volume agent: **ra**
- Largest cluster: **297 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 343 |
| unknown | 205 |
| aether | 76 |
| dex | 53 |
| sam | 53 |
| kai | 23 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 297 entries | **Score:** 286.3 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-06-11
- **Status:** {'active': 297}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 180 entries | **Score:** 165.75 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-06-11
- **Status:** {'active': 180}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 53 entries | **Score:** 71.38 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-06-11
- **Status:** {'active': 53}
- **Sample entries:**
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

### Cluster 4 — hyo.world returned HTTP 000000
- **Size:** 34 entries | **Score:** 45.15 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'active': 34}
- **Sample entries:**
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000
  - /api/health returned HTTP 000000

### Cluster 5 — /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
- **Size:** 17 entries | **Score:** 22.57 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'resolved_fp': 17}
- **Sample entries:**
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

### Cluster 6 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 22 entries | **Score:** 22.32 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-06-05
- **Status:** {'active': 22}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 7 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 15.1 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 8 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 5 entries | **Score:** 6.5 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-06-10
- **Status:** {'active': 5}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 9 — morning report generated but git push failed — report not live
- **Size:** 5 entries | **Score:** 5.95 | **Agent:** ra
- **Range:** 2026-05-05 → 2026-06-05
- **Status:** {'active': 5}
- **Sample entries:**
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

### Cluster 10 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 1.1 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 11 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 1.05 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 12 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 1.0 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 13 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 1.0 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

### Cluster 14 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 0.95 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 15 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 0.95 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| critical playbook old aether | 53 | 6.0h | 99.4% | 2026-06-11 |
| http returned api/health | 17 | 6.1h | 99.8% | 2026-06-05 |
| api/hq action http data | 17 | 6.1h | 99.8% | 2026-06-05 |
| http returned hyo world | 17 | 6.1h | 99.8% | 2026-06-05 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (297 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (180 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **aether PLAYBOOK.md is 15d old (>14d critical)** (53 entries, aether)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

- **hyo.world returned HTTP 000000** (34 entries, sam)
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000

- **/api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)** (17 entries, sam)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (22 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **Daily audit: 5 critical issues found** (16 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **morning-report pushed to git but not visible live — check Vercel deploy** (5 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **morning report generated but git push failed — report not live** (5 entries, ra)
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s