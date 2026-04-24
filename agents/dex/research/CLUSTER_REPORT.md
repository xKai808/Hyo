# Dex Pattern Cluster Report
**Generated:** 2026-04-24
**Total entries analyzed:** 186
**Noise reduction:** 186 entries → 105 clusters (43.5% dedup rate)

## Signal Summary
- Multi-entry clusters: **5** (same root cause, different timestamps)
- Singleton clusters: **100** (unique issues)
- Recurring temporal patterns: **3**
- Highest-volume agent: **sam**
- Largest cluster: **24 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| sam | 51 |
| ra | 46 |
| unknown | 31 |
| aether | 23 |
| dex | 13 |
| kai | 12 |
| nel | 6 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — 1 broken links detected
- **Size:** 24 entries | **Score:** 34.5 | **Agent:** unknown
- **Range:** 2026-04-18 → 2026-04-24
- **Status:** {'active': 24}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 2 — /api/hq?action=data returned HTTP 401
- **Size:** 21 entries | **Score:** 28.92 | **Agent:** sam
- **Range:** 2026-04-15 → 2026-04-21
- **Status:** {'resolved_fp': 21}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 3 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 21 entries | **Score:** 28.92 | **Agent:** ra
- **Range:** 2026-04-15 → 2026-04-21
- **Status:** {'resolved_fp': 21}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 4 — /api/usage returned HTTP 404
- **Size:** 14 entries | **Score:** 19.7 | **Agent:** sam
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'resolved_fp': 14}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 5 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 6 entries | **Score:** 8.3 | **Agent:** dex
- **Range:** 2026-04-16 → 2026-04-22
- **Status:** {'active': 6}
- **Sample entries:**
  - Dex Phase 4: 162 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 175 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status

### Cluster 6 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 2.95 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 7 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 2.95 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 8 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 2.95 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 9 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 2.95 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 10 — Bare YYYY-MM-DD.html filenames cause Vercel 404 for current date. Prefixed filenames (newsletter-DAT
- **Size:** 1 entries | **Score:** 2.75 | **Agent:** aether
- **Range:** 2026-04-18 → 2026-04-18
- **Status:** {'resolved': 1}

### Cluster 11 — Dual-path drift: all session 14 website changes committed to agents/sam/website/ only. Vercel deploy
- **Size:** 1 entries | **Score:** 2.7 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 12 — Service worker sw.js cached stale hq.html under hq-v1 forever. When Ant section was added (c1d8c85),
- **Size:** 1 entries | **Score:** 2.7 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 13 — Clean URL /hq not in network-first branch — service worker isDataOrPage check used endsWith(.html) b
- **Size:** 1 entries | **Score:** 2.7 | **Agent:** ra
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 14 — Claimed ant was deployed and working based on: (a) code was in hq.html, (b) Vercel MCP showed READY 
- **Size:** 1 entries | **Score:** 2.7 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 15 — Aether metrics 15-min refresh (extract_aether_metrics_from_logs) only updated balance. Did NOT updat
- **Size:** 1 entries | **Score:** 2.65 | **Agent:** aether
- **Range:** 2026-04-16 → 2026-04-16
- **Status:** {'resolved': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| detected links broken | 24 | 6.0h | 99.1% | 2026-04-24 |
| http returned api/usage | 14 | 6.0h | 98.8% | 2026-04-21 |
| phase detected check dex | 5 | 30.0h | 65.4% | 2026-04-21 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **1 broken links detected** (24 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **/api/hq?action=data returned HTTP 401** (21 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (21 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **/api/usage returned HTTP 404** (14 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (6 entries, dex)
  - Dex Phase 4: 162 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 175 recurrent patterns detected — check safeguard status