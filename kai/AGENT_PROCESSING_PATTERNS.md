# Agent Task Processing Patterns

**Author:** Kai | **Date:** 2026-04-12 | **Status:** Validated via simulation

## Summary

Each agent processes work differently based on their domain. One-size-fits-all delegation doesn't work. This document defines how Kai delegates to each agent and how each agent processes tasks, based on simulation results.

## Dispatch System

All agents use the same ledger infrastructure (`bin/dispatch.sh`) for tracking:
- JSONL append-only log per agent + Kai cross-reference
- ACTIVE.md human-readable view (auto-rebuilt from log)
- Lifecycle: CREATED → DELEGATED → IN_PROGRESS → TESTING → VERIFIED → DONE

The dispatch tool handles: delegate, ack, report, verify, close, list, log, status.

## Sam — Engineering Agent

**Processing pattern:** Individual task delegation with immediate execution.

**Why:** Engineering tasks are discrete and testable. Each task has a clear done/not-done state. Sam needs specific instructions because code changes must be precise.

**How Kai delegates:**
- One task at a time via `dispatch delegate sam P1 "specific task"`
- Include file paths or search patterns in the task title
- Sam ACKs with planned method, executes, runs tests, reports results

**Sam's execution loop:**
1. Receive task → ACK with method description
2. Search codebase for relevant files
3. Make changes
4. Run test suite (`sam.sh test`)
5. Report findings (including when the right action is to NOT change something)
6. Kai verifies against test output → close

**Key insight from simulation:** Sam correctly identified that removing console.log calls would break MVP persistence — the right answer was "don't do it yet." Good engineering judgment, not just blind execution.

**Task examples:** Fix code, add tests, create docs, validate schemas, build API endpoints.

## Nel — QA/Security/System Improvement Agent

**Processing pattern:** Investigation batches with cross-cutting analysis.

**Why:** Nel's work is investigative — she needs to scan broadly and cross-reference findings. Tasks are often interconnected (a permissions issue may reveal a path issue which reveals a security gap).

**How Kai delegates:**
- Batch of 5 tasks covering different system aspects
- Nel can work multiple investigations in parallel
- Results from one investigation inform others

**Nel's execution loop:**
1. Receive batch → ACK each with investigation method
2. Run scans/audits (grep, find, static analysis)
3. Cross-reference findings across investigations
4. Fix issues directly when safe (permissions, missing validation)
5. Report issues that need architectural decisions back to Kai
6. Kai verifies fixes → close

**Key insight from simulation:** Nel found a real bug in dispatch.sh (JSON string injection via unquoted variables) that wouldn't have been caught by normal testing. Investigative agents catch systemic issues.

**Task examples:** Security scans, permission audits, code quality analysis, path validation, edge case testing.

## Ra — Newsletter Product Manager

**Processing pattern:** Content pipeline health checks with quality gates.

**Why:** Ra's work is about content integrity and pipeline health, not individual code changes. Ra needs to verify that the end-to-end pipeline produces correct output, that sources are adequate, and that the archive is consistent.

**How Kai delegates:**
- Pipeline-stage tasks (gather coverage, archive integrity, render quality)
- Content quality assessments
- Research archive management

**Ra's execution loop:**
1. Receive task → ACK with audit approach
2. Run data integrity checks (cross-reference index vs files, validate JSON)
3. Analyze coverage gaps and quality metrics
4. Produce publishable reports for HQ
5. Report findings with specific numbers and recommendations
6. Kai verifies data accuracy → close

**Key insight from simulation:** Ra's tasks are fundamentally about measurement and reporting, not code changes. Ra found that source coverage is biased toward tech/crypto/macro — an editorial insight that can't be unit-tested.

**Task examples:** Archive integrity checks, source coverage audits, pipeline health, output validation, research reports.

## Cross-Agent Patterns

### When to use individual delegation vs. batch lists
- **Sam:** Individual tasks. Each needs a test cycle.
- **Nel:** Batches of 5. Investigations feed each other.
- **Ra:** Stage-by-stage. Pipeline order matters.

### Auto-delegation triggers
When Kai completes a coding task → delegate to Sam for test coverage.
When any agent changes files → delegate to Nel for security/quality audit.
When gather runs → delegate to Ra for source coverage review.
When a bug is fixed → delegate to Nel to check for similar patterns elsewhere.

### Continuous ledger maintenance
- Dispatch status runs at the start of every session
- ACTIVE.md is the first thing Kai reads per agent
- New tasks are auto-delegated when previous ones close
- Stale tasks (>48h in DELEGATED without ACK) get escalated

### Task completion verification (per Hyo's directive)
Every task follows this flow before marking complete:
1. Agent executes the task
2. Agent runs verification (tests, scans, checks)
3. Agent reports back with specific results
4. Kai verifies against the original task requirements
5. Only then: verify + close
6. After closing: refer back to the original job that spawned the task
