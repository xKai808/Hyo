# Aetherbot Priorities

Agent: aetherbot.hyo  
Updated: 2026-04-12

## Current Priorities

1. **Autonomous 15-minute cycle execution** — Ensure launchd scheduler runs reliably and pushes metrics to HQ every 15 minutes.

2. **Weekly reset integrity** — Validate that Monday 00:00 MT reset correctly archives current week, resets counters, and carries forward balance.

3. **Trade API health** — Monitor `/api/aetherbot` endpoint availability and response times. Ensure founder-token authentication works.

4. **Metrics JSON consistency** — Maintain valid JSON structure in `website/data/aetherbot-metrics.json`. Prevent corruption on concurrent writes.

5. **HQ dashboard push reliability** — Validate that metrics reach HQ dashboard with current founder token. Log failures for manual review.

## Monitoring

- Daily review of `agents/aetherbot/logs/` for errors or missed cycles
- Weekly validation of `website/data/aetherbot-metrics.json` structure
- Monthly audit of trades ledger (`agents/aetherbot/ledger/trades.jsonl`) for data integrity
- Real-time alert if 15-minute cycle fails or HQ push returns errors

## Success Criteria

- [x] Manifest created and integrated into agent fleet
- [ ] First launchd execution successful (verify logs)
- [ ] Metrics JSON initializes correctly
- [ ] Trade recording via API endpoint functional
- [ ] HQ push authenticates and delivers payload
- [ ] Monday reset logic validates in dry-run
