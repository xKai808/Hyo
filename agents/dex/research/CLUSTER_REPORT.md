# Dex Pattern Cluster Report
**Generated:** 2026-04-23
**Total entries analyzed:** 278
**Noise reduction:** 278 entries → 129 clusters (53.6% dedup rate)

## Signal Summary
- Multi-entry clusters: **11** (same root cause, different timestamps)
- Singleton clusters: **118** (unique issues)
- Recurring temporal patterns: **3**
- Highest-volume agent: **ra**
- Largest cluster: **32 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 75 |
| sam | 64 |
| unknown | 37 |
| dex | 37 |
| aether | 25 |
| nel | 19 |
| kai | 16 |
| ant | 5 |

## Top Issue Clusters (by impact score)

### Cluster 1 — /api/hq?action=data returned HTTP 401
- **Size:** 32 entries | **Score:** 43.58 | **Agent:** sam
- **Range:** 2026-04-13 → 2026-04-21
- **Status:** {'resolved_fp': 32}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 2 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 27 entries | **Score:** 37.25 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-21
- **Status:** {'resolved_fp': 27}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 3 — 5 broken links detected
- **Size:** 21 entries | **Score:** 30.28 | **Agent:** unknown
- **Range:** 2026-04-13 → 2026-04-23
- **Status:** {'active': 21}
- **Sample entries:**
  - 5 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 4 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 20 entries | **Score:** 26.35 | **Agent:** dex
- **Range:** 2026-04-13 → 2026-04-22
- **Status:** {'active': 20}
- **Sample entries:**
  - Dex Phase 4: 13 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 59 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 86 recurrent patterns detected — check safeguard status

### Cluster 5 — No newsletter produced for 2026-04-12 — past 06:00 MT deadline
- **Size:** 19 entries | **Score:** 24.02 | **Agent:** ra
- **Range:** 2026-04-13 → 2026-04-15
- **Status:** {'active': 19}
- **Sample entries:**
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline

### Cluster 6 — /api/usage returned HTTP 404
- **Size:** 14 entries | **Score:** 20.05 | **Agent:** sam
- **Range:** 2026-04-18 → 2026-04-21
- **Status:** {'resolved_fp': 14}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 7 — agents/nel/security is NOT gitignored
- **Size:** 11 entries | **Score:** 14.13 | **Agent:** nel
- **Range:** 2026-04-13 → 2026-04-15
- **Status:** {'resolved_fp': 11}
- **Sample entries:**
  - agents/nel/security is NOT gitignored
  - agents/nel/security is NOT gitignored
  - agents/nel/security is NOT gitignored

### Cluster 8 — Dex Phase 1 FAILED: 1 JSONL files have corrupt entries
- **Size:** 10 entries | **Score:** 12.7 | **Agent:** dex
- **Range:** 2026-04-13 → 2026-04-14
- **Status:** {'active': 10}
- **Sample entries:**
  - Dex Phase 1 FAILED: 1 JSONL files have corrupt entries
  - Dex Phase 1 FAILED: 2 JSONL files have corrupt entries
  - Dex Phase 1 FAILED: 2 JSONL files have corrupt entries

### Cluster 9 — Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive summary without re-
- **Size:** 2 entries | **Score:** 3.9 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-14
- **Status:** {'mitigated': 2}
- **Sample entries:**
  - Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive
  - Rewrote analysis executive summaries without re-sending to GPT for verification.

### Cluster 10 — Kai built single-phase GPT pipeline (send finished analysis for review) instead of Hyo's specified d
- **Size:** 2 entries | **Score:** 3.9 | **Agent:** ra
- **Range:** 2026-04-14 → 2026-04-14
- **Status:** {'mitigated': 2}
- **Sample entries:**
  - Kai built single-phase GPT pipeline (send finished analysis for review) instead 
  - Built single-phase GPT pipeline (send finished analysis for review = rubber stam

### Cluster 11 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 3.0 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 12 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 3.0 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 13 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 3.0 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 14 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 3.0 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 15 — Bare YYYY-MM-DD.html filenames cause Vercel 404 for current date. Prefixed filenames (newsletter-DAT
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** aether
- **Range:** 2026-04-18 → 2026-04-18
- **Status:** {'resolved': 1}

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| exists code aether json | 27 | 6.9h | 60.2% | 2026-04-21 |
| api/usage returned http | 14 | 6.0h | 98.8% | 2026-04-21 |
| gitignored agents/nel/security | 11 | 5.7h | 69.6% | 2026-04-15 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **/api/hq?action=data returned HTTP 401** (32 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (27 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **5 broken links detected** (21 entries, unknown)
  - 5 broken links detected
  - 1 broken links detected

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (20 entries, dex)
  - Dex Phase 4: 13 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 59 recurrent patterns detected — check safeguard status

- **No newsletter produced for 2026-04-12 — past 06:00 MT deadline** (19 entries, ra)
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-12 — past 06:00 MT deadline

- **/api/usage returned HTTP 404** (14 entries, sam)
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