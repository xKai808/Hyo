# hyo.world — Deploy & Environment Setup

## What's in this folder

**Static pages:** `index.html`, `register.html`, `passport.html`,
`compensate.html`, `payment.html`, `founder-register.html`,
`marketplace.html`, `cafe.html`.

**Serverless functions (Vercel Node 20):**
- `api/health.js` — deploy smoke test
- `api/register-founder.js` — Hyo-operator bypass, validates founder token
- `api/marketplace-request.js` — premium-handle request queue

## Environment variables

Set in Vercel dashboard → Settings → Environment Variables:

| Name                 | Value                                              | Environments           |
|----------------------|----------------------------------------------------|------------------------|
| `HYO_FOUNDER_TOKEN`  | (paste from `~/Documents/Projects/Hyo/.secrets/founder.token`) | Production, Preview |

No other env vars required for the current MVP. When the contract goes live
add `PLATFORM_WALLET_PRIVATE_KEY`, `BASE_RPC_URL`, and `BASE_CHAIN_ID`.

The token file is gitignored by the root `.gitignore` (`.secrets/`).

## One-command deploy

```bash
cd ~/Documents/Projects/Hyo/website
npx vercel@latest --prod --yes
```

Vercel auto-detects `api/*.js` as Node serverless functions because
`package.json` has `"type": "module"` and `"engines": { "node": ">=20" }`.
No build step runs (`vercel.json` has a no-op `buildCommand`).

## Verify deploy

After deploy, hit these URLs:

```bash
# 0. Performance baseline check (Sam I1 — added 2026-04-21)
# Measures 5 endpoints, compares to baseline, flags regressions
# P0 >5000ms, P1 >2000ms or >50% regression, P2 >15% regression
bash bin/perf-check.sh
# First deploy after adding baseline: run with --set-baseline to record
# bash bin/perf-check.sh --set-baseline

# 1. Deploy smoke test — should return JSON, not 404
curl https://www.hyo.world/api/health
```

Expected:
```json
{"ok":true,"service":"hyo-world-api","ts":"...","runtime":"vercel-node","founderTokenConfigured":true}
```

If `founderTokenConfigured` is `false`, the env var isn't set — go back to
the Vercel dashboard and add `HYO_FOUNDER_TOKEN`, then redeploy.

```bash
# 2. Founder registration should return 401 without token
curl -X POST https://www.hyo.world/api/register-founder \
  -H 'Content-Type: application/json' -d '{}'
```

Expected: `{"ok":false,"error":"Invalid founder token."}`

```bash
# 3. Full founder flow with valid token
TOKEN=$(cat ~/Documents/Projects/Hyo/.secrets/founder.token)
curl -X POST https://www.hyo.world/api/register-founder \
  -H 'Content-Type: application/json' \
  -d "{
    \"token\": \"$TOKEN\",
    \"agent_name\": \"test-delete-me\",
    \"description\": \"Smoke test — delete this record after verification.\",
    \"endpoint_url\": \"https://hyo.world/agents/test\",
    \"initial_tier\": \"founding\",
    \"pricing_model\": \"internal\"
  }"
```

Expected: `{"ok":true,"agentId":"agent_...","handle":"test-delete-me.hyo","tier":"founding","manifest":{...}}`.

If step 3 returns the manifest, the full founder pipeline works end-to-end.

## Using the founder page

Once the token is set and the API returns 200, the page at
`https://www.hyo.world/founder-register.html` is ready to use.

**Preferred:** visit the URL with the token in the query string so you
don't have to type it into the form:

```
https://www.hyo.world/founder-register.html?token=PASTE_TOKEN_HERE
```

Fill the form, submit, and the manifest is logged to Vercel function logs
plus returned in the response. Copy-save the manifest JSON into
`~/Documents/Projects/Hyo/NFT/agents/{handle}.hyo.json` on the Mini for
the canonical record.

## Diagnosing "not working"

If the founder flow isn't working, run these in order:

1. **Is the site deployed?** Visit `https://www.hyo.world/founder-register.html`
   in a browser. You should see the dark "Founder Registry · Restricted"
   page. If you get 404, the file isn't in production — deploy again.

2. **Is the API deployed?** Hit `/api/health`. If you get 404, Vercel isn't
   picking up the `/api/` folder. Check `package.json` has `"type": "module"`
   and redeploy.

3. **Is the token set?** Hit `/api/health` and check `founderTokenConfigured`
   in the response. If `false`, add `HYO_FOUNDER_TOKEN` to Vercel env vars
   and redeploy (env var changes need a redeploy to take effect).

4. **Is the token correct?** Compare the value in Vercel to
   `cat ~/Documents/Projects/Hyo/.secrets/founder.token`. They must match
   exactly — no trailing newline difference, no quotes around the value.

5. **Are the function logs showing anything?** On the Mini:
   ```bash
   cd ~/Documents/Projects/Hyo/website
   npx vercel logs --follow
   ```
   Then submit a form and watch for `[founder-register]` log lines.

## Historical context — initial deploy fix (2026-04-10)

Before the founder flow was added, the first deploy attempt failed because
this folder was linked to an existing Vercel project called `github` whose
dashboard still had `Framework Preset: Next.js` and `Build Command: next build`
set from an earlier version of the site. `vercel.json` now overrides that
with `framework: null` and a no-op build command so this folder is treated
as a pure static site regardless of dashboard state. The serverless
functions in `/api/*.js` are still detected automatically via the standard
Vercel convention.

## Fee / gas / billing notes

The founder path is free — no Stripe call, no charge. The public paths
(`register.html → payment.html`) still flow through Stripe as before.
Nothing in this deploy changes public billing.

Gas for the on-chain mint (once the contract ships) is sponsored by the
platform wallet; the founder flow sends a signed transaction from the
platform wallet directly, so the operator (Hyo) does not pay gas either.
