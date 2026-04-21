# Dex Pattern Cluster Report
**Generated:** 2026-04-21
**Total entries analyzed:** 255
**Noise reduction:** 255 entries → 117 clusters (54.1% dedup rate)

## Signal Summary
- Multi-entry clusters: **11** (same root cause, different timestamps)
- Singleton clusters: **106** (unique issues)
- Recurring temporal patterns: **2**
- Highest-volume agent: **ra**
- Largest cluster: **31 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 70 |
| sam | 60 |
| dex | 36 |
| unknown | 28 |
| aether | 23 |
| nel | 19 |
| kai | 15 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — /api/hq?action=data returned HTTP 401
- **Size:** 31 entries | **Score:** 28.97 | **Agent:** sam
- **Range:** 2026-04-13 → 2026-04-21
- **Status:** {'active': 31}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 2 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 26 entries | **Score:** 24.6 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-21
- **Status:** {'active': 26}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 3 — Dex Phase 4: 13 recurrent patterns detected — check safeguard status
- **Size:** 19 entries | **Score:** 17.22 | **Agent:** dex
- **Range:** 2026-04-13 → 2026-04-21
- **Status:** {'active': 19}
- **Sample entries:**
  - Dex Phase 4: 13 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 59 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 86 recurrent patterns detected — check safeguard status

### Cluster 4 — No newsletter produced for 2026-04-12 — past 06:00 MT deadline
- **Size:** 19 entries | **Score:** 16.65 | **Agent:** ra
- **Range:** 2026-04-13 → 2026-04-15
- **Status:** {'active': 19}
- **Sample entries:**
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline

### Cluster 5 — 5 broken links detected
- **Size:** 14 entries | **Score:** 13.63 | **Agent:** unknown
- **Range:** 2026-04-13 → 2026-04-21
- **Status:** {'active': 14}
- **Sample entries:**
  - 5 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 6 — /api/usage returned HTTP 404
- **Size:** 13 entries | **Score:** 12.75 | **Agent:** sam
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'active': 13}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 7 — agents/nel/security is NOT gitignored
- **Size:** 11 entries | **Score:** 9.73 | **Agent:** nel
- **Range:** 2026-04-13 → 2026-04-15
- **Status:** {'active': 11}
- **Sample entries:**
  - agents/nel/security is NOT gitignored
  - agents/nel/security is NOT gitignored
  - agents/nel/security is NOT gitignored

### Cluster 8 — Dex Phase 1 FAILED: 1 JSONL files have corrupt entries
- **Size:** 10 entries | **Score:** 8.8 | **Agent:** dex
- **Range:** 2026-04-13 → 2026-04-14
- **Status:** {'active': 10}
- **Sample entries:**
  - Dex Phase 1 FAILED: 1 JSONL files have corrupt entries
  - Dex Phase 1 FAILED: 2 JSONL files have corrupt entries
  - Dex Phase 1 FAILED: 2 JSONL files have corrupt entries

### Cluster 9 — Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive summary without re-
- **Size:** 2 entries | **Score:** 3.6 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-14
- **Status:** {'mitigated': 2}
- **Sample entries:**
  - Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive
  - Rewrote analysis executive summaries without re-sending to GPT for verification.

### Cluster 10 — Kai built single-phase GPT pipeline (send finished analysis for review) instead of Hyo's specified d
- **Size:** 2 entries | **Score:** 3.6 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-14
- **Status:** {'mitigated': 2}
- **Sample entries:**
  - Kai built single-phase GPT pipeline (send finished analysis for review) instead 
  - Built single-phase GPT pipeline (send finished analysis for review = rubber stam

### Cluster 11 — Bare YYYY-MM-DD.html filenames cause Vercel 404 for current date. Prefixed filenames (newsletter-DAT
- **Size:** 1 entries | **Score:** 2.9 | **Agent:** aether
- **Range:** 2026-04-18 → 2026-04-18
- **Status:** {'resolved': 1}

### Cluster 12 — Dual-path drift: all session 14 website changes committed to agents/sam/website/ only. Vercel deploy
- **Size:** 1 entries | **Score:** 2.85 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 13 — Service worker sw.js cached stale hq.html under hq-v1 forever. When Ant section was added (c1d8c85),
- **Size:** 1 entries | **Score:** 2.85 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 14 — Clean URL /hq not in network-first branch — service worker isDataOrPage check used endsWith(.html) b
- **Size:** 1 entries | **Score:** 2.85 | **Agent:** ra
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

### Cluster 15 — Claimed ant was deployed and working based on: (a) code was in hq.html, (b) Vercel MCP showed READY 
- **Size:** 1 entries | **Score:** 2.85 | **Agent:** sam
- **Range:** 2026-04-17 → 2026-04-17
- **Status:** {'unknown': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| http api/usage returned | 13 | 6.0h | 98.8% | 2026-04-21 |
| gitignored agents/nel/security | 11 | 5.7h | 69.6% | 2026-04-15 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **/api/hq?action=data returned HTTP 401** (31 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (26 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **Dex Phase 4: 13 recurrent patterns detected — check safeguard status** (19 entries, dex)
  - Dex Phase 4: 13 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 59 recurrent patterns detected — check safeguard status

- **No newsletter produced for 2026-04-12 — past 06:00 MT deadline** (19 entries, ra)
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline

- **5 broken links detected** (14 entries, unknown)
  - 5 broken links detected
  - 1 broken links detected

- **/api/usage returned HTTP 404** (13 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **agents/nel/security is NOT gitignored** (11 entries, nel)
  - agents/nel/security is NOT gitignored
  - agents/nel/security is NOT gitignored

- **Dex Phase 1 FAILED: 1 JSONL files have corrupt entries** (10 entries, dex)
  - Dex Phase 1 FAILED: 1 JSONL files have corrupt entries
  - Dex Phase 1 FAILED: 2 JSONL files have corrupt entries

- **Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive summary without re-** (2 entries, ra)
  - Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive
  - Rewrote analysis executive summaries without re-sending to GPT for verification.

- **Kai built single-phase GPT pipeline (send finished analysis for review) instead of Hyo's specified d** (2 entries, ra)
  - Kai built single-phase GPT pipeline (send finished analysis for review) instead 
  - Built single-phase GPT pipeline (send finished analysis for review = rubber stam