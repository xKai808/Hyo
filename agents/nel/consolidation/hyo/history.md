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

## 2026-04-25 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    30617 bytes
**Docs deployed:** 9 agent dirs

## 2026-04-26 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    23122 bytes
**Docs deployed:** 9 agent dirs

## 2026-04-27 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    27186 bytes
**Docs deployed:** 9 agent dirs

## 2026-04-28 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=0 in website/ | leaks=0 in NFT/
**HQ state:**    49264 bytes
**Docs deployed:** 9 agent dirs

## 2026-05-01 — nightly consolidation

**Sentinel:** passed=2 failed=2
findings:
- FAIL: .secrets dir mode=0700 (want 700)
- FAIL: founder.token mode=0600 (want 600)
**Cipher:** leaks=5 in website/
/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-29.md:19:/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-29.md:19:/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-28.md:41:/Users/kai/Documents/Projects/Hyo/kai/queue/completed/cmd-1777339979-242.json:6:  "stdout": "=== AETHERBOT_KEY env var ===\nSet: NO, Value: NOT_SET\n=== Key file ===\n-----BEGIN RSA PRIVATE KEY-----\n=== zshrc/env ===\n=== v255 timestamp format (ms vs seconds) ===\n186:# Session windows in MTN (all log timestamps are MTN):\n453:def create_signature(timestamp_ms: str, method: str, path: str) -> str:\n455:    message = f\"{timestamp_ms}{method.upper()}{path_without_query}\".encode(\"utf-8\")\n464:    timestamp_ms = str(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))\n466:    sig = create_signature(timestamp_ms, method, full_path)\n470:        \"KALSHI-ACCESS-TIMESTAMP\": timestamp_ms,\n505:        _last_ob_poll_ts = time.time()  # v254: record poll timestamp for exit timing delta\n2252:    _exit_submit_ts = time.time()  # v254: pre-submission timestamp\n2392:    Return the Unix timestamp of the most recently COMPLETED candle boundary.\n2393:    E.g. for 3m (180s) at 07:43:45 UTC \u2192 returns timestamp of 07:42:00 close.\n", | leaks=0 in NFT/
/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-29.md:20:/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-29.md:42:/Users/kai/Documents/Projects/Hyo/kai/queue/completed/cmd-1777339979-242.json:6:  "stdout": "=== AETHERBOT_KEY env var ===\nSet: NO, Value: NOT_SET\n=== Key file ===\n-----BEGIN RSA PRIVATE KEY-----\n=== zshrc/env ===\n=== v255 timestamp format (ms vs seconds) ===\n186:# Session windows in MTN (all log timestamps are MTN):\n453:def create_signature(timestamp_ms: str, method: str, path: str) -> str:\n455:    message = f\"{timestamp_ms}{method.upper()}{path_without_query}\".encode(\"utf-8\")\n464:    timestamp_ms = str(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))\n466:    sig = create_signature(timestamp_ms, method, full_path)\n470:        \"KALSHI-ACCESS-TIMESTAMP\": timestamp_ms,\n505:        _last_ob_poll_ts = time.time()  # v254: record poll timestamp for exit timing delta\n2252:    _exit_submit_ts = time.time()  # v254: pre-submission timestamp\n2392:    Return the Unix timestamp of the most recently COMPLETED candle boundary.\n2393:    E.g. for 3m (180s) at 07:43:45 UTC \u2192 returns timestamp of 07:42:00 close.\n",
/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-29.md:21:/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-28.md:41:/Users/kai/Documents/Projects/Hyo/kai/queue/completed/cmd-1777339979-242.json:6:  "stdout": "=== AETHERBOT_KEY env var ===\nSet: NO, Value: NOT_SET\n=== Key file ===\n-----BEGIN RSA PRIVATE KEY-----\n=== zshrc/env ===\n=== v255 timestamp format (ms vs seconds) ===\n186:# Session windows in MTN (all log timestamps are MTN):\n453:def create_signature(timestamp_ms: str, method: str, path: str) -> str:\n455:    message = f\"{timestamp_ms}{method.upper()}{path_without_query}\".encode(\"utf-8\")\n464:    timestamp_ms = str(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))\n466:    sig = create_signature(timestamp_ms, method, full_path)\n470:        \"KALSHI-ACCESS-TIMESTAMP\": timestamp_ms,\n505:        _last_ob_poll_ts = time.time()  # v254: record poll timestamp for exit timing delta\n2252:    _exit_submit_ts = time.time()  # v254: pre-submission timestamp\n2392:    Return the Unix timestamp of the most recently COMPLETED candle boundary.\n2393:    E.g. for 3m (180s) at 07:43:45 UTC \u2192 returns timestamp of 07:42:00 close.\n", | leaks=0 in NFT/
/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-29.md:44:/Users/kai/Documents/Projects/Hyo/kai/queue/completed/cmd-1777339979-242.json:6:  "stdout": "=== AETHERBOT_KEY env var ===\nSet: NO, Value: NOT_SET\n=== Key file ===\n-----BEGIN RSA PRIVATE KEY-----\n=== zshrc/env ===\n=== v255 timestamp format (ms vs seconds) ===\n186:# Session windows in MTN (all log timestamps are MTN):\n453:def create_signature(timestamp_ms: str, method: str, path: str) -> str:\n455:    message = f\"{timestamp_ms}{method.upper()}{path_without_query}\".encode(\"utf-8\")\n464:    timestamp_ms = str(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))\n466:    sig = create_signature(timestamp_ms, method, full_path)\n470:        \"KALSHI-ACCESS-TIMESTAMP\": timestamp_ms,\n505:        _last_ob_poll_ts = time.time()  # v254: record poll timestamp for exit timing delta\n2252:    _exit_submit_ts = time.time()  # v254: pre-submission timestamp\n2392:    Return the Unix timestamp of the most recently COMPLETED candle boundary.\n2393:    E.g. for 3m (180s) at 07:43:45 UTC \u2192 returns timestamp of 07:42:00 close.\n",
/Users/kai/Documents/Projects/Hyo/website/docs/consolidation/2026-04-28.md:41:/Users/kai/Documents/Projects/Hyo/kai/queue/completed/cmd-1777339979-242.json:6:  "stdout": "=== AETHERBOT_KEY env var ===\nSet: NO, Value: NOT_SET\n=== Key file ===\n-----BEGIN RSA PRIVATE KEY-----\n=== zshrc/env ===\n=== v255 timestamp format (ms vs seconds) ===\n186:# Session windows in MTN (all log timestamps are MTN):\n453:def create_signature(timestamp_ms: str, method: str, path: str) -> str:\n455:    message = f\"{timestamp_ms}{method.upper()}{path_without_query}\".encode(\"utf-8\")\n464:    timestamp_ms = str(int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000))\n466:    sig = create_signature(timestamp_ms, method, full_path)\n470:        \"KALSHI-ACCESS-TIMESTAMP\": timestamp_ms,\n505:        _last_ob_poll_ts = time.time()  # v254: record poll timestamp for exit timing delta\n2252:    _exit_submit_ts = time.time()  # v254: pre-submission timestamp\n2392:    Return the Unix timestamp of the most recently COMPLETED candle boundary.\n2393:    E.g. for 3m (180s) at 07:43:45 UTC \u2192 returns timestamp of 07:42:00 close.\n", | leaks=0 in NFT/
**HQ state:**    54709 bytes
**Docs deployed:** 9 agent dirs
