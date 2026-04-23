# Dex Active Tasks

Last updated: 2026-04-23T13:16:31Z

## In Progress

- **dex-001** [P2] [GUIDANCE] You've reported the same bottleneck 3 cycles in a row. What systemic fix would eliminate it? What assumption are you making?
  - Delegated: 2026-04-23T13:16:31Z
  - Status: DELEGATED

- **dex-002** [P1] [AUTO-REMEDIATE] Phase 1 JSONL corruption unresolved since 2026-04-14 (flag-dex-001): 2 JSONL files have corrupt entries. 4+ days stale as P2 — upgrading to P1. Need root-cause trace of which writer is producing malformed records and a schema-validation gate at append time. (flagged by dex, cascade flag-dex-002)
  - Delegated: 2026-04-18T08:07:23Z
  - Status: DELEGATED

## Queued

- **flag-dex-001** [P2] Dex Phase 1 FAILED: 2 JSONL files have corrupt entries
  - Created: 2026-04-14T06:02:59Z

- **flag-dex-002** [P2] Phase 1 JSONL corruption unresolved since 2026-04-14 (flag-dex-001): 2 JSONL files have corrupt entries. 4+ days stale as P2 — upgrading to P1. Need root-cause trace of which writer is producing malformed records and a schema-validation gate at append time.
  - Created: 2026-04-18T08:07:23Z

