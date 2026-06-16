# Dex Pattern Cluster Report
**Generated:** 2026-06-16
**Total entries analyzed:** 838
**Noise reduction:** 838 entries → 149 clusters (82.2% dedup rate)

## Signal Summary
- Multi-entry clusters: **10** (same root cause, different timestamps)
- Singleton clusters: **139** (unique issues)
- Recurring temporal patterns: **4**
- Highest-volume agent: **ra**
- Largest cluster: **322 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 368 |
| unknown | 225 |
| aether | 96 |
| sam | 56 |
| dex | 53 |
| kai | 23 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 322 entries | **Score:** 285.43 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-06-16
- **Status:** {'active': 322}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 200 entries | **Score:** 172.35 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-06-16
- **Status:** {'active': 200}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 73 entries | **Score:** 93.75 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-06-16
- **Status:** {'active': 73}
- **Sample entries:**
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

### Cluster 4 — hyo.world returned HTTP 000000
- **Size:** 34 entries | **Score:** 40.9 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'active': 34}
- **Sample entries:**
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000
  - /api/health returned HTTP 000000

### Cluster 5 — /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
- **Size:** 17 entries | **Score:** 20.45 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-05
- **Status:** {'resolved_fp': 17}
- **Sample entries:**
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

### Cluster 6 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 22 entries | **Score:** 19.65 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-06-05
- **Status:** {'active': 22}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 7 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 13.1 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 8 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 8 entries | **Score:** 10.2 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-06-15
- **Status:** {'active': 8}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 9 — morning report generated but git push failed — report not live
- **Size:** 5 entries | **Score:** 5.33 | **Agent:** ra
- **Range:** 2026-05-05 → 2026-06-05
- **Status:** {'active': 5}
- **Sample entries:**
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

### Cluster 10 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 0.98 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 11 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 0.93 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 12 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 0.87 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 13 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 0.87 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

### Cluster 14 — Daily audit 2026-05-18: verified-state.json + session-handoff.json + dispatch-transcripts all 12-18 
- **Size:** 1 entries | **Score:** 0.8 | **Agent:** kai
- **Range:** 2026-05-18 → 2026-05-18
- **Status:** {'active': 1}

### Cluster 15 — Daily audit: Ra newsletter pipeline silent 3 days (no .input.md for 5/17; 5/16 partial; ra-002/003/0
- **Size:** 1 entries | **Score:** 0.77 | **Agent:** ra
- **Range:** 2026-05-17 → 2026-05-17
- **Status:** {'active': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| critical playbook old aether | 73 | 6.0h | 99.4% | 2026-06-16 |
| api/health returned http | 17 | 6.1h | 99.8% | 2026-06-05 |
| action data http expected | 17 | 6.1h | 99.8% | 2026-06-05 |
| returned hyo http world | 17 | 6.1h | 99.8% | 2026-06-05 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (322 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (200 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **aether PLAYBOOK.md is 15d old (>14d critical)** (73 entries, aether)
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

- **morning-report pushed to git but not visible live — check Vercel deploy** (8 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **morning report generated but git push failed — report not live** (5 entries, ra)
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s