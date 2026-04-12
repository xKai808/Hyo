# Kai ↔ Agent Ledger Protocol

**Purpose:** Every interaction between Kai and an agent is logged in a structured, append-only ledger. This is the working memory between Kai and each agent. It ensures no task is lost, no work is duplicated, and every delegation has a clear lifecycle.

## Ledger locations

| Agent | Ledger dir | Active tasks | Full log |
|-------|-----------|--------------|----------|
| Kai (self) | `kai/ledger/` | `ACTIVE.md` | `log.jsonl` |
| Nel | `agents/nel/ledger/` | `ACTIVE.md` | `log.jsonl` |
| Ra | `agents/ra/ledger/` | `ACTIVE.md` | `log.jsonl` |
| Sam | `agents/sam/ledger/` | `ACTIVE.md` | `log.jsonl` |

## Task lifecycle

```
CREATED → DELEGATED → IN_PROGRESS → TESTING → VERIFIED → DONE
                                   ↘ BLOCKED → (unblocked) → IN_PROGRESS
                                   ↘ FAILED → RETRY → IN_PROGRESS
```

## JSONL log format

Each line in `log.jsonl` is a JSON object:

```json
{"ts":"2026-04-12T19:00:00Z","action":"DELEGATE","task_id":"sam-001","from":"kai","to":"sam","title":"Fix console.log in API code","priority":"P1","context":"Sam review found console.log in 3 API files","deadline":"2026-04-13T00:00:00Z"}
{"ts":"2026-04-12T19:05:00Z","action":"ACK","task_id":"sam-001","from":"sam","to":"kai","status":"IN_PROGRESS","method":"grep + sed replacement across api/*.js"}
{"ts":"2026-04-12T19:10:00Z","action":"REPORT","task_id":"sam-001","from":"sam","to":"kai","status":"TESTING","result":"Removed 12 console.log calls from 3 files. Running tests."}
{"ts":"2026-04-12T19:12:00Z","action":"VERIFY","task_id":"sam-001","from":"kai","to":"sam","status":"VERIFIED","notes":"Confirmed no console.log in api/. Tests pass."}
{"ts":"2026-04-12T19:12:00Z","action":"CLOSE","task_id":"sam-001","status":"DONE","completed":"2026-04-12T19:12:00Z"}
```

## ACTIVE.md format

Human-readable snapshot of current open tasks:

```markdown
# [Agent] Active Tasks

Last updated: 2026-04-12T19:12:00Z

## In Progress
- **sam-001** [P1] Fix console.log in API code
  - Delegated: 2026-04-12 19:00 UTC
  - Method: grep + sed replacement
  - Status: TESTING — removed 12 calls, running tests

## Queued
- **sam-002** [P2] Add hq.html to static file tests
  - Delegated: 2026-04-12 19:15 UTC

## Recently Completed
- **sam-000** [P1] Initial test suite run — 2026-04-12 18:30 UTC (DONE)
```

## Rules

1. **Every delegation creates a log entry.** No verbal-only tasks.
2. **Every completion requires verification.** Agent reports → Kai verifies → then DONE.
3. **ACTIVE.md is rebuilt from log.jsonl.** It's a view, not the source of truth.
4. **Task IDs are sequential per agent:** `sam-001`, `sam-002`, `nel-001`, `ra-001`.
5. **Kai's own ledger tracks what was delegated where.** Cross-reference.
6. **Nightly consolidation reads the ledger** and includes open task counts in reports.
