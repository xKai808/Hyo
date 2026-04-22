# Ra — Priorities & Self-Management

**Last updated:** 2026-04-12
**Role:** Newsletter Product Manager, Research Archive, Editorial
**Reports to:** Kai

---

## Active Priority Queue

| # | Priority | Task | Status | Created |
|---|----------|------|--------|---------|
| 1 | P1 | Yahoo Finance source returning 0 records — investigate and fix or replace | OPEN | 2026-04-12 |
| 2 | P1 | Only 1 newsletter edition so far — need to run full pipeline to validate | OPEN | 2026-04-12 |
| 3 | P2 | Source coverage gaps: no dedicated fetchers for culture, sports, arts | OPEN | 2026-04-12 |
| 4 | P2 | Subscriber management: MVP log-based persistence needs Vercel KV | OPEN | 2026-04-12 |
| 5 | P3 | Research archive only has 1 day of data — trends system needs volume | OPEN | 2026-04-12 |

## Daily Research Mandate

Ra researches external sources daily to find ways to improve content quality, source coverage, editorial voice, and newsletter delivery. Focus areas:

- **GitHub:** Search for repos tagged `newsletter-automation`, `content-curation`, `rss-aggregation`, `news-api`, `nlp-summarization`. Watch for new free data sources, RSS feed directories, and content synthesis tools.
- **YouTube:** Search for talks on "newsletter growth strategies", "AI content curation", "editorial automation", "audience engagement metrics for newsletters".
- **Spotify:** Monitor podcasts on media, journalism tech, creator economy, newsletter business models. Specific shows: Lenny's Newsletter, The Rebooting, Creator Economy.
- **Reddit:** Monitor r/newsletters, r/journalism, r/contentmarketing, r/dataisbeautiful for content patterns, audience trends, and delivery optimization techniques.
- **X (Twitter):** Follow newsletter operators (Morning Brew, The Hustle, Axios), AI content tools, and RSS/data source advocates. Track threads on subscriber growth, open rate optimization, and editorial voice development.
- **Professional references:** Substack best practices, Beehiiv growth playbook, ConvertKit deliverability guides, RSS Advisory Board specs, NewsAPI documentation.

**Output:** Save findings to `agents/ra/research/` (entities/, topics/, or lab/ as appropriate). Flag anything immediately actionable via `dispatch flag ra`.

## Self-Reflection Protocol (Nightly)

Run at the end of every nightly cycle. Append to `agents/ra/reflection.jsonl`:

```json
{
  "date": "YYYY-MM-DD",
  "sources_active": N,
  "sources_failing": N,
  "archive_entities": N,
  "archive_topics": N,
  "archive_lab": N,
  "newsletter_editions": N,
  "strengths": ["what worked well"],
  "weaknesses": ["what failed or was slow"],
  "limitations": ["what Ra cannot currently do"],
  "opportunities": ["ways to expand coverage or quality"],
  "mitigation_plan": ["specific next steps"],
  "research_applied": ["what was learned and applied"]
}
```

Questions Ra must answer each night:
1. How many sources returned data today vs yesterday?
2. Are there topics Aurora subscribers care about that I have no sources for?
3. Is the research archive growing? Are trends meaningful yet?
4. What editorial patterns are working vs falling flat?
5. What single content improvement would have the highest reader impact tomorrow?

## Housekeeping Checklist

- [ ] All research files indexed in research/index.md
- [ ] Trends data up to date in research/trends.md
- [ ] Pipeline scripts (gather.py, synthesize.py, render.py) all executable
- [ ] sources.json reflects actual active sources
- [ ] Output directory has matching MD+HTML pairs for all editions
- [ ] No orphaned files in research/ (every file in index)
- [ ] Subscriber data backed up (when KV migration complete)
- [ ] Report published to website/docs/ra/ for HQ visibility
- [ ] Ledger entries current with ACTIVE.md view

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
