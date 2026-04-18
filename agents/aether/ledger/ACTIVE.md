# Aether Active Tasks

Last updated: 2026-04-17T18:46:01-0600

## In Progress

- **aether-phantom-fix** [P0] Phantom position investigation — fix local/API state drift
  - Created: 2026-04-14
  - Method: Overwrite local state with API state at each cycle start (AetherBot code on Mini)
  - Status: QUEUED to Mini — needs queue worker pickup
  - Impact: 39 phantom warnings Monday, climbing. Degrades execution quality.

- **aether-bdi-gate** [P1] BDI=0 Hold Time Gate — block trades <120s from expiry when BDI=0
  - Created: 2026-04-14
  - Method: Add gate in AetherBot trade entry logic (Mini code)
  - Status: QUEUED to Mini

- **aether-harvest-miss** [P1] Harvest Miss Dual-Mode Fix — gate on anchor ±0.02 depth not held_px ±0.05
  - Created: 2026-04-14
  - Method: Update harvest trigger condition in AetherBot (Mini code)
  - Status: QUEUED to Mini

## Recently Completed

- **aether-sources-fix-2026-04-17** [P1] Research sources replaced — SHIPPED 2026-04-17T18:46:01-0600
  - 5 of 7 sources were dead (JS-rendered, paywalled, 0 results)
  - Replaced with: Kalshi API docs, arXiv q-fin.TR, Reddit Kalshi, BTC OHLCV, HN prediction markets
  - Verified: research-sources.json committed, will take effect next research cycle
  - Report published to HQ feed

- **aether-gpt-prompt-2026-04-17** [P1] GPT adversarial prompt strengthened — SHIPPED 2026-04-17T18:46:01-0600
  - Old: 3 lines, generic. New: 8 mandated dimensions with quantitative thresholds
  - Covers: strategy drift, risk concentration, entry quality degradation, harvest efficiency,
    timing regression, open issue progress, simulation gaps, failure mode prediction
  - Balance ledger and open issues updated to current week
