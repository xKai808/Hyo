# Vercel KV Setup — HQ State Persistence

## Why

HQ (`/api/hq`) previously stored all agent data in `globalThis` (in-memory only).
Vercel functions cold-start after ~5 minutes of inactivity — wiping all state.
Sam W2 shipped 2026-04-21: `/api/hq` now uses Vercel KV as a persistence layer.

Once KV is provisioned and env vars are set, agent pushes **survive cold starts**.

## Current state (before KV provisioned)

- `/api/health` returns `"kv_connected": false, "persistence": "in-memory-only"`
- All agent pushes still work — stored in memory until next cold start
- Behavior identical to before this change

## To activate (3 steps)

### Step 1: Create KV store

1. Go to [vercel.com/dashboard](https://vercel.com/dashboard)
2. Click **Storage** → **Create Database** → **KV**
3. Name: `hyo-hq-store` | Region: `iad1` (US East, closest to Vercel default)
4. Click **Create**

### Step 2: Link to your project

1. In the KV dashboard, click **Connect Project**
2. Select the `hyo-world` project
3. Choose environments: **Production** and **Preview**
4. Click **Connect** — Vercel auto-adds `KV_REST_API_URL` and `KV_REST_API_TOKEN`

### Step 3: Redeploy

```bash
cd ~/Documents/Projects/Hyo/website
npx vercel@latest --prod --yes
```

### Verify

```bash
curl https://www.hyo.world/api/health
# Should show: "kv_connected": true, "persistence": "vercel-kv"
```

## How it works

- **Cold start**: `initKV()` loads `@vercel/kv`, `hydrateFromKV()` fetches `hq:store` key
- **Every write** (`push`, `hyo-message`): `syncToKV()` writes back fire-and-forget
- **No KV**: falls through to in-memory silently — zero behavior change
- **KV failure**: warn to console, continue with in-memory — never blocks responses

## Free tier limits

Vercel KV free tier: 256 MB storage, 30k requests/day, 1 database.
HQ state is small (~50 KB max). Free tier will last indefinitely at current scale.
