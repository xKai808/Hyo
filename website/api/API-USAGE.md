# `/api/usage` — Real-Time API Usage Metrics

Aggregates OpenAI and Claude token usage from CSV exports and returns structured cost data with configurable budgets.

## Endpoint

```
GET /api/usage?provider=openai|claude|all
```

## Query Parameters

- `provider` (optional, default: `all`)
  - `openai` — Return OpenAI data only
  - `claude` — Return Claude data only
  - `all` — Return both providers

## Response

```json
{
  "ok": true,
  "updatedAt": "2026-04-12T13:00:00-07:00",
  "provider": "all",
  "openai": {
    "daily": [
      {
        "date": "2026-04-09",
        "model": "gpt-4o-2024-08-06",
        "input_tokens": 3608,
        "output_tokens": 564,
        "requests": 1,
        "total_cost": 15.27
      }
    ],
    "total": {
      "input_tokens": 11889,
      "output_tokens": 1570,
      "requests": 3,
      "total_cost": 47.76
    },
    "budget": 100.00,
    "remaining": 52.24,
    "percentUsed": "47.8"
  },
  "claude": {
    "daily": [
      {
        "date": "2026-04-08",
        "model": "claude-haiku-4-5-20251001",
        "input_tokens": 622,
        "output_tokens": 423,
        "requests": 1,
        "total_cost": 0.50
      }
    ],
    "total": {
      "input_tokens": 124419,
      "output_tokens": 44276,
      "requests": 7,
      "total_cost": 6.78
    },
    "budget": 50.00,
    "remaining": 43.22,
    "percentUsed": "13.6"
  },
  "config": {
    "openai_budget": 100.00,
    "claude_budget": 50.00
  }
}
```

## Data Sources

### OpenAI

Reads from: `website/data/completions_usage_*.csv`

File format (example):
```csv
start_time,end_time,start_time_iso,end_time_iso,model,input_tokens,output_tokens
1773446400,1773532800,2026-03-14T00:00:00+00:00,2026-03-15T00:00:00+00:00,gpt-4o-2024-08-06,3608,564
```

**Pricing used:**
- Default: gpt-4o-2024-08-06: $2.50 per 1M input tokens, $10.00 per 1M output tokens
- Override in `website/data/usage-config.json`

### Claude

Reads from: `website/data/claude_api_tokens_*.csv`

File format (example):
```csv
usage_date_utc,model_version,usage_input_tokens_no_cache,usage_input_tokens_cache_write_5m,usage_input_tokens_cache_write_1h,usage_input_tokens_cache_read,usage_output_tokens
2026-04-08,claude-haiku-4-5-20251001,622,0,0,0,423
```

Token aggregation:
```
input_tokens = usage_input_tokens_no_cache 
             + usage_input_tokens_cache_write_5m 
             + usage_input_tokens_cache_write_1h 
             + usage_input_tokens_cache_read
output_tokens = usage_output_tokens
```

**Pricing used:**
- claude-sonnet-4-6: $3.00 per 1M input, $15.00 per 1M output
- claude-haiku-4-5-*: $0.80 per 1M input, $4.00 per 1M output
- Override in `website/data/usage-config.json`

## Configuration

Edit `website/data/usage-config.json`:

```json
{
  "openai_budget": 100.00,
  "claude_budget": 50.00,
  "openai_pricing": {
    "gpt-4o": { "input": 2.50, "output": 10.00 },
    "gpt-4o-2024-08-06": { "input": 2.50, "output": 10.00 }
  },
  "claude_pricing": {
    "sonnet": { "input": 3.00, "output": 15.00 },
    "claude-sonnet-4-6": { "input": 3.00, "output": 15.00 },
    "haiku": { "input": 0.80, "output": 4.00 },
    "claude-haiku-4-5": { "input": 0.80, "output": 4.00 },
    "claude-haiku-4-5-20251001": { "input": 0.80, "output": 4.00 }
  }
}
```

The endpoint reloads this file on every request (no restart required).

## Caching

- Response is cached in-memory for 1 hour (3600000ms)
- Cache is invalidated if any CSV file is updated
- Manual cache clear: Restart the Vercel function (redeploy website/)

## Usage

### In Browser (HQ Dashboard)

```javascript
// Fetch data every 60 seconds
async function fetchUsageData() {
  const response = await fetch('/api/usage?provider=all');
  const data = await response.json();
  
  if (data.ok) {
    console.log('OpenAI:', data.openai.total.total_cost, '/', data.openai.budget);
    console.log('Claude:', data.claude.total.total_cost, '/', data.claude.budget);
  }
}

setInterval(fetchUsageData, 60000);
```

### Via cURL

```bash
# All data
curl https://www.hyo.world/api/usage

# OpenAI only
curl https://www.hyo.world/api/usage?provider=openai

# Claude only
curl https://www.hyo.world/api/usage?provider=claude
```

## Updating CSV Files

CSV files are read from `website/data/`. To update them:

### Option 1: Automated (via kai queue)
```bash
bash kai/queue/refresh-usage.sh
```

This script:
- Calls OpenAI and Anthropic billing APIs (if keys are set)
- Writes new CSV files
- Logs to `/tmp/hyo-usage-refresh.log`

### Option 2: Manual (download from cloud)

**OpenAI:**
1. Go to platform.openai.com → Billing → Usage
2. Export CSV for the date range
3. Save as `website/data/completions_usage_YYYY-MM-DD_YYYY-MM-DD.csv`

**Claude:**
1. Go to console.anthropic.com → Billing → API keys → Usage
2. Export CSV for the month
3. Save as `website/data/claude_api_tokens_YYYY_MM.csv`

After updating CSVs, the API will automatically pick up changes within 1 hour (or immediately if you redeploy).

## Error Handling

If CSV files are missing or malformed:

```json
{
  "ok": true,
  "openai": {
    "daily": [],
    "total": { "input_tokens": 0, "output_tokens": 0, "requests": 0, "total_cost": 0 },
    "budget": 100.00,
    "remaining": 100.00,
    "percentUsed": "0.0"
  },
  "claude": {
    "daily": [],
    "total": { "input_tokens": 0, "output_tokens": 0, "requests": 0, "total_cost": 0 },
    "budget": 50.00,
    "remaining": 50.00,
    "percentUsed": "0.0"
  }
}
```

The endpoint will return empty arrays and zero costs, but still return `"ok": true` with fallback defaults.

## Implementation Details

- **Language:** Node.js (Vercel Serverless)
- **Location:** `website/api/usage.js`
- **Dependencies:** Built-in (`fs`, `path`, `url`)
- **Caching:** In-memory `globalThis.__usageCache` with 1-hour TTL
- **Cost calculation:** Per-model, pre-computed by the endpoint

## Testing

```bash
# Local test (Node.js)
node website/api/usage.js

# Via curl (deployed)
curl https://www.hyo.world/api/usage | jq

# Filter by provider
curl https://www.hyo.world/api/usage?provider=openai | jq .openai
```
