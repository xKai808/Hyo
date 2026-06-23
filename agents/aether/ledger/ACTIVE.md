# Aether Active Tasks

Last updated: 2026-06-23T07:50:47Z

## In Progress

- **aether-001** [P1] [AUTO-REMEDIATE] aether PLAYBOOK.md is 40d old (>14d critical) (flagged by nel, cascade flag-nel-001)
  - Delegated: 2026-06-23T07:50:47Z
  - Status: DELEGATED

- **aether-002** [P1] [AUTO-REMEDIATE] Daily audit: Aether KILL-SWITCH active since 2026-05-13 (Hyo refused aether.sh) but daily-audit.sh still flags 'no runner output' and 'evolution.jsonl 80h stale' — script must read kill-switch and skip-stamp instead of flagging; also evolution.jsonl never existed (false stale claim) (flagged by kai, cascade flag-kai-019)
  - Delegated: 2026-05-17T08:07:37Z
  - Status: DELEGATED

- **aether-003** [P1] [AUTO-REMEDIATE] Daily audit META: DELEGATED→DONE transition broken across all agents — sam-005 stuck 16d, aether-002 stuck 7d, dex-002 stuck 4d, ra-002/003/004 stuck; no agent's auto-remediate ever closes; cascade fires endlessly. dex-002 already flagged 4d ago and itself is the stuck item. Need: pathway-closer daemon OR runners must call dispatch close on completion. Without this, every flag is a one-way street and audit metrics grow forever. (flagged by kai, cascade flag-kai-020)
  - Delegated: 2026-05-17T08:07:47Z
  - Status: DELEGATED

## Queued

- **flag-aether-001** [P2] dashboard data mismatch: local ts 2026-04-28T20:36:58-06:00 != API ts 2026-04-28T20:17:46-06:00
  - Created: 2026-04-29T02:37:29Z

