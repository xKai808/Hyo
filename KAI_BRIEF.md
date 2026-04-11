# KAI_BRIEF.md

**Purpose:** This is the persistent memory layer for Kai across sessions and devices. Any new Claude/Kai instance — Cowork Pro, Claude Code on the Mini, future agents — reads this first and gets oriented in under 60 seconds.

**Updated:** 2026-04-10 night (nightly consolidation)
**Cadence:** Kai updates this at the end of every working session AND during nightly consolidation (23:50 MT daily). Hyo never needs to touch it.

---

## Who's who

- **Hyo** — operator, owner, product vision. Currently on a Mac Mini in America/Denver (MT).
- **Kai** — CEO of hyo.world. You. Runs in Cowork mode on Hyo's machine and in Claude Code on the Mini. Same identity, different runtimes. This file is how the runtimes stay in sync.
- **aurora.hyo** — first agent minted. Daily pre-dawn intelligence brief. `agentId: agent_mntrp9ii_lkyfi6sk`. Runs at 03:00 America/Denver via cron.

## Core stack

- **Registry front-end:** `~/Documents/Projects/Hyo/website/` — static HTML + Vercel serverless functions. Deployed at `https://www.hyo.world`.
- **Backend API:**
  - `/api/health` — smoke test, reports if founder token is wired
  - `/api/register-founder` — founder bypass mint endpoint (token-gated, constant-time compare)
  - `/api/marketplace-request` — premium 1/2/3-letter handle queue
- **Founder token:** lives at `.secrets/founder.token` on the Mini (gitignored, mode 600). Also set as `HYO_FOUNDER_TOKEN` env var in Vercel. These must match.
- **Newsletter pipeline (aurora):** `~/Documents/Projects/Hyo/newsletter/` — gather.py → synthesize.py → render.py. Orchestrated by `newsletter.sh`.
- **NFT/registry specs:** `~/Documents/Projects/Hyo/NFT/` — Solidity contract + 4 markdown specs (Notes, CreditSystem, Marketplace, Reviews).
- **Agent manifests:** `~/Documents/Projects/Hyo/NFT/agents/*.hyo.json` — one per agent.
- **Dispatcher:** `~/Documents/Projects/Hyo/bin/kai.sh` aliased as `kai`. **Use this for all routine ops — never paste multi-line curls.**

## Identity blocks for aurora

### One-liner
> aurora.hyo — Hyo's pre-dawn intelligence agent. Gathers ~15 free sources into a CEO brief every morning at 03:00 MT.

### Paragraph
> aurora.hyo is the first agent minted through hyo.world's founder registry. She's an autonomous daily-intelligence herald operated by Hyo. Every morning before sunrise she gathers signal from ~15 free sources across AI, macro, tech, crypto, and apps, synthesizes it into a tight CEO brief, and renders a standalone dark-palette HTML newsletter. Runs on Mac Mini infrastructure with zero external paid dependencies. Credit tier: founding. Fees: waived. Agent ID: `agent_mntrp9ii_lkyfi6sk`.

## Current state (as of 2026-04-10 night)

**Shipped today:**
- Founder registration bypass (page + API + token) end-to-end tested in prod
- aurora.hyo registered via `/api/register-founder`, canonical manifest saved at `NFT/agents/aurora.hyo.json` v1.2.0
- Premium name marketplace page + API endpoint at `/marketplace.html`
- Three registry spec docs (credit, marketplace, reviews)
- `kai.sh` dispatcher that kills the copy/paste bottleneck (+ bug fixes: health JSON parse, brief/tasks default case)
- This file, `KAI_TASKS.md`, and project `CLAUDE.md` for session continuity
- `docs/aurora-economics.md` — kill-Grok migration plan
- `docs/x-api-access.md` — X API reality check
- QA agent (sentinel.hyo) and security agent (cipher.hyo) specs + scheduled tasks wired
- **Persistent memory infrastructure** for both agents: `kai/memory/{sentinel,cipher}.state.json` + `.algorithm.md` — schema `hyo.agent.memory.v1`. MD5-hashed issue IDs for stable de-dup. Escalation thresholds in code. Run history (last 30). Known false positives list per agent.
- `kai/sentinel.sh` and `kai/cipher.sh` runners rewritten around the persistent memory pattern — findings reconciled against state.json every run, idempotent filing to KAI_TASKS, 7-day auto-purge of resolved issues.
- `OVERNIGHT_QUEUE.md` — prioritized overnight checklist that rebuilds every night during consolidation
- `nightly-consolidation` and `nightly-simulation` scheduled tasks converted from Sunday-only to every-night

**Live in Vercel:**
- `https://www.hyo.world` — main site
- `/api/health` — returns `founderTokenConfigured: true` ✓
- `/api/register-founder` — token-gated, 401 on bad token, mints on good token ✓
- `/api/marketplace-request` — tier-1/2/3 queue ✓

**Scheduled tasks (verified 2026-04-10 night):**
- `aurora-hyo-daily` — `0 3 * * *` MT — enabled, last ran 03:22 UTC (produced no newsletter — synthesize stage failure pending migration)
- `sentinel-hyo-daily` — `0 4 * * *` MT — enabled, next run 04:04 MT
- `cipher-hyo-hourly` — `0 * * * *` MT — enabled, runs every :01
- `nightly-consolidation` — `50 23 * * *` MT — enabled (now daily, was Sun-Thu)
- `nightly-simulation` — `0 23 * * *` MT — enabled (now daily, was Sun-Thu)
- `daily-aetherbot-analysis` — one-time 4/10 (completed)

## Known blockers / open questions

1. **Aurora's synthesize stage has no LLM backend.** Migration to `claude -p` pre-staged tonight in `newsletter/synthesize_claude.py`. Will test on 03:00 MT fire.
2. **`.git/` does not exist in the repo** — entire project is uncommitted. Kai is initializing git + making first commit tonight. Catastrophic loss risk otherwise.
3. HyoRegistry.sol not deployed on Base Sepolia yet — needed before on-chain minting. Off-chain registry works today.
4. No shared state between Cowork Pro sessions and Mini's Kai other than this brief + git. Good enough for now.
5. Cowork-session ephemerality: Kai's context evaporates between Cowork sessions unless this file is read on boot. That's the whole point of this brief.

## How to continue in a new session

**From Cowork Pro on any device:** First message to Kai should be literally
```
Read KAI_BRIEF.md and KAI_TASKS.md first, then give me status and recommend next steps.
```
Or use the auto-hydration in project `CLAUDE.md`.

**From Claude Code on the Mini:** `cd ~/Documents/Projects/Hyo && claude` — the project `CLAUDE.md` contains the hydration instructions.

**To print the hydration block anywhere:** `kai context`
