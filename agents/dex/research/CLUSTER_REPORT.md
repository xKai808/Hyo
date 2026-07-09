# Dex Pattern Cluster Report
**Generated:** 2026-07-09
**Total entries analyzed:** 1087
**Noise reduction:** 1087 entries → 148 clusters (86.4% dedup rate)

## Signal Summary
- Multi-entry clusters: **9** (same root cause, different timestamps)
- Singleton clusters: **139** (unique issues)
- Recurring temporal patterns: **3**
- Highest-volume agent: **ra**
- Largest cluster: **404 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 450 |
| unknown | 316 |
| aether | 187 |
| dex | 53 |
| sam | 41 |
| kai | 23 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 404 entries | **Score:** 219.45 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-07-09
- **Status:** {'active': 404}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 291 entries | **Score:** 191.3 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-07-09
- **Status:** {'active': 291}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 164 entries | **Score:** 163.47 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-07-09
- **Status:** {'active': 164}
- **Sample entries:**
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

### Cluster 4 — hyo.world returned HTTP 000000
- **Size:** 34 entries | **Score:** 21.35 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'active': 34}
- **Sample entries:**
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000
  - /api/health returned HTTP 000000

### Cluster 5 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 22 entries | **Score:** 8.15 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-06-05
- **Status:** {'active': 22}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 6 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 10 entries | **Score:** 7.53 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-06-17
- **Status:** {'active': 10}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 7 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 4.65 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 8 — morning report generated but git push failed — report not live
- **Size:** 5 entries | **Score:** 2.7 | **Agent:** ra
- **Range:** 2026-05-05 → 2026-06-05
- **Status:** {'active': 5}
- **Sample entries:**
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

### Cluster 9 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 0.4 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 10 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 0.35 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 11 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 0.3 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 12 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 0.3 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 13 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 0.3 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

### Cluster 14 — Updated agents/sam/website/data/aether-metrics.json but website/ is a SEPARATE directory in git (not
- **Size:** 1 entries | **Score:** 0.3 | **Agent:** sam
- **Range:** 2026-04-14 → 2026-04-14
- **Status:** {'mitigated': 1}

### Cluster 15 — Analysis reports with all three tables and GPT sections existed as .txt files in agents/aether/analy
- **Size:** 1 entries | **Score:** 0.3 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-14
- **Status:** {'mitigated': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| aether playbook critical old | 164 | 6.0h | 96.6% | 2026-07-09 |
| http returned api/health | 17 | 6.1h | 99.8% | 2026-06-05 |
| http returned world hyo | 17 | 6.1h | 99.8% | 2026-06-05 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (404 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (291 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **aether PLAYBOOK.md is 15d old (>14d critical)** (164 entries, aether)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

- **hyo.world returned HTTP 000000** (34 entries, sam)
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (22 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **morning-report pushed to git but not visible live — check Vercel deploy** (10 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **Daily audit: 5 critical issues found** (16 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **morning report generated but git push failed — report not live** (5 entries, ra)
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s