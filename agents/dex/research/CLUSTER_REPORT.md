# Dex Pattern Cluster Report
**Generated:** 2026-05-05
**Total entries analyzed:** 205
**Noise reduction:** 205 entries → 129 clusters (37.1% dedup rate)

## Signal Summary
- Multi-entry clusters: **7** (same root cause, different timestamps)
- Singleton clusters: **122** (unique issues)
- Recurring temporal patterns: **3**
- Highest-volume agent: **ra**
- Largest cluster: **38 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 64 |
| unknown | 46 |
| sam | 26 |
| aether | 23 |
| kai | 16 |
| dex | 13 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — 1 broken links detected
- **Size:** 38 entries | **Score:** 48.0 | **Agent:** unknown
- **Range:** 2026-04-20 → 2026-05-01
- **Status:** {'active': 38}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 2 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 24 entries | **Score:** 32.97 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-05-05
- **Status:** {'active': 24}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 3 — /api/hq?action=data returned HTTP 401
- **Size:** 6 entries | **Score:** 6.95 | **Agent:** sam
- **Range:** 2026-04-20 → 2026-04-21
- **Status:** {'resolved_fp': 6}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 4 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 6 entries | **Score:** 6.95 | **Agent:** ra
- **Range:** 2026-04-20 → 2026-04-21
- **Status:** {'resolved_fp': 6}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 5 — /api/usage returned HTTP 404
- **Size:** 5 entries | **Score:** 5.8 | **Agent:** sam
- **Range:** 2026-04-20 → 2026-04-21
- **Status:** {'resolved_fp': 5}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

### Cluster 6 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 2.85 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 7 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 2.8 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 8 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 2.7 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 9 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 2.55 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 10 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 2.5 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

### Cluster 11 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 2.45 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 12 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 2.4 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 13 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 2.4 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 14 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 2.4 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 15 — Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed
- **Size:** 2 entries | **Score:** 2.33 | **Agent:** dex
- **Range:** 2026-04-21 → 2026-04-22
- **Status:** {'active': 2}
- **Sample entries:**
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| data http action returned | 6 | 6.0h | 100.0% | 2026-04-21 |
| html exists json code | 6 | 6.0h | 100.0% | 2026-04-21 |
| api/usage returned http | 5 | 6.0h | 100.0% | 2026-04-21 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **1 broken links detected** (38 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (24 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **/api/hq?action=data returned HTTP 401** (6 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (6 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **/api/usage returned HTTP 404** (5 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (2 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 