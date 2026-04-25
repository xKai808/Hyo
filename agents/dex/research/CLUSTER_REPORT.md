# Dex Pattern Cluster Report
**Generated:** 2026-04-25
**Total entries analyzed:** 187
**Noise reduction:** 187 entries → 109 clusters (41.7% dedup rate)

## Signal Summary
- Multi-entry clusters: **6** (same root cause, different timestamps)
- Singleton clusters: **103** (unique issues)
- Recurring temporal patterns: **3**
- Highest-volume agent: **sam**
- Largest cluster: **28 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| sam | 47 |
| ra | 45 |
| unknown | 35 |
| aether | 24 |
| dex | 12 |
| kai | 12 |
| nel | 8 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — 1 broken links detected
- **Size:** 28 entries | **Score:** 39.9 | **Agent:** unknown
- **Range:** 2026-04-18 → 2026-04-25
- **Status:** {'active': 28}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 2 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 17 entries | **Score:** 23.27 | **Agent:** ra
- **Range:** 2026-04-16 → 2026-04-21
- **Status:** {'resolved_fp': 17}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 3 — /api/hq?action=data returned HTTP 401
- **Size:** 16 entries | **Score:** 21.97 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-21
- **Status:** {'resolved_fp': 16}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 4 — /api/usage returned HTTP 404
- **Size:** 14 entries | **Score:** 19.35 | **Agent:** sam
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'resolved_fp': 14}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 5 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 5 entries | **Score:** 6.87 | **Agent:** dex
- **Range:** 2026-04-18 → 2026-04-22
- **Status:** {'active': 5}
- **Sample entries:**
  - Dex Phase 4: 175 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 215 recurrent patterns detected — check safeguard status

### Cluster 6 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 4 entries | **Score:** 5.97 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-04-25
- **Status:** {'active': 4}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 7 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 3.0 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

### Cluster 8 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 2.9 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 9 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 2.9 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 10 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 2.9 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 11 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 2.9 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 12 — Bare YYYY-MM-DD.html filenames cause Vercel 404 for current date. Prefixed filenames (newsletter-DAT
- **Size:** 1 entries | **Score:** 2.7 | **Agent:** aether
- **Range:** 2026-04-18 → 2026-04-18
- **Status:** {'resolved': 1}

### Cluster 13 — Dual-path drift: all session 14 website changes committed to agents/sam/website/ only. Vercel deploy
- **Size:** 1 entries | **Score:** 2.65 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 14 — Service worker sw.js cached stale hq.html under hq-v1 forever. When Ant section was added (c1d8c85),
- **Size:** 1 entries | **Score:** 2.65 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 15 — Clean URL /hq not in network-first branch — service worker isDataOrPage check used endsWith(.html) b
- **Size:** 1 entries | **Score:** 2.65 | **Agent:** ra
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| broken detected links | 28 | 6.0h | 99.1% | 2026-04-25 |
| http api/usage returned | 14 | 6.0h | 98.8% | 2026-04-21 |
| phase dex patterns detected | 4 | 24.0h | 100.0% | 2026-04-21 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **1 broken links detected** (28 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **Aether metrics JSON exists but hq.html has NO rendering code** (17 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **/api/hq?action=data returned HTTP 401** (16 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **/api/usage returned HTTP 404** (14 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (5 entries, dex)
  - Dex Phase 4: 175 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (4 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline