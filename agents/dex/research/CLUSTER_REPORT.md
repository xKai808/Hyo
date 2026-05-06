# Dex Pattern Cluster Report
**Generated:** 2026-05-06
**Total entries analyzed:** 197
**Noise reduction:** 197 entries → 128 clusters (35.0% dedup rate)

## Signal Summary
- Multi-entry clusters: **8** (same root cause, different timestamps)
- Singleton clusters: **120** (unique issues)
- Recurring temporal patterns: **2**
- Highest-volume agent: **ra**
- Largest cluster: **36 entries** with same root cause

## Agent Breakdown
| Agent | Issues |
|-------|--------|
| ra | 64 |
| unknown | 44 |
| aether | 23 |
| sam | 19 |
| kai | 16 |
| dex | 14 |
| nel | 13 |
| ant | 4 |

## Top Issue Clusters (by impact score)

### Cluster 1 — 1 broken links detected
- **Size:** 36 entries | **Score:** 45.15 | **Agent:** unknown
- **Range:** 2026-04-21 → 2026-05-05
- **Status:** {'active': 36}
- **Sample entries:**
  - 1 broken links detected
  - 1 broken links detected
  - 1 broken links detected

### Cluster 2 — No newsletter produced for 2026-04-24 — past 06:00 MT deadline
- **Size:** 27 entries | **Score:** 36.88 | **Agent:** ra
- **Range:** 2026-04-24 → 2026-05-06
- **Status:** {'active': 27}
- **Sample entries:**
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

### Cluster 3 — /api/hq?action=data returned HTTP 401
- **Size:** 3 entries | **Score:** 3.42 | **Agent:** sam
- **Range:** 2026-04-21 → 2026-04-21
- **Status:** {'resolved_fp': 3}
- **Sample entries:**
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

### Cluster 4 — Aether metrics JSON exists but hq.html has NO rendering code
- **Size:** 3 entries | **Score:** 3.42 | **Agent:** ra
- **Range:** 2026-04-21 → 2026-04-21
- **Status:** {'resolved_fp': 3}
- **Sample entries:**
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

### Cluster 5 — Daily audit: 5 critical issues found
- **Size:** 2 entries | **Score:** 2.97 | **Agent:** dex
- **Range:** 2026-05-05 → 2026-05-06
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

### Cluster 6 — daily-agent-report.sh used 'declare -A' associative arrays. macOS ships with bash 3.2 which does not
- **Size:** 1 entries | **Score:** 2.75 | **Agent:** ra
- **Range:** 2026-04-30 → 2026-04-30
- **Status:** {'unknown': 1}

### Cluster 7 — kai/schemas/kai_daily.schema.json missing. publish-to-feed.sh has a hard schema gate (exit 1) for an
- **Size:** 1 entries | **Score:** 2.75 | **Agent:** kai
- **Range:** 2026-05-01 → 2026-05-01
- **Status:** {'unknown': 1}

### Cluster 8 — AetherBot 401 auth failures were invisible — aether.sh reported 0 trades as standby mode instead of 
- **Size:** 1 entries | **Score:** 2.65 | **Agent:** ra
- **Range:** 2026-04-28 → 2026-04-28
- **Status:** {'unknown': 1}

### Cluster 9 — Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25
- **Size:** 2 entries | **Score:** 2.5 | **Agent:** dex
- **Range:** 2026-04-24 → 2026-04-26
- **Status:** {'active': 2}
- **Sample entries:**
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

### Cluster 10 — Morning report git push blocked: kai/ledger/ticket-enforcer.log grew to 175MB, exceeded GitHub 100MB
- **Size:** 1 entries | **Score:** 2.45 | **Agent:** nel
- **Range:** 2026-04-24 → 2026-04-24
- **Status:** {'unknown': 1}

### Cluster 11 — Anthropic API key on Mini hit usage quota (until 2026-05-01). kai_analysis.py had no fallback — fail
- **Size:** 1 entries | **Score:** 2.4 | **Agent:** ra
- **Range:** 2026-04-23 → 2026-04-23
- **Status:** {'unknown': 1}

### Cluster 12 — generate-morning-report.sh staged website/data/feed.json but not agents/sam/website/data/feed.json. 
- **Size:** 1 entries | **Score:** 2.35 | **Agent:** sam
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 13 — Answered 12 Hyo questions without reading source files first. Made two wrong claims: (1) no follow-u
- **Size:** 1 entries | **Score:** 2.35 | **Agent:** unknown
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 14 — Injected score card JS into hq.html via Python string replace. Used escaped dollar (backslash-dollar
- **Size:** 1 entries | **Score:** 2.35 | **Agent:** ra
- **Range:** 2026-04-22 → 2026-04-22
- **Status:** {'unknown': 1}

### Cluster 15 — /api/usage returned HTTP 404
- **Size:** 2 entries | **Score:** 2.3 | **Agent:** sam
- **Range:** 2026-04-21 → 2026-04-21
- **Status:** {'resolved_fp': 2}
- **Sample entries:**
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

## Temporal Patterns (recurring at consistent intervals)
| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |
|---------|-------------|--------------|-------------|-----------|
| http action returned data | 3 | 6.0h | 100.0% | 2026-04-21 |
| aether code json exists | 3 | 6.0h | 100.0% | 2026-04-21 |

## Deduplication Candidates
The following clusters contain multiple entries with the same root cause.
Consider merging them into a single canonical issue:

- **1 broken links detected** (36 entries, unknown)
  - 1 broken links detected
  - 1 broken links detected

- **No newsletter produced for 2026-04-24 — past 06:00 MT deadline** (27 entries, ra)
  - No newsletter produced for 2026-04-24 — past 06:00 MT deadline
  - No newsletter produced for 2026-04-25 — past 06:00 MT deadline

- **/api/hq?action=data returned HTTP 401** (3 entries, sam)
  - /api/hq?action=data returned HTTP 401
  - /api/hq?action=data returned HTTP 401

- **Aether metrics JSON exists but hq.html has NO rendering code** (3 entries, ra)
  - Aether metrics JSON exists but hq.html has NO rendering code
  - Aether metrics JSON exists but hq.html has NO rendering code

- **Daily audit: 5 critical issues found** (2 entries, dex)
  - Daily audit: 5 critical issues found
  - Daily audit: 1 critical issues found

- **Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic system health RED (25** (2 entries, dex)
  - Daily audit 2026-04-24: 54 unread URGENT hyo-inbox messages (duplicates from rep
  - Daily audit 2026-04-26: 63 unread URGENT messages in hyo-inbox.jsonl — chronic s

- **/api/usage returned HTTP 404** (2 entries, sam)
  - /api/usage returned HTTP 404
  - /api/usage returned HTTP 404

- **Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix needed** (2 entries, dex)
  - Dex Phase 4: 225 recurrent patterns detected — check safeguard status
  - Dex Phase 4: 235 recurrent patterns detected — increased from 0, root-cause fix 