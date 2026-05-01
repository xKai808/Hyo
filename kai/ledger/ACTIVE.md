# Kai Active Tasks

Last updated: 2026-05-01T06:26:47Z

## In Progress

- **nel-001** [P1] [AUTO-REMEDIATE] 1 broken links detected (flagged by nel, cascade flag-nel-001)
  - Delegated: 2026-05-01T06:11:19Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **sam-001** [P2] [GUIDANCE] Your last 3 cycles had the same assessment. What's preventing progress? What would you try differently?
  - Delegated: 2026-05-01T06:26:40Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **ra-001** [P2] [GUIDANCE] Your last 3 cycles had the same assessment. What's preventing progress? What would you try differently?
  - Delegated: 2026-05-01T06:26:41Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **aether-001** [P2] [GUIDANCE] Your last 3 cycles had the same assessment. What's preventing progress? What would you try differently?
  - Delegated: 2026-05-01T01:25:44Z
  - Status: DELEGATED

- **dex-001** [P2] [GUIDANCE] You've reported the same bottleneck 3 cycles in a row. What systemic fix would eliminate it? What assumption are you making?
  - Delegated: 2026-05-01T06:26:41Z
  - Status: DELEGATED

- **nel-002** [P1] SAFEGUARD: Cross-reference issue (flag-nel-003) — scan entire codebase for similar patterns: No newsletter produced for 2026-05-01 — past 06:00 MT deadline
  - Delegated: 2026-05-01T02:10:15Z
  - Status: DELEGATED

- **sam-002** [P1] SAFEGUARD: Add test coverage for issue (flag-nel-006): No newsletter produced for 2026-05-01 — past 06:00 MT deadline
  - Delegated: 2026-05-01T02:11:04Z
  - Status: DELEGATED

- **ra-002** [P1] [AUTO-REMEDIATE] No newsletter produced for 2026-05-01 — past 06:00 MT deadline (flagged by nel, cascade flag-nel-006)
  - Delegated: 2026-05-01T02:11:04Z
  - Status: DELEGATED

- **kai-001** [P1] [AUTO-REMEDIATE] 1 broken links detected (flagged by kai)
  - Delegated: 2026-05-01T06:26:41Z
  - Status: DELEGATED

- **kai-002** [P1] [AUTO-REMEDIATE] Daily audit 2026-04-30: 6 [AUTOMATE] items in KAI_TASKS.md untouched since 2026-04-12 (18 days, threshold 7d) — lines 243,244,245,246,269,272. Prioritize next session. (flagged by kai, cascade flag-kai-002)
  - Delegated: 2026-05-01T00:25:51Z
  - Status: DELEGATED

- **nel-003** [P1] SAFEGUARD: Cross-reference issue (flag-nel-006) — scan entire codebase for similar patterns: No newsletter produced for 2026-05-01 — past 06:00 MT deadline
  - Delegated: 2026-05-01T02:11:04Z
  - Status: DELEGATED

## Queued

- **flag-aether-001** [P2] dashboard data mismatch: local ts 2026-04-29T01:05:35-06:00 != API ts 2026-04-29T00:57:03-06:00
  - Created: 2026-04-29T07:05:36Z

- **flag-nel-001** [P2] Found 28 broken documentation links — fix or cleanup needed
  - Created: 2026-04-29T08:00:19Z

- **flag-kai-001** [P2] Daily audit (2026-04-29): daily-audit.sh HYO_ROOT bug — 6th recurrence; supplement at kai/ledger/daily-audit-2026-04-29-supplement.md §1 has one-line fix. Real state RED: 16 P0 tickets, system health 25/100, newsletter pipeline failed overnight, 5/7 reports missing today.
  - Created: 2026-04-29T08:09:14Z

- **flag-ra-001** [P2] [SELF-REVIEW] 1 untriggered files found
  - Created: 2026-04-29T13:12:06Z

- **flag-nel-002** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-04-29T14:10:37Z

- **flag-nel-003** [P2] Found 28 broken documentation links — fix or cleanup needed
  - Created: 2026-04-29T14:10:45Z

- **flag-sam-001** [P2] [SELF-REVIEW] 1 untriggered files found
  - Created: 2026-04-29T15:55:39Z

- **flag-nel-004** [P2] Found 28 broken documentation links — fix or cleanup needed
  - Created: 2026-04-29T18:10:14Z

- **flag-nel-005** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-05-01T00:20:25Z

- **flag-nel-006** [P2] No newsletter produced for 2026-05-01 — past 06:00 MT deadline
  - Created: 2026-05-01T00:20:25Z

- **flag-nel-007** [P2] Found 28 broken documentation links — fix or cleanup needed
  - Created: 2026-05-01T00:20:35Z

- **flag-kai-002** [P2] Daily audit 2026-04-30: 6 [AUTOMATE] items in KAI_TASKS.md untouched since 2026-04-12 (18 days, threshold 7d) — lines 243,244,245,246,269,272. Prioritize next session.
  - Created: 2026-05-01T00:25:51Z

- **flag-kai-003** [P2] Daily audit 2026-04-30: TZ bug — kai/queue/daily-audit.sh and downstream nel sentinels use 'date +%Y-%m-%d' (UTC), causing false P1 'no newsletter for 2026-05-01' to fire at 18:24 MT on 2026-04-30 (06h before MT day even starts). Force TZ=America/Denver in daily-audit.sh, nel newsletter sentinel, and any consumer that compares to MT schedule.
  - Created: 2026-05-01T00:25:57Z

- **flag-dex-001** [P2] agent research stale: aurora (no brief exists)
  - Created: 2026-05-01T05:04:07Z

