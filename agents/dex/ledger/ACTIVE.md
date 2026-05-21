# Dex Active Tasks

Last updated: 2026-05-21T14:07:43Z

## In Progress

- **dex-001** [P2] [GUIDANCE] You've reported the same bottleneck 3 cycles in a row. What systemic fix would eliminate it? What assumption are you making?
  - Delegated: 2026-05-21T14:07:43Z
  - Status: DELEGATED

- **dex-002** [P1] [AUTO-REMEDIATE] Daily audit 2026-05-21: 3 chronic issues re-flagged 3-21 consecutive days with ZERO closure — system cannot self-heal. (1) HYDRATION LAYER DEAD: verified-state.json + session-handoff.json 15d stale, dispatch transcripts 21d stale (latest 2026-04-30); kai-session-prep.sh + session-close.sh + dispatch-sync scheduled tasks dead 12+ days. (2) DELEGATED->DONE PIPELINE BROKEN: 13 P1 items stuck DELEGATED across all agents, oldest nel-006 = 15d; auto-remediate never closes. (3) daily-audit.sh HYO_ROOT bug recurs every sandbox run (false all-FAIL report). NEEDS HYO: dex-002 carries a launchctl request stuck DELEGATED 3d and never surfaced — run 'launchctl list | grep com.hyo' on Mini to confirm which scheduled tasks died. Internal remediation is structurally incapable of fixing this. (flagged by kai, cascade flag-kai-004)
  - Delegated: 2026-05-21T08:08:23Z
  - Status: DELEGATED

## Queued

- **flag-dex-001** [P2] agent research stale: aurora (no brief exists)
  - Created: 2026-05-01T05:04:07Z

