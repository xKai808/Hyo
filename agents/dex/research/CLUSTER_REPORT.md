# Dex Pattern Cluster Report
**Generated:** 2026-06-04
**Total entries analyzed:** 647
**Noise reduction:** 647 entries → 149 clusters (77.0% dedup rate)

## Signal Summary
- Multi-entry clusters: **10** (same root cause, different timestamps)
- Singleton clusters: **139** (unique issues)
- Recurring temporal patterns: **4**
- Highest-volume agent: **ra**
- Largest cluster: **257 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 301 |
| unknown | 170 |
| dex | 52 |
| aether | 48 |
| sam | 36 |
| kai | 23 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 257 entries | **Score:** 274.6 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-06-04
- **Status:** {'active': 257}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 152 entries | **Score:** 152.45 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-06-04
- **Status:** {'active': 152}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 25 entries | **Score:** 35.85 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-06-04
- **Status:** {'active': 25}
- **Sample entries:**
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

### Cluster 4 — hyo.world returned HTTP 000000
- **Size:** 20 entries | **Score:** 29.6 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-04
- **Status:** {'active': 20}
- **Sample entries:**
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000
  - /api/health returned HTTP 000000

### Cluster 5 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 21 entries | **Score:** 24.63 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-06-03
- **Status:** {'active': 21}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 6 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 17.9 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 7 — /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
- **Size:** 10 entries | **Score:** 14.8 | **Agent:** sam
- **Range:** 2026-06-01 → 2026-06-04
- **Status:** {'resolved_fp': 6, 'active': 4}
- **Sample entries:**
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

### Cluster 8 — morning report generated but git push failed — report not live
- **Size:** 3 entries | **Score:** 3.75 | **Agent:** ra
- **Range:** 2026-05-05 → 2026-06-03
- **Status:** {'active': 3}
- **Sample entries:**
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

### Cluster 9 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 2 entries | **Score:** 2.42 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-05-26
- **Status:** {'active': 2}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 10 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 1.3 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 11 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 1.3 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 12 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 1.27 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 13 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 1.23 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 14 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 1.2 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 15 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 1.18 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| aether old playbook critical | 25 | 6.1h | 99.5% | 2026-06-04 |
| http api/health returned | 10 | 6.1h | 100.0% | 2026-06-04 |
| expected api/hq data http | 10 | 6.1h | 100.0% | 2026-06-04 |
| http hyo returned world | 10 | 6.1h | 100.0% | 2026-06-04 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (257 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (152 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **aether PLAYBOOK.md is 15d old (>14d critical)** (25 entries, aether)
  - aether PLAYBOOK.md is 15d old (>14d critical)
  - aether PLAYBOOK.md is 15d old (>14d critical)

- **hyo.world returned HTTP 000000** (20 entries, sam)
  - /api/health returned HTTP 000000
  - hyo.world returned HTTP 000000

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (21 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **Daily audit: 5 critical issues found** (16 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **/api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)** (10 entries, sam)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)
  - /api/hq?action=data returned unexpected HTTP 000000 (expected 200 or 401)

- **morning report generated but git push failed — report not live** (3 entries, ra)
  - morning report generated but git push failed — report not live
  - morning report generated but git push failed — report not live

- **morning-report pushed to git but not visible live — check Vercel deploy** (2 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s