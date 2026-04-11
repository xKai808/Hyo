# Hyo Daily Newsletter — MVP

**Status:** scaffolding, pre-v0.1
**Goal:** deliver a daily intelligence brief to the operator by 05:00 MDT covering economics, stocks, macro, tech, AI, agentic AI, apps, new skills/websites, and viral social content — with analysis, "how to get ahead," and forward-looking synthesis.

## Cost model

**$0 marginal, free-first pipeline.** We scrape public APIs and RSS feeds for raw data, then use the existing Claude Max plan (Cowork session, no API key) or a single cheap Grok 4 Fast call for synthesis. Target total daily cost: **$0.00–$0.03**.

Avoid per-topic API calls. One consolidated synthesis pass on all collected data, max 50k input tokens.

## Architecture

```
03:00 MDT  gather.py    → scrape free sources → /Projects/Kai/intelligence/YYYY-MM-DD.jsonl
03:30 MDT  synthesize   → Cowork session reads the JSONL → writes markdown + html
05:00 MDT  deliver      → newsletter is already on disk; operator reads/plays on wake
```

## Pipeline stages

### 1. Gather (free sources only)

`gather.py` runs on the Mini via cron at 03:00 MDT. Outputs newline-delimited JSON to:
`/Users/kai/Documents/Projects/Kai/intelligence/YYYY-MM-DD.jsonl`

Each line: `{"source": "...", "topic": "...", "title": "...", "url": "...", "summary": "...", "score": 0.0, "timestamp": "..."}`

Sources (all free, no API key required):

| Source | What it gives | Endpoint |
|---|---|---|
| HN Algolia | Top tech/AI/startup stories + comment counts | `https://hn.algolia.com/api/v1/search_by_date?tags=front_page` |
| arxiv.org RSS | AI/ML papers | `https://arxiv.org/rss/cs.AI` + `cs.LG` + `cs.CL` |
| Reddit `.json` | Crowd pulse: r/singularity, r/LocalLLaMA, r/macro, r/artificial | `https://www.reddit.com/r/<sub>/top.json?t=day` |
| GitHub Trending (scrape) | Repos rising today | `https://github.com/trending?since=daily` |
| Product Hunt RSS | New apps/skills | `https://www.producthunt.com/feed` |
| FRED API (free, key optional) | Macro indicators | `https://api.stlouisfed.org/fred/series/observations` |
| CoinGecko free | Crypto moves | `https://api.coingecko.com/api/v3/coins/markets` |
| Yahoo Finance (unofficial) | Index/ETF moves | `https://query1.finance.yahoo.com/v7/finance/quote?symbols=SPY,QQQ,TLT,GLD,BTC-USD` |
| nitter/RSS bridges | Viral X content | varies, fallback to scraped public posts |

### 2. Synthesize

One call at 03:30 MDT with the full JSONL as context. System prompt lives at `prompts/synthesize.md`.

Expected output: markdown newsletter with these sections:
1. **Top 5 Signals** — the most important things that happened in the last 24h, with "why it matters"
2. **Macro & Markets** — rates, indices, key moves, what to watch
3. **AI & Agentic AI** — model releases, capability jumps, agent framework updates
4. **Tech & Apps** — new products, viral launches, things Hyo could learn from
5. **Skills & Content** — new ways to get ahead (frameworks, tools, methods)
6. **Forward Look** — 7-day horizon: what to watch, what to position for, what the operator should decide today
7. **CEO Note** — one paragraph, written TO the operator, recommending at most one action for the day

### 3. Deliver

- Write markdown to `/Users/kai/Documents/Projects/Hyo/newsletters/YYYY-MM-DD.md`
- Render HTML copy to `/Users/kai/Documents/Projects/Hyo/newsletters/YYYY-MM-DD.html` (shareable if hyo.world/daily later)
- Append a one-line entry to the daily notes log on the Mini so Cowork sessions know the newsletter landed
- Optionally: ship to hyo.world/daily/YYYY-MM-DD when website is fixed

## Data accumulation

Every gather run also appends normalized records to a long-lived rolling database at:
`/Users/kai/Documents/Projects/Kai/intelligence/all.jsonl`

This is the accumulating "CEO brain" — the raw substrate the synthesis model uses to get smarter about what matters to us specifically. Over 30+ days this becomes a real intelligence asset, not just a daily habit.

## Files

- `README.md` — this document
- `gather.py` — scraper (run on Mini, cron 03:00 MDT)
- `prompts/synthesize.md` — prompt for the synthesis pass
- `render.py` — markdown → HTML with Hyo styling
- `sources.yml` — configurable source list (add/remove without editing code)
- `.env.example` — optional FRED key, Grok key if we add a weekly cross-check

## Run order once bridge is live

1. Claude Code MCP bridge registered in Cowork → I can read/write anywhere on the Mini
2. I install the Python deps (`feedparser`, `requests`, `beautifulsoup4`, `pyyaml`) via bridge
3. I create the cron entries for 03:00 gather + 03:30 synthesize (synthesize fires a Cowork scheduled task that picks up the JSONL and writes the newsletter)
4. First dry run tonight after 03:00 MDT to verify gather.py output shape
5. First real newsletter lands 05:00 MDT tomorrow

## Post-MVP

- If synthesis quality is strong after 5-7 days, expand: custom versions for other people (paid), daily 15-60min podcast (text-to-speech on newsletter, upload to Spotify/YouTube), Hyo as umbrella brand
- Add Grok weekly cross-check (Friday: "was the week's analysis accurate?") — low cost, high value for building trust in the system
