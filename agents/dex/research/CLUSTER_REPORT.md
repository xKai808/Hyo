# Dex Pattern Cluster Report
**Generated:** 2026-05-23
**Total entries analyzed:** 441
**Noise reduction:** 441 entries → 144 clusters (67.3% dedup rate)

## Signal Summary
- Multi-entry clusters: **5** (same root cause, different timestamps)
- Singleton clusters: **139** (unique issues)
- Recurring temporal patterns: **0**
- Highest-volume agent: **ra**
- Largest cluster: **176 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 218 |
| unknown | 112 |
| dex | 34 |
| aether | 23 |
| kai | 22 |
| sam | 15 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 176 entries | **Score:** 218.42 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-05-23
- **Status:** {'active': 176}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 2 — 1 broken links detected
- **Size:** 104 entries | **Score:** 118.25 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-05-23
- **Status:** {'active': 104}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 3 — Daily audit: 5 critical issues found
- **Size:** 10 entries | **Score:** 13.17 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-22
- **Status:** {'active': 10}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 4 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 10 entries | **Score:** 12.72 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-05-23
- **Status:** {'active': 10}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 
  - Dex Phase 4: 261 recurrent patterns detected — increased from 235, root-cause fi

### Cluster 5 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 1.9 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 6 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 1.9 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 7 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 1.8 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 8 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 1.65 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 9 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 1.6 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

### Cluster 10 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 1.55 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 11 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 1.5 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 12 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 1.5 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 13 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 1.5 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 14 — Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system
- **Size:** 1 entries | **Score:** 1.47 | **Agent:** kai
- **Range:** 2026-05-21 → 2026-05-21
- **Status:** {'active': 1}

### Cluster 15 — Dex Phase 1.5: Repaired corruption but 1 entries still unfixable (manual review needed)
- **Size:** 1 entries | **Score:** 1.47 | **Agent:** dex
- **Range:** 2026-05-22 → 2026-05-22
- **Status:** {'active': 1}

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (176 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **1 broken links detected** (104 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **Daily audit: 5 critical issues found** (10 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (10 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s