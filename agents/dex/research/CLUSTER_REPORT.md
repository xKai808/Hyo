# Dex Pattern Cluster Report
**Generated:** 2026-04-27
**Total entries analyzed:** 186
**Noise reduction:** 186 entries → 111 clusters (40.3% dedup rate)

## Signal Summary
- Multi-entry clusters: **7** (same root cause, different timestamps)
- Singleton clusters: **104** (unique issues)
- Recurring temporal patterns: **5**
- Highest-volume agent: **ra**
- Largest cluster: **34 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 41 |
| unknown | 41 |
| sam | 40 |
| aether | 25 |
| dex | 13 |
| kai | 12 |
| nel | 10 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — 1 broken links detected
- **Size:** 34 entries | **Score:** 47.8 | **Agent:** unknown
- **Range:** 2026-04-18 → 2026-04-27
- **Status:** {'active': 34}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 2 — /api/hq?action=data returned HTTP 401
- **Size:** 13 entries | **Score:** 17.35 | **Agent:** sam
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'resolved_fp': 13}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 3 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 13 entries | **Score:** 17.35 | **Agent:** ra
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'resolved_fp': 13}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 4 — /api/usage returned HTTP 404
- **Size:** 12 entries | **Score:** 16.05 | **Agent:** sam
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'resolved_fp': 12}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 5 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 4 entries | **Score:** 5.78 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-04-25
- **Status:** {'active': 4}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 6 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 4 entries | **Score:** 5.35 | **Agent:** dex
- **Range:** 2026-04-19 → 2026-04-22
- **Status:** {'active': 4}
- **Sample entries:**
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 215 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status

### Cluster 7 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 2.95 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 8 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 2.9 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

### Cluster 9 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 10 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 11 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 12 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 13 — Bare YYYY-MM-DD.html filenames cause Vercel 404 for current date. Prefixed filenames (newsletter-DAT
- **Size:** 1 entries | **Score:** 2.6 | **Agent:** aether
- **Range:** 2026-04-18 → 2026-04-18
- **Status:** {'resolved': 1}

### Cluster 14 — Dual-path drift: all session 14 website changes committed to agents/sam/website/ only. Vercel deploy
- **Size:** 1 entries | **Score:** 2.55 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 15 — Service worker sw.js cached stale hq.html under hq-v1 forever. When Ant section was added (c1d8c85),
- **Size:** 1 entries | **Score:** 2.55 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| links broken detected | 34 | 6.0h | 100.0% | 2026-04-27 |
| api/hq http data returned | 13 | 6.0h | 99.6% | 2026-04-21 |
| exists aether json html | 13 | 6.0h | 99.6% | 2026-04-21 |
| api/usage http returned | 12 | 6.0h | 100.0% | 2026-04-21 |
| detected phase check patterns | 3 | 24.0h | 100.0% | 2026-04-21 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **1 broken links detected** (34 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **/api/hq?action=data returned HTTP 401** (13 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (13 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **/api/usage returned HTTP 404** (12 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (4 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (4 entries, dex)
  - Dex Phase 4: 209 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 215 recurrent patterns detected — check safeguard status

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s