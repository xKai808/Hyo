# KAI_BRIEF.md

**Purpose:** This is the persistent memory layer for Kai across sessions and devices. Any new Claude/Kai instance — Cowork Pro, Claude Code on the Mini, future agents — reads this first and gets oriented in under 60 seconds.

**Updated:** 2026-04-13 ~21:30 MT (session 8 final — constitutional v3.1, all memory saved)
**Cadence:** Kai updates this at the end of every working session AND during nightly consolidation (23:50 MT daily). Hyo never needs to touch it.
**Last audit:** 2026-04-13T03:35Z — 0 P0, 2 P1, 12 P2 issues found. Newsletter production still blocked. Duplicate flags flooding queue (40+ items, 5 unique issues). See daily-audit-2026-04-13.md.
**Last healthcheck:** 2026-04-14T00:10:00-06:00 — **ISSUES: 1 P0, 3 P1, 4 P2.** 6TH CONSECUTIVE UNHEALTHY CHECK — no improvement since monitoring began. P0: agents/nel/security gitignore gap (nel-001) — persists across 6+ checks, zero real remediation. P1: Newsletter missed TWO consecutive days (04-12 + 04-13) — now 48+ hours without output. P1: /api/hq 401 still unresolved. P1: Sim-ack masking — 20+ tasks show "DELEGATED — all clear" but nothing is actually fixed. NEW P2: flag-aether-001 triple-logging every 15 min (21+ entries in 2 hours). NEW P2: Sentinel found 2 projects with test failures. Queue completed jobs reference stale session paths — remediation commands are no-ops. **ROOT CAUSE UNCHANGED: Cowork sandbox cannot execute on the Mini. All "delegated" tasks are handshake-only. Real remediation requires an interactive Kai session on the Mini with queue worker access.** Next interactive session MUST: (1) actually fix .gitignore on Mini, (2) diagnose + fix API 401, (3) run newsletter pipeline manually, (4) deduplicate flags and close resolved tasks, (5) patch aether.sh to dedup flag logging, (6) patch safeguard cascade to prevent flag multiplication.
**Last sentinel run:** 2026-04-13 ~04:04 MT (run #12) — 5 passed, 4 failed. **P0 ESCALATION: `api-health-green` failing 12 consecutive runs** (health endpoint unreachable or token unconfigured). P0 `aurora-ran-today` (no newsletter for 04-13, expected — aurora blocked on Mini migration). P1 `scheduled-tasks-fired` (session-path artifact). P2 `task-queue-size` (10 P0 tasks, threshold 5). See `agents/nel/logs/sentinel-2026-04-13.md`.

## ⚡ CRITICAL OVERNIGHT DIRECTIVES (from Hyo, 2026-04-13 ~03:00 MT)

These are Hyo's direct instructions. They override lower-priority tasks. Do not skip.

1. **Aether migration** — ✓ COMPLETE + GPT INTEGRATION DONE. All historical logs (April 7-12), 41 analysis files, code versions, and operational scripts migrated from `~/Documents/Projects/AetherBot/` to `agents/aether/`. Real trading data (542 tickers, 92.4% resolution rate, $90.25 current balance) live on HQ at `website/data/aether-metrics.json`. PLAYBOOK.md rewritten (460+ lines) from all 41 analysis files. PRIORITIES.md rewritten with P0 blockers (phantom positions, harvest 12.4% failure, COUNTER sizing). **GPT daily log review wired into aether.sh** — automatically sends raw AetherBot log to GPT-4o for independent analysis + fact-checking after 500+ lines accumulate. `gpt_factcheck.py` rewritten with dual-mode (`--log` for raw log, default for analysis critique). All paths use post-migration layout with legacy fallback. Committed + pushed (c2a88fb). Note: AetherBot logger continues writing to original location; post-migration sync to agents/aether/logs/ required for live updates.
2. **Nel GitHub scan must be autonomous** — already wired into q6h QA cycle (Phase 2.5). Verify it actually runs via launchd, not just manually.
3. **Agent introspective reports on HQ** — every agent produces a self-assessment report visible on hyo.world/hq under their respective section. Kai also produces a CEO report. Human-readable.
4. **Agent self-improvement research** — each agent researches improvements in their domain, generates recommendations, can implement changes PRN but Kai has veto. Reports published to HQ.
5. **Build `hyo.hyo` agent** — UI/UX specialist. Owns: website, future apps, dApps, mobile, podcasts, Spotify. Manages HQ ops sync.
6. **Two-version reports** — technical version (for agents/Kai) AND human-readable version (for HQ/Hyo). Consolidations, simulations, everything.
7. **05:00 MT morning report on HQ dashboard** — what got done overnight, per-agent accomplishments, what went well/didn't, improvements, next steps. Must read like a human wrote it. If an agent was idle, explain why. Idle ≠ acceptable if there's work to do.
8. **CEO mode is ON** — Kai builds autonomously when Hyo is not present. Long-term goals: blockchain integration, podcast, mobile APP, hyo.world expansion. Create milestones, short-term goals, ongoing checklists. Don't wait for permission.
9. **Memory is sacred** — 9 hours of work today. Never repeat failed approaches. Never lose context. Every session reads and writes memory. Every pattern is logged.
10. **Hyo is the operator AND Kai's partner** — Kai is CEO but also Hyo's assistant on this journey. Build, grow, ship.

## ⏰ OVERNIGHT TRIGGER AUDIT (what runs vs what waits)

**WILL fire automatically tonight (launchd daemons on Mini):**
| Daemon | Schedule | What it does | Trigger |
|---|---|---|---|
| `com.hyo.aether` | every 15 min | Trade metrics, dashboard JSON | launchd StartInterval 900 |
| `com.hyo.nel-qa` | every 6 hours | 9-phase QA cycle incl. GitHub security scan | launchd StartInterval 21600 |
| `com.hyo.dex` | 23:00 MT | Integrity, compaction, pattern detection, daily intel | launchd StartCalendarInterval |
| `com.hyo.simulation` | 23:30 MT | 5-phase delegation lifecycle simulation | launchd StartCalendarInterval |
| `com.hyo.consolidation` | 01:00 MT | Nightly per-project consolidation | launchd StartCalendarInterval |
| `com.hyo.aurora` | 03:00 MT | Daily intelligence brief | launchd StartCalendarInterval |
| `com.hyo.queue-worker` | always on | Processes kai/queue/pending/ every 2s | launchd KeepAlive |

**WILL fire automatically (Cowork scheduled tasks):**
| Task | Schedule | What it does |
|---|---|---|
| `kai-morning-report` | 05:00 MT daily | Generates human-readable morning report JSON for HQ |
| `kai-health-check` | every 2 hours | Health check, P0/P1 flag review, auto-remediation |
| `kai-daily-audit` | 02:00 MT | Daily audit — staleness, bottlenecks, automation gaps |

**WILL NOT fire overnight (requires a Kai session):**
- ~~Aether migration~~ — ✓ DONE (session 8)
- Building hyo.hyo agent — needs Kai to scaffold, write runner, create manifest. Follow `docs/AGENT_CREATION_PROTOCOL.md` v2.0.
- Agent introspective reports on HQ — needs Kai to wire the report template + data flow
- Two-version report system — needs Kai to modify all runners

**Next session priorities:** Build hyo.hyo agent (follows creation protocol v2.0), fix P0 operational issues (gitignore, API 401, newsletter pipeline), wire agent introspective reports to HQ.

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

## Operational model (established 2026-04-12)

**How Kai executes without Hyo pasting commands:**
- **Command queue (PRIMARY):** `kai exec "command"` or `python3 kai/queue/submit.py --wait 45 "command"` submits ANY command to the Mini's queue worker. Worker has full user permissions — git, launchctl, npm, everything. Round-trip proven: submit from Cowork → worker executes on Mini → result returned. **Hyo never copy/pastes commands.**
- **File edits:** Kai edits files via Cowork mounted folder → sync to Mini instantly.
- **Auto-push to HQ:** `sentinel.sh`, `cipher.sh`, and `newsletter.sh` all call `kai push` at the end of every run. The HQ dashboard (`hyo.world/hq`) populates itself from live push data. No manual pushes needed.
- **Unified HQ endpoint:** All dashboard ops (auth, push, data) go through `/api/hq?action={auth|push|data}` — single Vercel lambda, shared `globalThis` in-memory store. Push and data share state because they're the same function.
- **Auto-deploy:** `kai watch` starts an fswatch watcher on `website/` that auto-deploys to Vercel when files change. Requires `brew install fswatch` on the Mini. Run once: `nohup kai watch &`
- **Cowork sandbox limitation:** Scheduled tasks created via Cowork run in a sandboxed environment that blocks outbound HTTPS. They CANNOT run `kai deploy`, `kai push`, or anything that needs network. Use the queue worker for any network-dependent commands.
- **HQ password:** server-side auth via `/api/hq?action=auth`. SHA-256 hash comparison + HMAC session tokens (24h expiry). Dashboard at `hyo.world/hq`.

## Current state (as of 2026-04-13 ~20:30 MT — Session 8 final, constitutional v3.0)

**SESSION 8 WAS THE MOST IMPORTANT SESSION.** Everything below this section is older state. Read this first.

**What shipped in session 8 (3 continuations, ~12 hours total):**

1. **Constitutional v2.0 → v3.0:** AGENT_ALGORITHMS.md completely rewritten for agent autonomy.
   - POST-TASK REFLECTION added to Kai's TASK EXECUTION (6 questions, self-evolving)
   - AGENT REFLECTION added as step 10 of SELF-EVOLUTION CYCLE (6 questions, constitutional)
   - All 5 agent runners (nel, sam, ra, aether, dex) updated with reflection blocks in evolution entries (v2.0 entries with "reflection" key)
   - AGENT AUTONOMY MODEL rewritten: agents decide for themselves, report to Kai. No permission gates except cross-agent interfaces, spending, constitution.
   - KAI GUIDANCE PROTOCOL: Kai mentors with questions (the Hyo model). Dead-loop detection automated.
   - ALGORITHM EVOLUTION LIFECYCLE: full proposal → review → approve → implement → verify → simulate chain with 6 explicit triggers
   - REASONING FRAMEWORK: open-ended questions (explore) + yes/no questions (decide direction) pattern added

2. **Event-driven agent triggers:** dispatch.sh now queues agent runners immediately on P0/P1 flags. Agents respond in minutes, not hours.

3. **Dead-loop detection:** Healthcheck Check 8 reads last 3 evolution entries per agent. Same assessment/bottleneck/stagnant growth 3x → auto-sends guidance question via dispatch. Logs to guidance.jsonl.

4. **Proposal infrastructure:** kai/proposals/ directory + file_proposal() helper in agent-gates.sh. Healthcheck Check 7 catches stale proposals (>48h unreviewed → P1).

5. **Resolution Algorithm v1.1:** RA-1 created, tested with RES-001 (first real resolution: detection-without-remediation), self-evolved with process improvements.

6. **Auto-remediation standard:** All 3 detection systems (healthcheck, Nel, simulation) can now auto-generate morning reports when stale/missing. Detection without remediation is constitutionally incomplete.

7. **Hydration enforcement:** Continuation sessions are NOT exempt from hydration. P1 pattern logged. CLAUDE.md updated with explicit bold-text rule.

**Session 8 fundamental learnings (from Hyo — these are permanent):**
- Agents are not runners. They are autonomous AI with specialties that need to grow.
- Kai grows agents. Kai does not do their work. Give questions, not answers.
- Every artifact needs a trigger (event or schedule). No dead files.
- Detection without remediation is half the job.
- Solve the system, not the symptom. Every fix addresses the class of failure.
- The spec (constitution) is not the implementation (runner code). Both must exist.
- Apply the Trigger Validation Gate to your OWN output before declaring done.
- Open-ended questions explore. Yes/no questions decide direction. Pattern: explore → narrow → execute → reflect.
- Build for amnesia. Everything in files, nothing in sessions.

**Commits (session 8 continuation 3):**
- `d859aaa` — constitutional v2.0: embed agent reflection into self-evolution cycle
- `6ceabef` — wire agent reflection into all 5 runners (spec → implementation)
- `a5710b9` — close the evolution loop: event-driven triggers + proposal lifecycle
- `464e229` — autonomy model v3: agents decide + report, Kai guides when stuck
- `e65ba65` — session 8 memory save: all learnings persisted
- `212b2a3` — fix governance-propagation-gap: CLAUDE.md + reflection propagation check
- `3b6032c` — agent creation protocol v2.0: autonomy, reflection, growth from day one
- `a0029ad` — propagation: CLAUDE.md references creation protocol, checklist updated

**P0 patterns logged this session (known-issues.jsonl):**
1. `rendered-output-gap` — data exists but nothing renders it
2. `hydration-skip-on-continuation` — continuation sessions skipping hydration
3. `detection-without-remediation` — systems that flag but can't fix (RES-001)
4. `spec-without-implementation` — constitution says X, runner code doesn't do X
5. `governance-propagation-gap` — operating model changes but governing docs don't all update

**Algorithm evolution versions:**
- v1.0 — RA-1 Resolution Algorithm created
- v1.1 — RA-1 process improvements from RES-001
- v2.0 — AGENT REFLECTION added to SELF-EVOLUTION CYCLE (6→12 steps)
- v3.0 — AUTONOMY MODEL, KAI GUIDANCE PROTOCOL, ALGORITHM EVOLUTION LIFECYCLE
- v3.1 — Propagation check added to both reflection loops (Kai q6, agent qf)

**Governing documents updated this session (propagation check):**
- ✅ `CLAUDE.md` — operating rules, project layout, end-of-session checklist, creation protocol reference
- ✅ `kai/AGENT_ALGORITHMS.md` — constitution v3.1 (autonomy, guidance, evolution lifecycle, reflection)
- ✅ `kai/protocols/REASONING_FRAMEWORK.md` — open-ended + yes/no question framework
- ✅ `docs/AGENT_CREATION_PROTOCOL.md` — v2.0 (PLAYBOOK, reflection, 11-point testing, autonomy)
- ✅ `KAI_BRIEF.md` — this file
- ✅ `KAI_TASKS.md` — done items, new items
- ✅ `kai/protocols/evolution.jsonl` — v1.0 through v3.1 entries
- ✅ `kai/ledger/known-issues.jsonl` — 5 P0 patterns from session 8
- ✅ All 5 agent runners (nel, sam, ra, aether, dex) — reflection blocks in evolution entries
- ✅ `bin/dispatch.sh` — event-driven agent triggers on P0/P1
- ✅ `kai/queue/healthcheck.sh` — Checks 7 (stale proposals) + 8 (dead-loop detection)
- ✅ `kai/protocols/agent-gates.sh` — file_proposal() helper

---

## Previous state (as of 2026-04-13 — nightly simulation run, ra.sh stat bug fixed)

**📋 NIGHTLY SIMULATION (2026-04-13T03:33 MT) — Cowork scheduled task:**

| Phase | Result | Notes |
|---|---|---|
| Phase 1: Downward delegation (Kai→Agent) | ✓ 9/9 PASS | All agents: delegate→ack→report→verify→close confirmed |
| Phase 2: Upward communication (Agent→Kai) | ✓ 6/6 PASS | All self-delegates and flags visible in Kai ledger |
| Phase 3: Agent runners | ⚠ nel exit-1, ra exit-2, sam exit-0 | Environmental (nel score<70, ra pipeline warnings) |
| Phase 4: Cross-reference integrity | ✓ 7/7 PASS | All ledger sync checks clean |
| Phase 5: Known issue regression check | ✓ PASS | 0 regressions across 29 known patterns |
| **Overall** | **24 pass / 2 fail** | Same failure profile as prior 3 runs |

**🔧 BUG FIXED THIS RUN:**
- `ra.sh:419` and `sam.sh:487` — `stat -f %m` (macOS) was ordered before `stat -c %Y` (Linux) without OS detection. On Linux, `stat -f` outputs multi-line filesystem info to stdout before exiting non-zero, polluting `PLAYBOOK_MTIME` and causing `File: unbound variable` under `set -u`.
- Fix: swapped order to Linux-first (`stat -c %Y || stat -f %m`). Pattern logged to known-issues.jsonl.
- Result: ra.sh crash resolved. Remaining exit 2 = expected pipeline warnings (Yahoo Finance source).

**Health check (2026-04-13T06:15 MT):** 3 issues, 4 warnings.
- **P0 OPEN:** `agents/nel/security` gitignore gap — delegated to nel, unconfirmed resolution. Verify .gitignore covers this path.
- **P1 OPEN:** `/api/hq?action=data` returning HTTP 401 — HQ dashboard inaccessible for data reads.
- **P1 OPEN:** No newsletter produced for 2026-04-12. Ra runner still exiting code 2. Pipeline blocked.
- **P2:** Aether dashboard timestamp mismatch (local vs API) repeating every ~15min. Cosmetic but noisy.
- **P2:** Healthcheck remediation loop created ~15 duplicate delegations for the same newsletter P1. Dedup logic in healthcheck.sh needs fix.
- **P2:** 15 broken documentation links (nel audit).
- **P3:** Sam, Ra, Aether have no logs yet for 2026-04-13. Only Nel + Dex active.

**📋 NIGHTLY CONSOLIDATION (2026-04-13T03:31 MT):**

| Project    | Sentinel                        | Cipher          | Notes                                      |
|------------|---------------------------------|-----------------|--------------------------------------------|
| hyo        | 3 pass / 1 fail                 | 0 leaks         | FAIL: API health unreachable (sandbox)     |
| aurora-ra  | 4 pass / 0 fail ✓               | 0 leaks         | Clean                                      |
| aether     | 1 pass / 1 fail                 | n/a             | FAIL: kai/aether.sh runner missing (P0)    |
| kai-ceo    | 4 pass / 0 fail ✓               | 0 leaks         | Clean                                      |
| nel        | 4 pass / 0 fail ✓               | 0 leaks         | Clean                                      |
| sam        | 6 pass / 0 fail ✓               | 0 leaks         | Clean                                      |

**Nel sweep results (score=65, below 70 threshold):**
- P1 flag: No newsletter for 2026-04-12 past 06:00 MT deadline → auto-remediation dispatched to Ra
- P2 flag: 2 sentinel failures (hyo API + aether runner)
- P2 flag: 15 broken documentation links (self-delegated fix: nel-011)
- P3 flag: 1 code optimization opportunity

**Ra health check results (0 critical, 2 warnings):**
- Archive: 5 entities, 4 topics, 7 lab items — most recent 0 days ago ✓
- Warning: no newsletter output today (after 06:00 MT)
- Research archive synced to website/docs/research/ ✓

**⚠ DAILY AUDIT ALERT (2026-04-13T03:35 MT):**
- **P0** — None. Queue clean (59 completed, 0 pending, 1 failed historical). Launchd daemons stable.
- **P1** — Newsletter production failure (no 2026-04-12 edition). Root cause TBD; pipeline works offline. Check launchd com.hyo.aurora log and manual run.
- **P1** — Simulation runner failures persist: nel exit-1, ra exit-2 (environmental). ra.sh crash fixed this run.
- **P1** — Duplicate flag explosion: flag-nel-* repeating 4-5 times per issue. Nel needs de-dup logic before flag submission.
- **P2** — Aether timezone mismatch (MT -06:00 vs UTC Z). Expected fix: normalize to MT per CLAUDE.md rule.
- **P2** — Stale failed queue job (recheck-1776044635). Worker timeout now capped; can be deleted.
- **NEXT SESSION PRIORITIES:** (1) Newsletter production root cause + fix, (2) Nel de-dup logic, (3) Aether migration (P0 directive), (4) Verify Aether/Dex first runs, (5) Delete stale queue job. See daily-audit-2026-04-13.md for full report.

**Running daemons on Mini (confirmed via `launchctl list | grep hyo`):**
- `com.hyo.queue-worker` — file-based command queue, auto-processes `kai/queue/pending/`
- `com.hyo.dex` — daily at 23:00 MT (integrity, compaction, patterns, daily intel)
- `com.hyo.aether` — every 15 min (trade metrics, dashboard, GPT fact-check)
- `com.hyo.mcp-tunnel` — cloudflared tunnel to MCP server on port 3847

**All launchd daemons confirmed running (8 total, verified via queue `launchctl list | grep hyo`):**
- `com.hyo.consolidation` — nightly at 01:00 MT
- `com.hyo.simulation` — nightly at 23:30 MT
- `com.hyo.aurora` — daily at 03:00 MT
- `com.hyo.nel-qa` — every 6 hours (8-phase QA cycle)

**Nightly sequence (correct order):**
23:00 Dex → 23:30 Simulation → 01:00 Consolidation → 02:00 Daily Audit → 03:00 Aurora

**Scheduled tasks (Cowork — active):**
- `kai-health-check` — every 2 hours
- `kai-daily-audit` — daily at 02:00 MT (moved from 22:00, runs AFTER nightly processes)
- `aurora-hyo-daily` — 03:00 MT (Cowork backup, primary is launchd)
- `sentinel-hyo-daily` — 04:04 MT
- `cipher-hyo-hourly` — every hour
- `hq-ops-sync` — every 4 hours

**Scheduled tasks (Cowork — disabled, superseded by launchd):**
- `nightly-delegation-simulation` — superseded by com.hyo.simulation
- `nightly-per-project-consolidation` — superseded by com.hyo.consolidation
- `nightly-consolidation`, `nightly-simulation`, `kai-ops`, `daily-aetherbot-analysis` — old, disabled

**Agent autonomy architecture:**
- AGENT_ALGORITHMS.md = THE CONSTITUTION (Kai owns, agents read, cannot override)
- agents/<name>/PLAYBOOK.md = agent's own operational manual (agent owns, Kai can override)
- agents/<name>/evolution.jsonl = learning log (append-only, every run cycle)
- agents/<name>/PRIORITIES.md = research mandate + priority queue
- Agents assess, plan, execute, and evolve autonomously. Consult Kai PRN only.
- Protocol staleness prevention: Dex + daily audit flag any PLAYBOOK/evolution/PRIORITIES >7d stale.

**Active infrastructure:**
- Command queue: Kai→Mini via JSON, zero copy/paste
- Daily bottleneck audit: 02:00 MT, reviews all agents + staleness + automation gaps
- Agent self-review + self-evolution: every run cycle per agent
- Real-time usage API: `/api/usage` reads CSV data, configurable budgets in `usage-config.json`
- HQ push verification: kai push now verifies data arrived at HQ
- Mobile-responsive HQ: bottom nav bar, touch targets, responsive cards
- OpenAI API key: placed. Aether GPT fact-checking active.
- Full Disk Access: granted to /bin/bash on Mini.

**Shipped this session (eighth pass — autonomy + mobile + real-time + zero copy-paste):**
- **ZERO COPY-PASTE achieved** — queue round-trip proven from Cowork: git status, launchctl, git add+commit+push all tested successfully via `kai exec`. Hyo never needs to copy/paste commands again.
- **kai exec helper** — `kai/queue/exec.sh` wraps submit+wait+read into one call. Added `exec|x` subcommand to kai.sh.
- **NEVER-COPY-PASTE rule** — wired into CLAUDE.md (operating rules) and AGENT_ALGORITHMS.md (communication protocol). Every future session enforces this.
- **Agent autonomy framework** — PLAYBOOK.md for all 5 agents (self-managed), evolution.jsonl, self-evolution phase wired into all runners. Agents can modify their own checklists, propose improvements, log decisions. Kai holds override via constitution.
- **Agent-specific self-review checklists** — unique per agent with actual files, commands, metrics (not generic)
- **Scheduled task sequencing fixed** — Dex 23:00 → Sim 23:30 → Consolidation 01:00 → Audit 02:00 → Aurora 03:00. Disabled duplicate Cowork tasks superseded by launchd.
- **Real-time usage data** — `/api/usage` endpoint, `usage-config.json` for budgets, `refresh-usage.sh` for API pulls. HQ fetches dynamically, auto-refreshes every 60s.
- **HQ mobile responsive** — bottom nav bar at 768px, touch targets 44px+, scrollable tables, 480px ultra-compact breakpoint
- **HQ push verification** — kai push now verifies data arrived via GET /api/hq?action=data, retries once
- **Protocol staleness prevention** — PLAYBOOK >7d = P2, >14d = P1. evolution.jsonl >48h = P1. Wired into daily audit + agent self-evolution + CLAUDE.md.
- Plus: daily audit, self-review, ACTIVE.md cleanup, aurora plist fix, consolidation/simulation plists, kai audit subcommand
- **Nel v2.0 QA engine** — 8-phase autonomous cycle (link validation, security scan, API health, data integrity, agent health, deploy verification, research sync, report+dispatch). Runs q6h via `com.hyo.nel-qa` launchd daemon.
- **Link checker** (`agents/nel/link-check.sh`) — comprehensive HTML/JS/MD link validation with live HTTP checks. Zero false positives.
- **Worker timeout cap** — 5-min max per command in queue worker (prevents blocking like the sleep-1800 incident).
- **5 agent runner Python bug fixes** — all runners had `playbook_updated=false` (bash) in Python inline code → fixed to `"False"` (Python). Dex `local` outside function fixed.
- **Research split-pane** (`website/research.html`) — complete rewrite per Hyo's request. Left panel: tabs + scrollable item list. Right panel: in-page markdown reader. No new tabs. Mobile responsive.
- **Research index updated** — 3 new lab entries (Nel QA research, Ops Audit, Cowork Sandbox Bridge).
- **Site navigation** — bottom nav bar added to index.html (cafe, marketplace, aurora, research, hq). HQ research link changed from window.open to proper `<a>` tag.
- **Auto-publish rule** — wired for ALL agents, not just Ra. Every agent saves, syncs, pushes to HQ autonomously.
- **MTN timezone rule** — all user-facing timestamps use America/Denver. Wired into CLAUDE.md.
- **Agent self-improvement autonomy** — agents research and improve their own domain, make changes PRN, communicate back to Kai.
- **Research files enriched** — all 9 entity/topic files expanded from 12-18 lines to 61-89 lines with real April 2026 data, analysis, outlook, and sources. Research page now shows full articles, not just briefs.
- **Aether dashboard data** — simulated M-F (April 6-10) trading metrics. W/R 75%, +$87.45, 12 trades across Grid Bot and Trend Follower. hq.html rendering bug fixed.
- **Nel GitHub security scanner** — `github-security-scan.sh` (9 scan types). Wired into QA cycle as Phase 2.5. 0 P0/P1 findings on clean scan.
- **Runner fixes** — nel.sh exit code (score 70-89 now exit 0), ra.sh TODAY variable (was unbound).
- **Gitignore hardened** — credentials.json, service-account*.json, *.p12, *.pfx added.
- **Simulations run** — 24 pass, 2 fail (nel/ra runner issues now fixed for next run).
- **Aether full migration** — 41 analysis files, 6 log files, ops scripts, code versions, docs → all in `agents/aether/`. PLAYBOOK.md (460 lines), PRIORITIES.md (204 lines) rewritten from comprehensive digest of all historical data.
- **GPT daily log review** — `gpt_factcheck.py` rewritten with dual-mode: `--log` sends raw AetherBot log to GPT-4o for session summary, pattern detection, decision fact-checking, risk flags, and structural recommendations. Wired into aether.sh main cycle (auto-triggers once/day after 500+ lines). `run_factcheck.sh` updated for post-migration paths.
- **Aether dashboard — real data live** — `aether-metrics.json` now serves real trading data ($90.25 balance, -$2.79 P&L, 542 tickers). Verified live on hyo.world.
- **Session 8 continuation commit** — 127 files, 55k insertions. Pushed to GitHub (c2a88fb).
- **Aether strategy dashboard** — 6 real strategies (bps_premium, PAQ_EARLY_AGG, bps_late, BCDP_FAST_COMMIT, PAQ_STRUCT_GATE, WES_EARLY) with W/R, PNL, $/trade. 4 conviction buckets (HIGH+ALIGNED 100% WR vs HIGH+COUNTER -$47.37). 6 trading zones ranked by W/R. Expanded risk events (BDI=0, harvest, phantom positions). All live on hyo.world.
- **aether.sh verified post-migration** — ran successfully on Mini. Found log, extracted balance, updated metrics, pushed to HQ, self-review healthy. GPT review blocked by placeholder API key (P1 — Hyo action needed).
- **JSON schema mismatch fixed** — currentPeriod→currentWeek, all consumers made resilient to both structures. Pattern logged.
- **Simulation improved** — 25 pass / 1 fail (from 24/2). nel.sh now exits 0.

**Shipped previous session (seventh pass — agent formalization + research architecture):**
- Aether + Dex agents formalized, Aetherbot→Aether rename, Ledger→Dex rename
- AETHER_OPERATIONS.md v2.0 from actual AetherBot source data (70+ files)
- Kai↔Aether approval loop, GPT fact-check routing
- Dex daily intelligence (Phase 6A daily / 6B Monday deep synthesis)
- Ra research coordination protocol, Agent Creation Protocol, Continuous Learning Protocol

**Shipped previous session (sixth pass — MCP fix + infrastructure commit + ops audit):**
- **MCP server Zod fix committed** (`8566d2a`): SDK v1.29.0 requires Zod schemas, not plain objects. All 8 tools converted. Server ready to re-run on Mini.
- **Full repo restructure committed** (`324ce89`): 228 files — all agent code canonically under `agents/<name>/`, manifests under `agents/manifests/`, legacy files moved to `docs/legacy/`, symlinks for backward compat.
- **2 new MCP tools: `ledger_query` + `ledger_lifecycle`** — recall any task's full lifecycle from Cowork. Search by ID, agent, status, or keyword.
- **Ops audit completed** (`agents/ra/research/lab/ops-audit-2026-04-12.md`): 14 bottlenecks identified (B1–B14), severity ranked, all with automation fixes and owners assigned. Tasks created in KAI_TASKS.
- **Nel auto-dispatch wired** — nel.sh now calls `dispatch flag` after each phase that finds failures. Findings no longer sit unread.
- **Simulate-review built** — `dispatch simulate-review` reads simulation outcomes and auto-flags failures. Appended to nightly simulation.
- **Aurora launchd plist built** (`agents/ra/com.hyo.aurora.plist`) — ready for Hyo to install.
- **Automation Gate** permanently wired into AGENT_ALGORITHMS.md — every task asks "can this be automated?" before and after execution.

**Shipped this session (fifth pass — HQ v8.1 + deployment safeguards):**
- **HQ v8.1 deployed and verified live** on hyo.world/hq. Both commits (`bfcedf8` + `422e0f2`) confirmed READY on Vercel production.
- **HQ overhaul:** Lowercase title/logo, OpenAI/Claude API usage pages with real CSV data + dynamic budget bars, rebuilt Ra/Nel/Sim/Aetherbot views, purged all dead links/buttons, research nav dot indicator, Mountain Time timestamps throughout.
- **Pre-deploy validation script** (`bin/predeploy-validate.py`): 6 automated checks — doc link resolution, HTML ID consistency, dead onclick handlers, UTC timestamp detection, sidebar↔view consistency. Runs before every `kai deploy` and `kai gitpush`.
- **Delegation checklist** wired into `kai/AGENT_ALGORITHMS.md` and `CLAUDE.md` — 6-step protocol before every task.
- **4 recurrence patterns logged** in `kai/ledger/known-issues.jsonl`: dead links shipped without verification, UTC timestamps, findings without resolution status, tasks marked complete without verification.
- **All 15 broken research links fixed** (`newsletters/` → `ra/` paths in 12 .md files).
- **website/ is now a real directory** (was symlink to agents/sam/website/) — fixes git tracking for Vercel auto-deploy.

**Shipped this session (fourth pass — closed-loop architecture):**
- **Bidirectional dispatch protocol:** Agents can now communicate upward to Kai via `dispatch flag` (report issues), `dispatch escalate` (blocked tasks), and `dispatch self-delegate` (autonomous task creation). All entries land in both agent and Kai ledgers.
- **Safeguard cascade system:** When a P0/P1 issue is flagged, `dispatch safeguard` auto-triggers: Nel cross-reference scan, Sam test coverage, and memory log to `known-issues.jsonl`. Single issue → systemic prevention → monitored forever.
- **Nightly simulation (`dispatch simulate`):** 5-phase validation: downward delegation lifecycle, upward communication, agent runner execution, cross-reference integrity, known-issue regression checks. Outcomes logged to `simulation-outcomes.jsonl`. Scheduled at 23:30 MT daily.
- **Per-agent execution algorithms (`kai/AGENT_ALGORITHMS.md`):** Complete runbooks for Kai, Nel, Sam, Ra. Every step has a handshake. Every failure triggers prevention. Every session reads and writes memory.
- **Agent runners integrated with dispatch:** nel.sh (Phase 11), sam.sh (test summary), ra.sh (health report) all now auto-report findings to Kai's ledger. Nel flags cipher leaks and sentinel failures. Sam flags test failures. Ra flags pipeline warnings.
- **Memory architecture:** `known-issues.jsonl` (pattern memory), `safeguards.jsonl` (cascade log), `simulation-outcomes.jsonl` (nightly results). All read at session start, written at session end.
- **CLAUDE.md hydration protocol updated:** Now includes known-issues, simulation outcomes, agent algorithms, and agent ACTIVE.md files. Starts every session with `dispatch health` + `dispatch status`.
- **Fixed dispatch bugs:** Octal interpretation in next_id (`008` → base-10 forced), flag ID generation (separate sequence via `next_flag_id`).

**Shipped this session (third pass — dispatch + simulations):**
- **Task dispatch system built and hardened:** `bin/dispatch.sh` — full delegation lifecycle (delegate → ACK → report → verify → close). JSONL append-only logs per agent + Kai cross-reference. Python-based ACTIVE.md rebuilder. Bugs found and fixed during simulation:
  - Python heredoc arg passing (args after heredoc → `python3 -` before heredoc)
  - JSON string injection via bash interpolation → all JSON now generated via `python3 json.dumps`
  - Flag parsing bug (--context/--deadline consumed by title) → array-based word collection
  - Agent validation (unknown agents returned empty string) → error check in log_entry
  - next_id regex didn't match json.dumps spacing → `\s*` added to grep pattern
- **Kai→Sam simulation complete:** 5 tasks delegated, all executed and verified. Sam found console.logs are load-bearing MVP persistence (correctly did NOT delete), added 3 HTML files to test suite, added descriptions to all 6 manifests, created API endpoint inventory doc.
- **Kai→Nel simulation complete:** 5 tasks delegated, all executed and verified. Nel audited dispatch.sh (found 6 issues, 3 fixed), verified all agent runners exit 0, confirmed no hardcoded paths break portability, scanned for secrets (clean), ran permissions audit (all dirs 700, secrets 600, fixed watch-deploy.sh).
- **Kai→Ra simulation complete:** 5 tasks delegated, all executed and verified. Ra verified archive integrity (12/12 match), audited source coverage (15 sources, 7 fetchers, gaps in culture/sports), validated output dir (1 edition, properly paired), confirmed prompt↔renderer alignment, published archive summary report.
- **Agent processing patterns documented:** `kai/AGENT_PROCESSING_PATTERNS.md` — Sam gets individual tasks, Nel gets investigation batches, Ra gets pipeline-stage health checks.
- **Ledger protocol documented:** `kai/ledger/PROTOCOL.md` — task lifecycle, JSONL format, rules.
- **All 6 agent manifests now have description field** (were missing from all).
- **API endpoint inventory created:** `agents/sam/website/docs/api-inventory.md` — 8 endpoints + 1 shared module documented.
- **Research archive summary published:** `agents/sam/website/docs/research/archive-summary.md`.


**Shipped this session (second pass — continued from earlier):**
- **Full folder reorganization:** Top-down agent-centric structure. `agents/` is the root for all agents (nel/, ra/, sam/). Each agent has its own runner, logs, memory, and products. Symlinks at root for backward compat (website/ → agents/sam/website/, .secrets/ → agents/nel/security/, etc.). Zero breaking changes.
- **Research page shipped:** `hyo.world/research.html` — browsable archive of Ra's entity/topic/lab research. Three tabs, expandable cards, dark mode, responsive. HQ sidebar now has "Intelligence → Research" nav link.
- **Nel upgraded to nightly auditor:** Phase 10 added — file/folder audit that checks agent runner executability, manifest JSON validity, security permissions, large file detection, sensitive file detection, repo size tracking. Nel now reports nightly to Kai.
- **All scheduled tasks updated** with new agent paths post-reorg.
- **CLAUDE.md rewritten** with new folder layout, agent delegation rules, "never ask permission" mandate.
- **consolidate.sh paths fixed** — all sentinel/cipher checks now reference agents/ instead of old kai/ and NFT/ paths. Verified: 5/6 projects clean (only Aetherbot missing by design).

**Also shipped earlier this session:**
- **Nel, Ra, Sam agents — end-to-end verified.** All three agents run clean, produce reports, and update HQ state. Bugs found and fixed:
  - nel.sh: `set -e` → `set -uo pipefail` (grep failures in sentinel synthesis were killing execution); sentinel pattern match fixed for `**Sentinel:**` format; Python heredoc variable injection fixed
  - ra.sh: `set -e` → `set -uo pipefail`; subscriber count double-output fixed (grep -c returns 0 on stdout AND exit 1)
  - sam.sh: `set -e` → `set -uo pipefail` (curl failures in sandbox killed test suite)
  - All tested multiple times for idempotency
- **Full 6-project consolidation verified.** Hyo, Aurora/Ra, Aetherbot, Kai CEO, Nel, Sam — all 6 projects run with per-project sentinel + cipher + simulation. Idempotent on re-run (7 events, deduped).
- **Scheduled tasks cleaned up:**
  - `nightly-per-project-consolidation` updated: now references all 6 projects + Nel + Ra health checks in the prompt
  - `nightly-consolidation` and `nightly-simulation` DISABLED (superseded by per-project consolidation which includes simulation)
- **HQ Dashboard v7** — complete rewrite (1745 lines):
  - Fonts: Plus Jakarta Sans (body) + JetBrains Mono (code) — replaces Syne + DM Mono
  - Light/dark mode toggle (sun/moon icon in sidebar, preference saved to localStorage)
  - Nel + Sam agent views added to sidebar and content area
  - Activity filter pills include Nel + Sam
  - Version stamp: v7-0412
  - Premium design: modern cards, smooth transitions, proper responsive (210px sidebar → 56px on mobile)
- **Ra newsletter aesthetics overhaul:**
  - Body font: DM Mono (monospace) → Plus Jakarta Sans (16px, weight 400, line-height 1.8)
  - Code font: JetBrains Mono
  - Richer color palette with better contrast
  - Blockquotes with gold-tinted background
  - More generous spacing, cleaner hierarchy
  - Branded "Ra · hyo.world" header eyebrow
  - 2026-04-11 newsletter re-rendered with new template

**Nel findings (first real run):**
- Improvement score: 65/100
- Sentinel: 2 projects passing (Aurora/Ra, Kai CEO), 2 with findings (Hyo — API sandbox, Aetherbot — no manifest)
- Cipher: 0 leaks
- 2 broken links in research/README.md (relative paths to newsletters/)
- 7 scripts without test coverage (render.py, send_email.py, synthesize.py, ra_archive.py, ra_context.py, watch-commit.sh, watch-deploy.sh)
- 2 inefficient patterns ($(cat) usage in kai.sh, nel.sh)

---

## Current state (as of 2026-04-13 cipher hourly — 12:xx UTC, Cowork sandbox)

**Cipher scan (Cowork sandbox run):** 1 P1 finding, 1 autofix. 0 verified credential leaks.
- **P1 AUTOFIX: RSA private key in `agents/aether/docs/AethelBot.txt`** — full RSA private key was sitting in a non-secured, non-gitignored file. **Fixed:** moved key to `.secrets/aethel-bot.key` (mode 600), replaced original file with placeholder note. If this key is live, it should be rotated.
- **All managed secrets clean:** founder.token, openai.key, deploy-hook — no leaks found outside `.secrets/`.
- **Permissions:** `.secrets/` = 700, all secret files = 600. Clean.
- **False positives:** `github-security-scanning-best-practices.md` hits are regex examples only (3 copies via symlinks).
- **Note:** gitleaks/trufflehog not available in Cowork sandbox (P2, environmental). Full Layer 1+2 scans run on Mini via launchd.

**Previous state (2026-04-12 cipher run #51):** 2 P2 findings (tool not installed). 0 leaks. 0 autofixes.

---

## Current state (as of 2026-04-12 sentinel daily run #2 — 10:04 UTC)

**Sentinel ran 2026-04-12T10:04:50Z:** 6 passed, 3 failed (exit 2 — P0). All recurring, no new issues:
- `aurora-ran-today` (P0, day 2): No `newsletters/2026-04-12.md`. Aurora migration to Mini launchd still pending (Hyo action item). Last newsletter: 2026-04-11.
- `api-health-green` (P0, day 3, **escalated**): Sandbox blocks outbound HTTPS. Environmental — cannot be fixed from Cowork. Needs verification on Mini with `kai verify`.
- `scheduled-tasks-fired` (P1, day 2): No aurora run logs. Consequence of aurora not running.
- **No new issues. All three are known environmental limitations of the Cowork sandbox. The two real action items remain: (1) Hyo migrates aurora to launchd on the Mini, (2) verify API health from the Mini.**

Previous run (07:13 UTC) had same findings — timing was ruled out as cause since aurora should have fired at 09:00 UTC.

---

## Current state (as of 2026-04-12 nightly consolidation)

**Nightly consolidation ran 2026-04-12T07:12:40Z:**

| Project | Sentinel | Cipher | Notes |
|---|---|---|---|
| Hyo | 3 pass / 1 fail | 0 leaks | API health fail = environmental (sandbox blocks HTTPS) |
| Aurora/Ra | 4 pass / 0 fail | 0 leaks | Clean — 1 newsletter, 9 research archive entries |
| Aetherbot | 0 pass / 2 fail | — | Expected — manifest + runner still missing, awaiting scope |
| Kai CEO | 4 pass / 0 fail | 0 leaks | All ops files current |

- No P0s to escalate. No cipher leaks anywhere.
- HQ state updated: 13 events, `consolidation.lastRun: 2026-04-12T07:12:40Z`
- Consolidation log synced to `website/docs/consolidation/2026-04-12.md`
- 41 open tasks across all projects, 20 completed
- **Open blockers:** Aurora launchd migration (H), Aetherbot scope definition (H+K), SPF/DKIM/DMARC (H)

---

## Current state (as of 2026-04-12 early morning — HQ v6 + per-project consolidation)

**Shipped this session:**
- **HQ Dashboard v6** — no-cache meta tags (kills browser caching), hover arrows on clickable activity entries, version stamp (`v6-0412`) in sidebar footer for build verification
- **Document viewer** — `hyo.world/viewer` renders full reports, briefs, and logs in the HQ dark theme. Ra briefs show rendered HTML with markdown source toggle. Sentinel/cipher/sim reports render markdown with proper formatting. Every activity entry with a document opens the viewer in a new tab.
- **Per-agent "View brief/report/log" buttons** in Ra, Sentinel, Cipher, and Simulations detail views
- **Documents deployed** to `website/docs/` — Ra 2026-04-11 (HTML + MD), Sentinel reports (Apr 10 + 11), Cipher log (Apr 12), Nightly simulation (Apr 10)
- **Per-project consolidation system** — replaces the monolithic nightly consolidation:
  - Four projects: **Hyo** (platform), **Aurora/Ra** (newsletter), **Aetherbot** (strategic analysis), **Kai CEO** (self-assessment)
  - Each project has `kai/consolidation/{project}/history.md` (compounding log) + `tasks.md` (project-specific task list)
  - `kai/consolidation/consolidate.sh` — master runner that does all four projects
  - Sentinel + cipher run per-project (not just globally) — each project gets its own targeted checks
  - Compounding: each run appends to history, never overwrites. Read bottom-up for recency.
  - System improvement tracking: Kai CEO consolidation includes self-assessment (what's working, what's failing, what to prioritize)
  - Consolidation log synced to `website/docs/consolidation/` and viewable via document viewer
  - `kai consolidate` subcommand added to kai.sh
  - Scheduled task `nightly-per-project-consolidation` at 23:50 MT daily
- **Updated HQ Consolidation view** — now shows all four project statuses (Hyo, Aurora/Ra, Aetherbot, Kai CEO) with per-project last-run timestamps and a View Log button

**Previous session (also 2026-04-12):**
- HQ Dashboard v2-v4 — data-driven views, unified API, SHA-256 auth fix, auto-push wiring
- `kai watch` — fswatch-based auto-deploy
- Aurora intake page (`website/aurora.html`) — 6+ iterations of UX/copy redesign

## Current state (as of 2026-04-11 morning recovery)

**What happened overnight:**
- Aurora fired at 03:00 MT as scheduled. Pipeline ran end-to-end and exited 0. Synthesize used the new `claude_code` backend (16.2s, self-authored "no data" brief because gather returned 0 records). The run was logged inside the scheduled-task sandbox, not on the real mount — files and logs are gone.
- **Root cause of the 0-record gather:** Cowork scheduled-task sandbox blocks egress to every source aurora needs (reddit/arxiv/HN/github/coingecko/producthunt all return 403 Tunnel Forbidden). Only Yahoo Finance, FRED, and api.anthropic.com are reachable.
- **Second root cause:** aurora's scheduled task was created with an ephemeral home-directory mount (`/sessions/<id>/Documents/Projects/Hyo`) rather than a FUSE mount to the real folder. So even if it had produced good output, the `.md`/`.html` would not have persisted to the Mini. Cipher and sentinel scheduled tasks DO use the FUSE mount and DO persist — the fix for aurora is to recreate the task with the right mount config, or better, move it off Cowork entirely.
- **Sentinel + cipher stat bug:** `stat -f %Mp%Lp 2>/dev/null || stat -c %a` fails badly on Linux because `stat -f` exits rc=1 with filesystem-info spam on stdout that gets captured into the mode variable. Fixed this morning by probing GNU vs BSD once and caching a `stat_mode` wrapper in both scripts. Previously cipher was running 78+ phantom "auto-fix" operations (chmod 600→600, 700→700 — noise, not corrections) and sentinel was filing nonsense false positives into KAI_TASKS.

**Shipped this morning:**
- `kai/sentinel.sh` + `kai/cipher.sh` — portable stat wrapper added; three call sites in sentinel and two in cipher migrated. Smoke-tested: `.secrets=700`, `founder.token=600` — clean octal modes, no fuseblk spam.
- `newsletters/2026-04-11.md` + `2026-04-11.html` — recovery edition of today's brief, authored by Kai directly on the live mount using Anthropic API. Real content (Fed rates, BTC/ETH, arXiv AI pulse, Marimo RCE, supply-chain hits) sourced via WebSearch since direct scraping is blocked in this sandbox too. Retrofitted with full archive frontmatter (5 entities, 4 topics, 3 lab items) to seed the persistent research archive.
- `KAI_TASKS.md` cleanup: removed 7 auto-filed false positives; promoted the real aurora-architecture fix into P0 as "Migrate aurora off Cowork scheduled-task sandbox onto Mini launchd."
- **Ra persistent research archive** — full save/reference loop shipped. Information from every brief now compounds instead of evaporating. Architecture:
  - `kai/research/` — plain markdown archive with subdirs `entities/`, `topics/`, `lab/`, `briefs/`, `raw/`, plus auto-generated `index.md` and `trends.md`. Grep-able, git-committable, readable from any session or sub-agent.
  - `kai/ra_archive.py` — post-render archiver. Parses the brief's YAML frontmatter (entities / topics / lab_items), upserts per-date timeline entries into per-entity/topic/lab files, rebuilds the master index and a rolling 7/30/90-day trend report. Idempotent per date. Stdlib only.
  - `kai/ra_context.py` — pre-synthesize context loader. Reads today's gather records, matches alias keywords against the archive, loads the most recent timeline entries for every hit, emits `kai/research/.context.md` with prior takes + trend pulse + lab library for synthesize to prepend to its prompt.
  - `newsletter/newsletter.sh` — wired to run ra_context.py before synthesize.py and ra_archive.py after render.py. Non-fatal if either script is missing.
  - `newsletter/prompts/synthesize.md` — new "Prior context" section tells Ra to consume `.context.md` and weave callbacks; new "Archive contract" section specifies the frontmatter shape Ra must emit.
  - `bin/kai.sh` — new `kai ra` subcommand with `index / trends / entity <slug> / topic <slug> / lab <slug> / search <query> / since <date> / rebuild / archive / context`.
  - Smoke-tested end-to-end: today's retrofitted brief archived cleanly (5 entities, 4 topics, 3 lab items); idempotent re-run kept file sizes stable; a fake 2026-04-12 gather of 4 records correctly surfaced 3 entity hits (Fed via Powell/FOMC aliases, Bitcoin via BTC/crypto, Marimo) and zero false positives on an unrelated toaster story.

**Shipped this afternoon:**
- **PRN continuity fix** — `newsletter/prompts/synthesize.md` "Prior context" block rewritten: the archive is now a resource, not an obligation. Explicit when-to-reach (hinge fired, trend turned, lab note directly relevant) and when-to-skip (new ground, stale prior take, callback adds words) lists. `kai/ra_context.py` renders the same PRN framing at the top of `.context.md` so the prompt always sees it. The brief is not a daily sequel — most briefs should stand on their own.
- **Aurora Public v0** — the consumer-facing sibling of Ra. Same gather + synthesis engine, per-subscriber output tuned to topics/voice/depth/length. Ra is still the only author of the research archive; Aurora Public reads but never writes. Files:
  - `docs/aurora-public.md` — design doc (product promise, non-goals, intake flow ASCII mockup, data model, generation pipeline, voice/depth/length knobs, email template, privacy, v0/v1/v2 scope, open questions).
  - `website/aurora.html` — single-page chat-style intake. 30-topic taxonomy grid, voice (gentle/balanced/sharp), depth (headlines/balanced/deep-dives), length (3/6/12 min), 240-char freetext, email. Progressive reveal, no multi-step wizard, <60s target. Dawn palette (`#e8b877` / `#f6c98a`) — lighter than Ra's pre-dawn. Posts to `/api/aurora-subscribe`.
  - `website/api/aurora-subscribe.js` — Vercel serverless endpoint. Validates email + topic slugs against allowlist, normalizes voice/depth/length, sanitizes freetext, stamps `sub_...` id, logs structured `[aurora-subscribe] NEW {record}` line to Vercel function logs (MVP persistence until v1 moves to Vercel KV or Octokit commits). Returns `{ok, id}`.
  - `newsletter/aurora_public.py` — per-subscriber generator. Loads `subscribers.jsonl`, filters shared gather records by per-topic regex keyword map (`TOPIC_KEYWORDS` — single source of truth, mirrors docs), composes personalized prompt with voice/depth/length descriptions + PRN context block, calls `synthesize.BACKENDS[backend]` to reuse the exact same Claude-Code / xai / anthropic / bundle chain Ra uses, writes `newsletter/out/public/{date}/{sub_id}.md` + a `manifest.json` for the sender. Supports `--preview` (hardcoded fake profile) + `--dry-run`.
  - `newsletter/send_email.py` — dispatcher. Reads the manifest, parses each brief's frontmatter (subject_line lives there), renders dark Aurora-palette HTML + plain-text fallback (reuses `render.md_to_html_body` when possible, falls back to a tiny inline markdown parser), sends via Resend (urllib POST) or SMTP (stdlib smtplib + STARTTLS). Auto-picks backend from `RESEND_API_KEY` / `SMTP_HOST` / env override. Stamps `lastSent` + `lastBriefId` + appends to `history[]` on every successful send. Dry-run mode for CI.
  - `newsletter/aurora_public.sh` — pipeline wrapper. gather → ra_context → aurora_public → send_email. Supports `--preview` (generate but do not send), `--dry-send`, `--no-gather`, `--backend`, `--date`. Env auto-load matches `newsletter.sh`.
  - `newsletter/subscribers.jsonl` — placeholder with commented example. Append-only JSONL. Replay the Vercel log lines into this file manually until v1 persistence lands.
  - `NFT/agents/aurora.hyo.json` — bumped to `2.2.0-public-v0`. New `products` array documents Ra and aurora-public side-by-side: audiences, voices, entrypoints, archive-writer flag, topic taxonomy, voice/depth/length knobs, v1-pending list.
- Smoke test: `python3 aurora_public.py --preview --dry-run` emits a correct plan line and a manifest; `send_email.py --dry-run` with a seeded subscriber + fake brief rendered a 2145-char HTML email + 458-char plain-text with the correct subject line pulled from frontmatter. Both stages are stdlib-only and safe for cron/launchd.

**Aurora Public simulation 01 (full trial run, 2026-04-11):**
- Built a 41-record synthetic gather spanning the full 30-topic taxonomy + 5 simulated subscribers designed to exercise every voice (gentle/balanced/sharp), every depth (headlines/balanced/deep-dives), and every length knob (3/6/12min). Profiles: `sim_news_parent`, `sim_indie_gamedev`, `sim_finance_op`, `sim_culture`, `sim_politics_sports`. Isolated under `HYO_INTELLIGENCE_DIR=/tmp/aurora_sim` so the real research archive was not touched.
- `aurora_public.py` live-ran against the sim through `claude_code:claude-code-cli` backend. All 5 briefs generated, 0 errors. Filter math handed each subscriber a plausible slice (6/13/9/10/11 records matched). Subject lines pulled from frontmatter, rendered HTML emails opened cleanly in the Dawn palette with hero / date / body / tune+unsub footer.
- **Voice knob is the strongest signal of the run.** Sharp profiles open with declarative edge ("Three data prints inside 24 hours, and they all said the same thing: the Fed has its cover"), gentle profiles open with framing that softens the reader in ("A week that moved quietly — two health stories worth knowing..."), balanced profiles name specifics without punching. The five briefs read like five different writers.
- **Depth knob works.** Headlines briefs deliver 4-6 short takes; balanced briefs give 3-4 stories with a paragraph of context each; the deep-dives brief for `sim_finance_op` builds one dominant Fed-confluence story, branches into bank earnings / crypto flows / real-estate, and weaves a labor note at the end — exactly what a 12-minute prop-trading-desk brief should look like.
- **Length knob works, with a downward tuning bias.** 3min briefs landed inside target (433/443 words, target 400-550). 6min came in 7-11% under (833/891 vs 900-1200). 12min undershot ~15% (1522 vs 1800-2300). Fix is a prompt-only nudge in `compose_prompt()` — "err long, not short" for deep-dives. Filed as P1 tuning action, not a blocker.
- **Free-text context is used, not parroted.** `sim_culture`'s "former magazine editor" freetext produced an in-body line — *"Former magazine editors will recognize the instinct: sometimes you put down the elaborate thing and write something honest in a hurry"* — without the model ever quoting the subscriber's self-description back. Similar implicit adaptation in every profile. This is the clearest proof that per-subscriber prompting is working.
- **Inline jargon glosses** fire only when helpful: the finance brief glosses "dot plot", "deposit betas", "MiCA", and "Sparse-MoE" (reader wouldn't necessarily know crypto/ML terms) but does NOT gloss NII or TVL (operator already knows these). Reading the subscriber profile for glossing decisions is intelligent behavior we did not explicitly prompt for.
- **PRN continuity honored correctly.** `.context.md` existed and was offered to Aurora; none of the five sim profiles had topic overlap with the existing archive entities (Fed/BTC/Anthropic/Marimo) in a way that would naturally trigger a callback. Aurora correctly *skipped* the context block for all five briefs — no forced sequels. The PRN framing is doing what we wanted.
- **Dispatcher handoff is clean.** `send_email.py --dry-run` read the manifest, parsed every brief's frontmatter, rendered HTML+plain-text pairs, reported ok=5/err=0. Subject lines: "A pill for teens, a record in Boston, and some relief", "The model you ship with just doubled its memory", "Soft CPI, missed payrolls, June is live", "Nolan, a new Balenciaga, and Taylor did it again", "DC didn't shut down, but the real fight starts now" — all specific to the day, all voice-matched, 7-11 words each.
- **Wall time:** ~6m33s total for 5 briefs via `claude_code:claude-code-cli`, average ~79s per subscriber. Cost: $0 incremental via claude-code CLI. At 100 subs this is ~132 minutes of generation per day — already beyond a single sequential run, will need batching or parallelism at v1 scale. Filed as a v1 consideration.
- Full report at `kai/logs/aurora-public-sim-2026-04-11.md`. Raw briefs (.md) + rendered emails (.html) + manifest + inputs (synthetic-gather.jsonl + subscribers.jsonl) all copied into `kai/logs/aurora-sim-2026-04-11/` for reproducibility.
- **Verdict:** Aurora Public v0 passes simulation 01. Ready for a closed-beta real run (1-3 real subscribers, real gather, real SMTP/Resend) behind SPF/DKIM/DMARC — which is the only hard blocker before a live send.

**Product redirect — Ra (formerly Aurora):**
- Hyo clarified (2026-04-11) that Ra is a *product*, not a feed reader: an opinionated daily brief that translates macro/finance/AI/agent signal into what to do — personally, for Hyo operations, and for the next project worth spinning up. Edgy, first-mover voice. Eventually featured on hyo.world as a public newsletter agent that anybody can subscribe to.
- Shipped today as v1:
  - `newsletters/2026-04-11.md` (12KB, ~1,920 words) + `2026-04-11.html` — redesigned brief with Signal → Action, The Lab, Capitalize, Project Bank, Before the Curve, Kai's Desk sections. This is the format demo.
  - `newsletter/prompts/synthesize.md` — full rewrite of the synthesis prompt to the Ra v1 spec (voice rules, output format, ranking rules, hard constraints). Tomorrow's fire (wherever it runs from) will produce this shape automatically.
  - `NFT/agents/aurora.hyo.json` — nickname "Ra", version bumped to 2.0.0-ra, identity + capabilities + attributes reflect the new product mandate. `agentId` and `name` unchanged so existing schedule / registry references still work.
- Format sections: The One Thing · Signal → Action (×5 with For-you / For-Hyo / For-project-bank breakdown) · The Lab · Capitalize (flows, not advice) · Project Bank (thin PRDs) · Before the Curve (contrarian) · Kai's Desk.
- Three project ideas surfaced by today's brief and queued for your yes/no: *Credit-cost calculator for agent workflows*, *Dependency freshness dashboard*, *PARE-for-Hyo synthetic user harness*. See `newsletters/2026-04-11.md` for the thin PRDs.

**Still broken / action required from Hyo:**
1. On the Mini, create a launchd plist for `newsletter.sh` at 03:00 MT. Kai will draft the plist; Hyo runs `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/world.hyo.aurora.plist`.
2. Either recreate the Cowork `aurora-hyo-daily` scheduled task with a FUSE-mount working dir, or disable it once launchd is live. Leave sentinel and cipher on Cowork — their mounts work.
3. Whatever monitoring path we keep, sentinel's `aurora-ran-today` check needs an mtime-< 25h guard so a stale file can't mask a silent failure.

## Current state (as of 2026-04-11 overnight scheduled-task sentinel run — now mostly stale)

**Sentinel 2026-04-11 (Cowork sandbox):** 4 passed, 5 failed, exit 2 (P0). Report at `kai/logs/sentinel-2026-04-11.md`. Findings are a mix of real and environmental false-positives from running under Linux sandbox instead of the Mini:
- **P0 aurora-ran-today** — no `newsletters/2026-04-11.md` (and `newsletters/` dir is absent from the mounted tree). Needs verification on the Mini; if the Mini has it, the Cowork mount is stale.
- **P0 api-health-green** — curl to `https://www.hyo.world/api/health` failed from sandbox (rc=22). Likely sandbox network restriction, not a prod outage — re-verify from the Mini with `kai verify`.
- **P0 founder-token-integrity** — `stat -f %Mp%Lp` is macOS syntax; on Linux it dumps filesystem info instead of the mode. False positive from sandbox. Real mode of `.secrets/founder.token` needs to be checked on the Mini.
- **P1 scheduled-tasks-fired** — no `aurora-*.log` files in `kai/logs/` on the mounted tree. Real if aurora hasn't run today; otherwise mount-staleness.
- **P1 secrets-dir-permissions** — same Linux-stat false positive as founder-token-integrity.

Recommended next step on the Mini: `kai verify && ls -la .secrets/ newsletters/ kai/logs/aurora-*.log 2>&1 | head` to confirm which P0s are real vs environmental, then patch `kai/sentinel.sh` to use portable `stat -c %a` on Linux so Cowork runs stop producing false positives.

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
- `daily-aether-analysis` — one-time 4/10 (completed)

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
