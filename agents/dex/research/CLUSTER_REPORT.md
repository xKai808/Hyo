# Dex Pattern Cluster Report
**Generated:** 2026-05-29
**Total entries analyzed:** 532
**Noise reduction:** 532 entries → 147 clusters (72.4% dedup rate)

## Signal Summary
- Multi-entry clusters: **6** (same root cause, different timestamps)
- Singleton clusters: **141** (unique issues)
- Recurring temporal patterns: **0**
- Highest-volume agent: **ra**
- Largest cluster: **227 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 269 |
| unknown | 136 |
| dex | 47 |
| aether | 24 |
| kai | 23 |
| sam | 16 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 227 entries | **Score:** 265.3 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-05-29
- **Status:** {'active': 227}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 128 entries | **Score:** 137.15 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-05-29
- **Status:** {'active': 128}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — Daily audit: 5 critical issues found
- **Size:** 16 entries | **Score:** 20.3 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-28
- **Status:** {'active': 16}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 4 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 16 entries | **Score:** 19.85 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-05-29
- **Status:** {'active': 16}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 5 — morning-report pushed to git but not visible live — check Vercel deploy
- **Size:** 2 entries | **Score:** 2.72 | **Agent:** sam
- **Range:** 2026-05-19 → 2026-05-26
- **Status:** {'active': 2}
- **Sample entries:**
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

### Cluster 6 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 1.6 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 7 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 1.6 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 8 — aether PLAYBOOK.md is 15d old (>14d critical)
- **Size:** 1 entries | **Score:** 1.5 | **Agent:** aether
- **Range:** 2026-05-29 → 2026-05-29
- **Status:** {'active': 1}

### Cluster 9 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 1.5 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 10 — Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTER
- **Size:** 1 entries | **Score:** 1.42 | **Agent:** kai
- **Range:** 2026-05-25 → 2026-05-25
- **Status:** {'active': 1}

### Cluster 11 — Daily audit 2026-05-23: hyo-inbox.jsonl flooded to 52,616 lines / 14.7MB (52,588 SLA-breach auto-spa
- **Size:** 1 entries | **Score:** 1.38 | **Agent:** dex
- **Range:** 2026-05-23 → 2026-05-23
- **Status:** {'active': 1}

### Cluster 12 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 1.35 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 13 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 1.32 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 14 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 1.32 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

### Cluster 15 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 1.3 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (227 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (128 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **Daily audit: 5 critical issues found** (16 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (16 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **morning-report pushed to git but not visible live — check Vercel deploy** (2 entries, sam)
  - morning-report pushed to git but not visible live — check Vercel deploy
  - morning-report pushed to git but not visible live — check Vercel deploy

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s