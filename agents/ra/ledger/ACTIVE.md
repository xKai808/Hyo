# Ra Active Tasks

Last updated: 2026-04-17T18:45:46-0600

## In Progress

- **ra-apr12-13-retroactive** [P2] Investigate Apr 12 and Apr 13 synthesis failures
  - Created: 2026-04-17T18:45:46-0600
  - Method: Check Mini launchd logs for those nights, verify ANTHROPIC_API_KEY env in plist
  - Status: OPEN — input.md exists for both dates, synthesis never ran

## Recently Completed

- **ra-pipeline-fix-2026-04-17** [P1] Newsletter auto-publish to HQ feed — SHIPPED 2026-04-17T18:45:46-0600
  - Fixed: newsletter.sh now writes directly to both feed.json paths after each successful run
  - Published: Apr 15 and Apr 17 newsletters retroactively added to HQ feed
  - Verified: 4 newsletter entries now in feed (Apr 14, 15, 16, 17)
  - Report published to HQ feed

## Newsletter Status

| Date       | Generated | Published to HQ |
|------------|-----------|-----------------|
| 2026-04-17 | ✓ 04:04   | ✓ manual then auto-wired |
| 2026-04-16 | ✓ 19:29   | ✓                       |
| 2026-04-15 | ✓ 04:03   | ✓ retroactive           |
| 2026-04-14 | ✓ 18:41   | ✓                       |
| 2026-04-13 | ✗ gather only | ✗ synthesis failed  |
| 2026-04-12 | ✗ gather only | ✗ synthesis failed  |
