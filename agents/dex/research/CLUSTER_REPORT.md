# Dex Pattern Cluster Report
**Generated:** 2026-04-28
**Total entries analyzed:** 189
**Noise reduction:** 189 entries → 117 clusters (38.1% dedup rate)

## Signal Summary
- Multi-entry clusters: **7** (same root cause, different timestamps)
- Singleton clusters: **110** (unique issues)
- Recurring temporal patterns: **5**
- Highest-volume agent: **unknown**
- Largest cluster: **36 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| unknown | 44 |
| ra | 44 |
| sam | 36 |
| aether | 24 |
| dex | 13 |
| kai | 12 |
| nel | 12 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — 1 broken links detected
- **Size:** 36 entries | **Score:** 50.4 | **Agent:** unknown
- **Range:** 2026-04-19 → 2026-04-28
- **Status:** {'active': 36}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 2 — /api/usage returned HTTP 404
- **Size:** 10 entries | **Score:** 13.2 | **Agent:** sam
- **Range:** 2026-04-19 → 2026-04-21
- **Status:** {'resolved_fp': 10}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 3 — /api/hq?action=data returned HTTP 401
- **Size:** 10 entries | **Score:** 13.2 | **Agent:** sam
- **Range:** 2026-04-19 → 2026-04-21
- **Status:** {'resolved_fp': 10}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 4 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 10 entries | **Score:** 13.2 | **Agent:** ra
- **Range:** 2026-04-19 → 2026-04-21
- **Status:** {'resolved_fp': 10}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 5 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 7 entries | **Score:** 10.18 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-04-28
- **Status:** {'active': 7}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 6 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 4 entries | **Score:** 5.25 | **Agent:** dex
- **Range:** 2026-04-19 → 2026-04-22
- **Status:** {'active': 4}
- **Sample entries:**
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 215 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status

### Cluster 7 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 3.0 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 8 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 2.9 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 9 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 2.85 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

### Cluster 10 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 11 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 2.75 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 12 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 2.75 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 13 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 2.75 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 14 — Dual-path drift: all session 14 website changes committed to agents/sam/website/ only. Vercel deploy
- **Size:** 1 entries | **Score:** 2.5 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 15 — Service worker sw.js cached stale hq.html under hq-v1 forever. When Ant section was added (c1d8c85),
- **Size:** 1 entries | **Score:** 2.5 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| links broken detected | 36 | 6.0h | 100.0% | 2026-04-28 |
| api/usage http returned | 10 | 6.0h | 100.0% | 2026-04-21 |
| api/hq action http data | 10 | 6.0h | 100.0% | 2026-04-21 |
| code json aether html | 10 | 6.0h | 100.0% | 2026-04-21 |
| dex check patterns phase | 3 | 24.0h | 100.0% | 2026-04-21 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **1 broken links detected** (36 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **/api/usage returned HTTP 404** (10 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **/api/hq?action=data returned HTTP 401** (10 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (10 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (7 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (4 entries, dex)
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 215 recurrent patterns detected — check safeguard status

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s