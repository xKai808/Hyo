# Ant GROWTH.md — Accountant Self-Improvement Tracker
**Agent:** Ant (Financial Accounting)
**Domain:** API credit tracking, expense reporting, income tracking, monthly bookkeeping
**Last updated:** 2026-04-23
**Status:** Active

## Active Weaknesses

### W1: Cowork Session Costs Are Invisible
**Severity:** P0
**Status:** active
**Evidence:**
- api-usage.jsonl tracks only automated script calls (Aether, etc.)
- Cowork sessions consume Anthropic API credits but are not logged anywhere
- Real April spend: $21.09 total vs $0.24 tracked in api-usage.jsonl ($20.85 untracked)
- Ant dashboard consistently understates true Anthropic spend
**Root cause:** No programmatic Anthropic usage API exists for individual accounts.
  Console uses session-cookie authenticated endpoints that require browser login.
**Fix approach:** Daily balance diff tracking via browser scrape + KNOWLEDGE.md has full investigation.
  bin/ant-fetch-balance.py exists but needs one-time Keychain authorization on Mini.

### W2: Credit Balance Goes Stale Between Manual Scrapes
**Severity:** P1
**Status:** active
**Evidence:**
- scraped-credits.json has 48h staleness threshold
- If no Cowork session runs for 2+ days, balance becomes outdated
- ant-update.sh correctly warns when stale, but has no auto-refresh
**Fix approach:** Build automated balance refresh that runs via the Chrome MCP during any
  active Cowork session, without requiring screen control.

### W3: Monthly Close Is Manual
**Severity:** P1
**Status:** active
**Evidence:**
- PROTOCOL_ANT.md documents the close procedure
- No launchd job triggers it on the 1st of each month
- Requires: kai exec or manual run
**Fix approach:** Add a monthly-close launchd plist that runs on day 1 at 01:00 MT.

## Expansion Opportunities

### E1: AetherBot P&L Cross-Reference
Build reconciliation between Ant's income tracking (from aether-metrics.json)
and AetherBot's actual trade ledger. Currently relies on weekly_pnl snapshot;
should verify against individual trade outcomes.

## Goals

| ID | Goal | Deadline | Status |
|----|------|----------|--------|
| G1 | Automate balance scrape (no screen control) | 2026-05-01 | pending |
| G2 | Monthly close launchd plist | 2026-04-28 | pending |
| G3 | Cowork cost tracking via balance diff | 2026-05-01 | pending |
