# Nel Active Tasks

Last updated: 2026-05-27T14:21:51Z

## In Progress

- **nel-001** [P1] [AUTO-REMEDIATE] 1 broken links detected (flagged by nel, cascade flag-nel-001)
  - Delegated: 2026-05-27T14:21:51Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **nel-002** [P1] SAFEGUARD: Cross-reference issue (flag-kai-002) — scan entire codebase for similar patterns: Daily audit: 2 critical issues found
  - Delegated: 2026-05-27T08:07:17Z
  - Status: DELEGATED

- **nel-003** [P1] SAFEGUARD: Cross-reference issue (flag-kai-010) — scan entire codebase for similar patterns: Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTERVENTION. 22 stuck DELEGATED items in Kai ledger; meta-fix ticket aether-002 itself stuck 8d. Newsletter pipeline is a no-op: missed 2026-05-25/21/17/12/09/08/07/06 — Ra AUTO-REMEDIATE records DELEGATED but never produces output. verified-state.json + session-handoff.json frozen 20d at 2026-05-05 (kai-session-prep.sh + session-close.sh dead). daily-audit.sh HYO_ROOT bug recurred (scheduled task wrapper sets no HYO_ROOT; first run today produced phantom FAILs). ~20 consecutive daily Kai audit flags unresolved. Kai cannot restart dead launchd plists from Cowork sandbox — Hyo must run: launchctl list | grep com.hyo on the Mini, then reload kai-session-prep, session-close, weekly-maintenance, and the Ra newsletter pipeline.
  - Delegated: 2026-05-25T08:08:07Z
  - Status: DELEGATED

- **nel-004** [P1] SAFEGUARD: Cross-reference issue (flag-nel-010) — scan entire codebase for similar patterns: No newsletter produced for 2026-05-21 — past 06:00 MT deadline
  - Delegated: 2026-05-21T22:13:48Z
  - Status: DELEGATED

- **nel-005** [P1] SAFEGUARD: Cross-reference issue (flag-kai-020) — scan entire codebase for similar patterns: Daily audit META: DELEGATED→DONE transition broken across all agents — sam-005 stuck 16d, aether-002 stuck 7d, dex-002 stuck 4d, ra-002/003/004 stuck; no agent's auto-remediate ever closes; cascade fires endlessly. dex-002 already flagged 4d ago and itself is the stuck item. Need: pathway-closer daemon OR runners must call dispatch close on completion. Without this, every flag is a one-way street and audit metrics grow forever.
  - Delegated: 2026-05-17T08:07:47Z
  - Status: DELEGATED

- **nel-006** [P1] SAFEGUARD: Cross-reference issue (flag-nel-015) — scan entire codebase for similar patterns: No newsletter produced for 2026-05-06 — past 06:00 MT deadline
  - Delegated: 2026-05-06T18:13:22Z
  - Status: DELEGATED

## Queued

- **flag-nel-004** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-04-28T14:10:36Z

- **flag-nel-005** [P2] Found 27 broken documentation links — fix or cleanup needed
  - Created: 2026-04-28T14:10:42Z

- **flag-nel-006** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-04-28T14:11:47Z

- **flag-nel-007** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-04-28T14:13:42Z

- **flag-nel-008** [P2] Found 27 broken documentation links — fix or cleanup needed
  - Created: 2026-04-28T14:13:48Z

- **flag-nel-009** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-04-28T14:14:42Z

- **flag-nel-010** [P2] Found 27 broken documentation links — fix or cleanup needed
  - Created: 2026-04-28T14:14:49Z

- **flag-nel-011** [P2] Found 9 code optimization opportunities — rolling improvement
  - Created: 2026-04-28T14:14:49Z

- **flag-nel-012** [P2] Audit found 5 system issues — review security/structure
  - Created: 2026-04-28T14:14:58Z

- **flag-nel-013** [P2] [SELF-REVIEW] 1 untriggered files found
  - Created: 2026-04-28T14:15:17Z

- **flag-nel-001** [P2] 1 broken links detected
  - Created: 2026-04-28T14:57:47Z

- **flag-nel-002** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-04-28T18:10:26Z

- **flag-nel-003** [P2] No newsletter produced for 2026-04-28 — past 06:00 MT deadline
  - Created: 2026-04-28T18:10:26Z

- **flag-nel-014** [P2] Sentinel: 2 project(s) with test failures
  - Created: 2026-05-06T18:13:22Z

- **flag-nel-015** [P2] No newsletter produced for 2026-05-06 — past 06:00 MT deadline
  - Created: 2026-05-06T18:13:22Z

- **flag-nel-016** [P2] Found 29 broken documentation links — fix or cleanup needed
  - Created: 2026-05-06T18:13:30Z

- **flag-nel-017** [P2] Audit found 5 system issues — review security/structure
  - Created: 2026-05-22T18:16:00Z

- **flag-nel-018** [P2] [SELF-REVIEW] 1 untriggered files found
  - Created: 2026-05-22T18:16:08Z

