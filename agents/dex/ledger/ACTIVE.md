# Dex Active Tasks

Last updated: 2026-05-18T19:53:57Z

## In Progress

- **dex-001** [P2] [GUIDANCE] You've reported the same bottleneck 3 cycles in a row. What systemic fix would eliminate it? What assumption are you making?
  - Delegated: 2026-05-18T19:53:57Z
  - Status: DELEGATED

- **dex-002** [P1] [AUTO-REMEDIATE] Daily audit 2026-05-18: verified-state.json + session-handoff.json + dispatch-transcripts all 12-18 days stale — hydration data layer is broken, every session boots on stale truth. Root cause: kai-session-prep.sh and session-close.sh + dispatch sync scheduled tasks have not run for ~12 days. This compounds with flag-kai-020 (DELEGATED→DONE pipeline broken) — flags pile up forever because closure is broken AND state cannot be re-verified. Hyo: please run 'launchctl list | grep com.hyo' on Mini to confirm which scheduled tasks died. (flagged by kai, cascade flag-kai-022)
  - Delegated: 2026-05-18T08:08:06Z
  - Status: DELEGATED

## Queued

- **flag-dex-001** [P2] agent research stale: aurora (no brief exists)
  - Created: 2026-05-01T05:04:07Z

