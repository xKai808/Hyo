# refresh-usage.sh — Usage Data Refresh Script

This script pulls the latest OpenAI and Anthropic Claude API usage data from the cloud billing APIs and updates the local CSV files that power the HQ dashboard.

## Quick Start

```bash
bash kai/queue/refresh-usage.sh
```

The script runs safely even if API keys aren't configured — it falls back to existing CSVs.

## How It Works

1. **Checks for API keys** (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)
2. **Calls cloud billing APIs** (if available)
3. **Parses responses** and writes new CSV files to `website/data/`
4. **Logs all operations** to `/tmp/hyo-usage-refresh.log`
5. **Falls back gracefully** if APIs aren't available

## Environment Variables

Set these to enable live API refresh:

```bash
export OPENAI_API_KEY="sk-..."            # From platform.openai.com
export OPENAI_ORG_ID="org-..."            # From OpenAI org settings
export ANTHROPIC_API_KEY="sk-ant-..."     # From console.anthropic.com
export ANTHROPIC_ORG_ID="org-..."         # Optional; for org-level billing
```

## Scheduling

To run automatically every 4 hours, add to `launchd` or cron:

```bash
# Via launchd (macOS)
# Create a plist at ~/Library/LaunchAgents/com.hyo.refresh-usage.plist
# with:
#   <key>StartInterval</key>
#   <integer>14400</integer>  <!-- 4 hours in seconds -->

# Via cron
0 */4 * * * cd /Users/kai/Documents/Projects/Hyo && bash kai/queue/refresh-usage.sh >> /tmp/hyo-usage-refresh.log 2>&1
```

## Output

The script writes:
- **`website/data/completions_usage_YYYY-MM-DD_YYYY-MM-DD.csv`** — OpenAI completions usage
- **`website/data/claude_api_tokens_YYYY_MM.csv`** — Claude API token usage

Both are read by the `/api/usage` endpoint and displayed on the HQ dashboard.

## Testing

```bash
# Test in dry-run mode (logs only, no actual writes)
bash kai/queue/refresh-usage.sh --dry-run

# View logs
tail -f /tmp/hyo-usage-refresh.log
```

## Integration with HQ Dashboard

The `/api/usage` endpoint automatically:
- Reads the latest CSV files from `website/data/`
- Caches results for 1 hour (TTL: `3600000ms`)
- Computes costs using pricing from `website/data/usage-config.json`
- Returns aggregated daily + total cost metrics

The HQ dashboard at `hyo.world/hq` fetches this endpoint every 60 seconds and displays:
- Daily usage charts (OpenAI + Claude side-by-side)
- Total cost vs. budget (configurable)
- Per-model breakdown with request counts

## Configuration

To change budgets or pricing, edit `website/data/usage-config.json`:

```json
{
  "openai_budget": 100.00,
  "claude_budget": 50.00,
  "openai_pricing": {
    "gpt-4o-2024-08-06": { "input": 2.50, "output": 10.00 }
  },
  "claude_pricing": {
    "claude-sonnet-4-6": { "input": 3.00, "output": 15.00 },
    "claude-haiku-4-5-20251001": { "input": 0.80, "output": 4.00 }
  }
}
```

The API endpoint will automatically reload this config on every request.

## Fallback Behavior

If API keys aren't set, the script exits cleanly (exit 0) and the HQ dashboard continues to display the most recent CSV snapshots. This means:
- **No API keys?** → Use existing CSVs (safe)
- **API call fails?** → Fall back to existing CSVs (safe)
- **API succeeds?** → Write new CSVs, update dashboard in real-time

No manual intervention required.

## Future Enhancements

- [ ] Stream CSV updates instead of full rewrites
- [ ] Add Stripe webhook integration for immediate cost updates
- [ ] Alert on budget overage (email to Hyo)
- [ ] Export monthly cost reports
- [ ] Multi-org billing aggregation
