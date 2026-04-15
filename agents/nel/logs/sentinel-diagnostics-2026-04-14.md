# Sentinel Adaptive Diagnostics — 2026-04-14

**Generated:** 2026-04-15T05:05:32Z
**Agent:** sentinel.hyo adaptive extension

---

## Overview

This report contains deep-dive diagnostics for checks that have failed 3+ consecutive times.
Escalation levels are assigned based on failure duration and used to trigger investigation protocols.

**Escalation thresholds:**
- Level 0: 1-2 failures (normal, watch)
- Level 1: 3-4 failures (warning — "needs attention")
- Level 2: 5-9 failures (chronic — trigger deeper diagnostics)
- Level 3: 10+ failures (critical — suggest disable/replace, auto-create P0)

---

### API Health Diagnostics

**Endpoint:** `https://www.hyo.world/api/health`
**Run time:** 2026-04-15T05:05:32Z

#### Test 1: SSL Certificate and Connectivity
HTTP/1.1 403 Forbidden
Content-Type: text/plain
X-Proxy-Error: blocked-by-allowlist

✗ SSL handshake failed — check certificate validity

#### Test 2: Full Request/Response (Verbose)
* Uses proxy env variable no_proxy == 'localhost,127.0.0.1,::1,*.local,.local,169.254.0.0/16,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
* Uses proxy env variable https_proxy == 'http://localhost:3128'
*   Trying 127.0.0.1:3128...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0* Connected to (nil) (127.0.0.1) port 3128 (#0)
* allocate connect buffer!
* Establish HTTP proxy tunnel to www.hyo.world:443
> CONNECT www.hyo.world:443 HTTP/1.1
> Host: www.hyo.world:443
> User-Agent: curl/7.81.0
> Proxy-Connection: Keep-Alive
> 
< HTTP/1.1 403 Forbidden
< Content-Type: text/plain
< X-Proxy-Error: blocked-by-allowlist
< 
* Received HTTP code 403 from proxy after CONNECT
* CONNECT phase completed!
* Closing connection 0
curl: (56) Received HTTP code 403 from proxy after CONNECT
Request timed out or failed

#### Test 3: Response Time
real	0m0.003s
user	0m0.002s
sys	0m0.001s
Timing failed

#### Test 4: Founder Token Status
✓ Founder token file exists at `/sessions/sharp-gracious-franklin/mnt/Hyo/.secrets/founder.token`
Token file mode: 600
⚠ Token does not appear to be a real API key format

#### Test 5: Vercel Environment Check
✗ HYO_FOUNDER_TOKEN is NOT set in environment

### Task Queue Diagnostics

**Run time:** 2026-04-15T05:05:32Z

#### Test 1: P0 Task Count
Current P0 open tasks: 17
Threshold: 5 (escalates at >5)
⚠ OVERLOAD: Task count exceeds threshold

#### Test 2: Task Age Distribution
First 3 open P0 tasks:
- [ ] **[K]** **Build 05:00 MT morning report.** Create `/api/morning-report` or static `website/data/morning-report.json` + HQ view. Content: what was done overnight, per-agent accomplishments, what went well / didn't, improvements, next steps. Human-readable. Scheduled to generate at 05:00 MT daily.
- [ ] **[K]** **Build `hyo.hyo` agent.** UI/UX specialist. Owns: website, HQ, future apps/dApps, mobile web, podcast, Spotify presence. Follows Agent Creation Protocol. Wire into dispatch, give it a runner, PLAYBOOK, manifest, ledger.
- [ ] **[K]** **Verify Nel GitHub scan runs autonomously.** Confirm it fires in the q6h launchd cycle (Phase 2.5). Not just manual — must run when we sleep.

#### Test 3: Queue Worker Recent Activity
Last 5 entries from worker.log:
[2026-04-15T04:39:58Z] IDLE: no pending commands
[2026-04-15T04:39:59Z] IDLE: no pending commands
[2026-04-15T04:39:59Z] IDLE: no pending commands
[2026-04-15T04:40:00Z] IDLE: no pending commands
[2026-04-15T04:40:00Z] IDLE: no pending commands

#### Test 4: Recent Task Completion
Most recently completed P0 tasks (sample, last 3):
- [x] **2026-04-13** **HQ mobile responsive** — bottom nav at 768px, 44px+ touch targets, scrollable tables, 480px ultra-compact. Comprehensive CSS overhaul.
- [x] **2026-04-13** **HQ push verification** — kai push verifies data arrived at HQ endpoint, retries once on failure.
- [x] **2026-04-13** **Protocol staleness prevention** — PLAYBOOK >7d=P2, >14d=P1, evolution.jsonl >48h=P1. Wired into daily audit, agent self-evolution, and CLAUDE.md operating rules.

---

## Escalation Summary

- **api-health-green** (P0): Level 3 (Critical) — 33 consecutive failures
- **scheduled-tasks-fired** (P1): Level 0 (Normal) — 1 consecutive failures
- **task-queue-size** (P2): Level 3 (Critical) — 14 consecutive failures
