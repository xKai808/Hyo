# Sam Active Tasks

Last updated: 2026-05-21T14:12:01Z

## In Progress

- **sam-001** [P1] SAFEGUARD: Add test coverage for issue (flag-nel-001): 1 broken links detected
  - Delegated: 2026-05-21T14:12:01Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **sam-002** [P1] SAFEGUARD: Add test coverage for issue (flag-kai-003): Daily audit: 2 critical issues found
  - Delegated: 2026-05-21T08:06:23Z
  - Status: DELEGATED

- **sam-003** [P1] SAFEGUARD: Add test coverage for issue (flag-kai-004): Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system cannot self-heal. (1) HYDRATION LAYER DEAD: verified-state.json + session-handoff.json 15d stale, dispatch transcripts 21d stale (latest 2026-04-30); kai-session-prep.sh + session-close.sh + dispatch-sync scheduled tasks dead 12+ days. (2) DELEGATED->DONE PIPELINE BROKEN: 13 P1 items stuck DELEGATED across all agents, oldest nel-006 = 15d; auto-remediate never closes. (3) daily-audit.sh HYO_ROOT bug recurs every sandbox run (false all-FAIL report). NEEDS HYO: dex-002 carries a launchctl request stuck DELEGATED 3d and never surfaced — run 'launchctl list | grep com.hyo' on Mini to confirm which scheduled tasks died. Internal remediation is structurally incapable of fixing this.
  - Delegated: 2026-05-21T08:08:23Z
  - Status: DELEGATED

- **sam-004** [P1] SAFEGUARD: Add test coverage for issue (flag-kai-019): Daily audit: Aether KILL-SWITCH active since 2026-05-13 (Hyo refused aether.sh) but daily-audit.sh still flags 'no runner output' and 'evolution.jsonl 80h stale' — script must read kill-switch and skip-stamp instead of flagging; also evolution.jsonl never existed (false stale claim)
  - Delegated: 2026-05-17T08:07:37Z
  - Status: DELEGATED

- **sam-005** [P1] SAFEGUARD: Add test coverage for issue (flag-kai-020): Daily audit META: DELEGATED→DONE transition broken across all agents — sam-005 stuck 16d, aether-002 stuck 7d, dex-002 stuck 4d, ra-002/003/004 stuck; no agent's auto-remediate ever closes; cascade fires endlessly. dex-002 already flagged 4d ago and itself is the stuck item. Need: pathway-closer daemon OR runners must call dispatch close on completion. Without this, every flag is a one-way street and audit metrics grow forever.
  - Delegated: 2026-05-17T08:07:47Z
  - Status: DELEGATED

## Queued

- **flag-sam-001** [P2] SIM-TEST: upward flag communication test
  - Created: 2026-05-01T05:30:00Z

