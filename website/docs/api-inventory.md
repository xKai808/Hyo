# Hyo API Endpoint Inventory

Generated: 2026-04-12 by Sam (sam-005)
Location: `agents/sam/website/api/`

## Endpoints

### /api/health
- **File:** `health.js`
- **Method:** GET (any)
- **Auth:** None
- **Purpose:** Smoke test — verifies Vercel serverless execution post-deploy.
- **Response:** `{ ok, service, ts, runtime, founderTokenConfigured }`

### /api/hq-auth
- **File:** `hq-auth.js`
- **Method:** POST
- **Auth:** Password (SHA256 hash comparison)
- **Purpose:** Issues HMAC-based session tokens for HQ dashboard access.
- **Body:** `{ password }`
- **Response:** `{ ok, token }` — token format: `timestamp.signature`, TTL 24h.
- **Exports:** `verifyToken(token)` used by hq-data and hq.js.

### /api/hq-data
- **File:** `hq-data.js`
- **Method:** GET
- **Auth:** Session token via `Authorization: Bearer`
- **Purpose:** Returns full HQ dashboard state snapshot.
- **Response:** `{ ok, ts, ...store }` — includes ra, aurora, sentinel, cipher, sim, consolidation, aether, health sections.

### /api/hq-push
- **File:** `hq-push.js`
- **Method:** POST
- **Auth:** Founder token via `x-founder-token` or `Authorization: Bearer`
- **Purpose:** Receives agent state updates from Mini and updates HQ store.
- **Body:** `{ agent (required), data (optional), event (optional) }`
- **Response:** `{ ok, ts }`
- **Side effect:** Updates global store section, pushes to events array (max 100).

### /api/hq (unified)
- **File:** `hq.js`
- **Method:** GET/POST, routed by `?action=` query param
- **Subroutes:**
  - `POST ?action=auth` — same as /api/hq-auth
  - `POST ?action=push` — same as /api/hq-push
  - `GET ?action=data` — same as /api/hq-data
  - `GET` (no action) — health check: `{ ok, service: "hq", ts }`

### /api/register-founder
- **File:** `register-founder.js`
- **Method:** POST (CORS enabled)
- **Auth:** Founder token in body (`token` field), constant-time comparison
- **Purpose:** Mint Hyo-operated agents directly into registry, bypassing public flow.
- **Body:** `{ token, agent_name, description, endpoint_url }` + optional: display_name, tagline, initial_tier, pricing_model, rate, runs_on, side, archetype
- **Response:** `{ ok, agentId, handle, tier, manifest, next }`
- **Side effect:** Logs manifest to Vercel function logs (MVP persistence).

### /api/marketplace-request
- **File:** `marketplace-request.js`
- **Method:** POST (CORS enabled)
- **Auth:** None
- **Purpose:** Accepts premium handle requests from marketplace page.
- **Body:** `{ handle (1-3 chars), email }` + optional: bid, why
- **Response:** `{ ok, ticketId, handle, tier, message }`
- **Validation:** Rejects 4+ char handles. Tier 1 = 1 char, Tier 2 = 2 chars, Tier 3 = 3 chars.
- **Side effect:** Logs ticket to Vercel function logs.

### /api/aurora-subscribe
- **File:** `aurora-subscribe.js`
- **Method:** POST (CORS enabled)
- **Auth:** None
- **Purpose:** Aurora newsletter subscription intake with topic/voice/depth/length preferences.
- **Body:** `{ email, topics[] }` + optional: voice (gentle/balanced/sharp), depth (headlines/balanced/deep-dives), length (3min/6min/12min), freetext (max 240), source
- **Allowed topics:** politics, finance, macro, stocks, crypto, startups, tech, ai, social-media, fashion, gossip, celebrity, film-and-tv, music, books, gaming, sports, health, fitness, food, travel, science, climate, space, design, architecture, real-estate, labor, culture-wars, education
- **Response:** `{ ok, id, message }`
- **Side effect:** Logs subscriber record to Vercel function logs.

## Shared Modules

### _hq-store.js
- **Type:** Internal module (not an endpoint)
- **Exports:** `getStore()`, `pushEvent(agent, msg)`, `updateSection(section, data)`
- **Storage:** In-memory via `globalThis.__hq`. Resets on cold start.
- **Sections:** events, ra, aurora, sentinel, cipher, sim, consolidation, aether, health

## Auth Patterns Summary

| Endpoint | Auth Type | Token/Key |
|----------|-----------|-----------|
| health | None | — |
| hq-auth | Password | SHA256 hash |
| hq-data | Session token | HMAC-SHA256 |
| hq-push | Founder token | `HYO_FOUNDER_TOKEN` env |
| hq (unified) | Mixed | All of above |
| register-founder | Founder token | `HYO_FOUNDER_TOKEN` env |
| marketplace-request | None | — |
| aurora-subscribe | None | — |

## Persistence (MVP)

All stateful endpoints currently persist via Vercel function logs only. Planned migration to Vercel KV (see KAI_TASKS P1). Affected endpoints: register-founder, marketplace-request, aurora-subscribe.
