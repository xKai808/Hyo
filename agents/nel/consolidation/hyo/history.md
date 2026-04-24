# Hyo — Consolidation History

**Purpose:** Compounding nightly log of the Hyo platform. Each entry builds on the last. Read top-down to understand trajectory; read bottom-up for recency.

---

## 2026-04-12 — Foundation night

**What exists today:**
- hyo.world live on Vercel (static HTML + serverless functions)
- Founder registration bypass (page + API + token) tested in prod
- HQ dashboard v6 — auth-gated, data-driven, per-agent views, document viewer, clickable activity feed
- Static JSON data layer (`website/data/hq-state.json`) for persistence across deploys
- Premium name marketplace page + API
- Three registry spec docs (CreditSystem, Marketplace, Reviews)

**System improvements since last consolidation:**
- First consolidation — baseline established
- Gitwatch auto-commit/push running via `bin/watch-commit.sh`
- Deploy hook wired: push to main → Vercel rebuild
- No-cache meta tags on HQ to kill browser caching issues

**What's compounding:**
- Every agent run now writes to `hq-state.json` → dashboard shows real data without manual push
- Document viewer means every run's output is permanently browsable at `hyo.world/viewer`
- Gitwatch means Kai edits deploy automatically — zero manual steps

**What's degrading or stuck:**
- No persistent storage for registrations (Vercel function logs only — ephemeral)
- HyoRegistry.sol not deployed on-chain yet
- No shared database — everything is flat files
- Credits section has zero data (no usage tracking wired)

**Sentinel findings (platform-wide):**
- API health: ok, token wired
- `.secrets/` dir: 700 ✓
- `founder.token`: 600 ✓

**Cipher findings (platform-wide):**
- 0 leaks detected
- No exposed secrets in website/ directory













## 2026-04-12 — nightly consolidation

**Sentinel:** passed=3 failed=1
findings:
- FAIL: API health endpoint unreachable
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:** 2712 bytes
**Docs deployed:** 6 agent dirs


## 2026-04-13 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**     4330 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-14 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**     5413 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-15 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**     6716 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-16 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**     8236 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-18 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    12562 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-19 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    18114 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-20 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    29658 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-21 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    29095 bytes
**Docs deployed:** 8 agent dirs

## 2026-04-22 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    43627 bytes
**Docs deployed:** 9 agent dirs

## 2026-04-23 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    42647 bytes
**Docs deployed:** 9 agent dirs

## 2026-04-24 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    42654 bytes
**Docs deployed:** 9 agent dirs
