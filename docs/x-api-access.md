# docs/x-api-access.md

**Written:** 2026-04-10
**Verdict:** X Premium ($8/mo) does NOT include X API access. If you need X API access, you pay separately. This is an important correction.

---

## What you get for $8/mo

X Premium (formerly Twitter Blue) at ~$8/mo on the web tier gives you:
- Blue checkmark verification
- Longer posts, edit button, 2x algorithmic boost
- Ad revenue sharing (after thresholds)
- Grok access in the X app (chat only, not API)

What you do NOT get: **any form of X API access**. This is a common misconception because "Premium" sounds like it should include developer features, but the API is a separate product with its own billing.

## What X API access actually costs (as of Feb 2026)

As of February 6, 2026, X replaced the tiered subscription model with **pay-per-use as the default** for all new developers.

- **New developers**: directed to the pay-per-use Developer Console. No free tier, no Basic tier option. Buy credits upfront, charged per API call, capped at 2M post reads/month.
- **Legacy Basic** (for existing subscribers only): $200/mo, 7-day search access, allows publishing at volume.
- **Pro**: $5,000/mo — 1M tweets, full archive search
- **Enterprise**: $42,000+/mo — custom

Source: [X API Pricing 2026 guide](https://www.xpoz.ai/blog/guides/understanding-twitter-api-pricing-tiers-and-alternatives/) and [postproxy.dev 2026 breakdown](https://postproxy.dev/blog/x-api-pricing-2026/).

## What this means for aurora

Aurora originally had X in mind as a gather source for the daily brief ("what is tech Twitter saying this morning"). Given the new pricing, **that path is not economical for a single-operator project**. Three options:

### Option A: skip X entirely (recommended)
The aurora brief already gathers from ~15 free sources (HN, arxiv, RSS, Reddit, GitHub trending, CoinGecko, Yahoo Finance, FRED). X adds signal but not uniquely — most high-quality tech discourse surfaces in HN and RSS within hours. Cost to skip: $0. Signal loss: low.

### Option B: scrape read-only via unofficial library
Libraries like `snscrape` historically did this but have been aggressively rate-limited. **Not recommended** — fragile, ToS-adjacent, will break.

### Option C: use a third-party data provider
TweetAPI, tweetarchivist, netrows, etc. offer lower-cost tiers by reselling access. Typically $20-50/mo for modest volume. **Worth revisiting** only if aurora monetizes past $100/mo and X signal becomes provably valuable.

## Action items

1. **Cancel X Premium** if the only reason you're paying is because you thought it included API access. It doesn't. Keep it only if the verification or posting features are worth $8/mo on their own.
2. **Skip X in aurora's gather stage** for now. Remove from `sources.json` if present.
3. **Revisit in 3 months** once aurora has revenue — at that point, $20-50/mo for a third-party provider might be justified.

## How to obtain a real X API key (if you ever decide to)

For the legacy Basic tier (if you were grandfathered in), or pay-per-use for new devs:

1. Go to https://developer.x.com and sign in with the X account that will own the app
2. Apply for a developer account — you'll describe your use case in 50-200 words
3. Once approved, create a Project and then an App within that project
4. App → "Keys and tokens" → generate:
   - API Key & Secret (OAuth 1.0a)
   - Bearer Token (OAuth 2.0, read-only)
   - Access Token & Secret (OAuth 1.0a, for user-context actions)
5. Store the bearer token in `.secrets/x-api.token` (gitignored, mode 600)
6. Add `X_BEARER_TOKEN` to `.env.example` with a placeholder
7. Use from Python: `headers = {"Authorization": f"Bearer {os.environ['X_BEARER_TOKEN']}"}`

**Do not do this until aurora has revenue to justify it.** The free/pay-per-use tier's rate limits are too restrictive for anything beyond demo use.

## Sources

- [X API Pricing 2026: All Tiers Compared - xpoz.ai](https://www.xpoz.ai/blog/guides/understanding-twitter-api-pricing-tiers-and-alternatives/)
- [X API Pricing 2026: New Pay-As-You-Go - wearefounders.uk](https://www.wearefounders.uk/the-x-api-price-hike-a-blow-to-indie-hackers/)
- [Twitter Subscription Features 2026 - tweetarchivist](https://www.tweetarchivist.com/twitter-subscription-features-guide)
- [How to Get X API Key 2026 - elfsight](https://elfsight.com/blog/how-to-get-x-twitter-api-key-in-2026/)
