# Ant — Active Ledger
# Updated by: Kai session 2026-04-18 (manual — ant-update.sh will overwrite on next run)

**Agent:** Ant (Accountant)
**Last run:** 2026-04-18T23:20:47-06:00 (manual via Cowork session)
**Status:** OK
**Protocol version:** 1.2

## Credit status (as of last run)

| Provider   | Remaining | Total  | Used MTD | Source                  |
|------------|-----------|--------|----------|-------------------------|
| Anthropic  | $30.79    | $40.00 | $0.24    | screen-scraped (0h ago) |
| OpenAI     | $18.64    | $20.00 | $0.89    | screen-scraped (0h ago) |

## Net position (2026-04)

- Income: $24.94
- Fixed expenses: $220.00 (Claude Max $200 + GPT Plus $20)
- API MTD: $1.19 (Anthropic $0.24 + OpenAI $0.89 + buffer)
- **Net: -$196.25**

## Open tickets

| Ticket       | Priority | Description                                          |
|--------------|----------|------------------------------------------------------|
| ANT-GAP-001  | P2       | Screen-scrape requires Cowork; needs Admin API key   |
| ANT-GAP-002  | P3       | No launchd job for monthly close (1st of month)      |
| ANT-GAP-003  | P3       | No failure alert if ant-daily fails overnight        |

## Next scheduled run

2026-04-19T23:45:00-06:00 (via com.hyo.ant-daily launchd)

## Session notes (2026-04-18)

This session completed:
- ant-update.sh rewritten with quoted heredoc fix (bad substitution bug)
- scraped-credits.json populated with real Anthropic/OpenAI balances
- ant-data.json rebuilt with real credits + 14-day history
- hq.html: daily chart fixed (history[] field path), SyntaxError fixed
- PROTOCOL_ANT.md bumped to v1.2 with 17 failure modes, locked layout spec,
  verified schedule table, agent independence tiers
