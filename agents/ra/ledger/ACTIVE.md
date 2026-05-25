# Ra Active Tasks

Last updated: 2026-05-25T14:11:50Z

## In Progress

- **ra-001** [P2] [GUIDANCE] Your last 3 cycles had the same assessment. What's preventing progress? What would you try differently?
  - Delegated: 2026-05-25T14:11:50Z
  - Method: sim-ack: agent handshake test
  - Status: DELEGATED — sim-report: all clear

- **ra-002** [P1] [AUTO-REMEDIATE] Daily audit 2026-05-25: DELEGATED->DONE pipeline broken 25 days (since 2026-05-01) — NEEDS HYO INTERVENTION. 22 stuck DELEGATED items in Kai ledger; meta-fix ticket aether-002 itself stuck 8d. Newsletter pipeline is a no-op: missed 2026-05-25/21/17/12/09/08/07/06 — Ra AUTO-REMEDIATE records DELEGATED but never produces output. verified-state.json + session-handoff.json frozen 20d at 2026-05-05 (kai-session-prep.sh + session-close.sh dead). daily-audit.sh HYO_ROOT bug recurred (scheduled task wrapper sets no HYO_ROOT; first run today produced phantom FAILs). ~20 consecutive daily Kai audit flags unresolved. Kai cannot restart dead launchd plists from Cowork sandbox — Hyo must run: launchctl list | grep com.hyo on the Mini, then reload kai-session-prep, session-close, weekly-maintenance, and the Ra newsletter pipeline. (flagged by kai, cascade flag-kai-010)
  - Delegated: 2026-05-25T08:08:07Z
  - Status: DELEGATED

- **ra-003** [P1] [AUTO-REMEDIATE] No newsletter produced for 2026-05-25 — past 06:00 MT deadline (flagged by nel, cascade flag-nel-012)
  - Delegated: 2026-05-25T02:15:43Z
  - Status: DELEGATED

- **ra-004** [P1] [AUTO-REMEDIATE] No newsletter produced for 2026-05-21 — past 06:00 MT deadline (flagged by nel, cascade flag-nel-010)
  - Delegated: 2026-05-21T22:13:48Z
  - Status: DELEGATED

## Queued

- **flag-ra-001** [P2] [SELF-REVIEW] 1 untriggered files found
  - Created: 2026-04-28T20:59:10Z

