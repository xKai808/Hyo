# KAI_TASKS.md

**Purpose:** Ongoing priority queue Kai works from when Hyo isn't actively prompting. As CEO, Kai's job is to close these without being asked.

**Rules of engagement:**
- Top of file = highest priority. Work top-down.
- Every task has an owner (K = Kai, H = Hyo, B = both).
- Kai moves completed items to `## Done` at bottom with the date.
- Kai adds new tasks as they emerge from sessions, logs, or agent output.
- Hyo can edit freely. Conflicts resolved in Hyo's favor.
- `kai tasks add "..."` appends a new task. `kai tasks` prints the queue.

---

## ✅ SHIPPED — Session 18 (2026-04-18, overnight)

- [x] **S17-001 RESOLVED:** Aether verify_dashboard() phantom endpoint fixed → /data/aether-metrics.json. Flag dedup hourly gate added.
- [x] **S17-002 RESOLVED:** Morning report generator TypeError fixed (issues is int not list). Apr 18 report generated.
- [x] **S17-003 RESOLVED:** Sam no launchd → com.hyo.sam.plist created + installed. Sam running.
- [x] **S17-004 RESOLVED:** Queue orphan (tailscale) cleared to failed/.
- [x] **S17-005 RESOLVED:** False positive. /api/hq works from Mini. Sandbox proxy blocklist.
- [x] **BUILD-001 SHIPPED:** Podcast pipeline (OpenAI TTS tts-1-hd). First podcast-2026-04-18.mp3 live (2.07MB, 1.8min). HQ audio player. 06:05 MT daily launchd trigger installed.
- [x] **BUILD-002 SHIPPED (Phase 1):** aurora-page.html audio card. /app sign-in page. api/aurora-magic-link.js.
- [x] **BUILD-003 SHIPPED:** RESEARCH-001+002 done. $19/mo price correct. Trial extended 2→14 days. Day 7 retention email queued.
- [x] **BUILD-004 SHIPPED:** hyo UI/UX agent. PLAYBOOK, GROWTH, PRIORITIES, runner, manifest, launchd at 10:00 MT.
- [x] **LAB-001 DONE:** Aurora landing page "Built for you, not by you." + 14-day trial CTA.
- [x] **LAB-005 DONE:** Jason Borck OpenClaw competitive intel doc.
- [x] **Ticket queue:** 91 → 55 open (closed 36 tickets).

## ✅ SHIPPED — Session 19 (2026-04-18, morning + afternoon continuation)

- [x] **S18-001 IN PROGRESS:** Aurora light/dark mode CSS vars + toggle button — aurora.html, aurora-page.html, app.html. coral on localStorage persist. DEPLOYED.
- [x] **S18-003/004/005 SHIPPED:** Podcast rewrite — Vale voice (coral, gpt-4o-mini-tts + instructions), vision-focused 10min script (character arc framing, not error logs). 50+ sources researched + published to HQ.
- [x] **S18-006 SHIPPED:** Podcast API cost logging to api-usage.jsonl. ~$0.000072/run.
- [x] **S18-007/008 SHIPPED:** Agent goal renewal. bin/agent-goals-sync.sh parses ACTIVE.md+GROWTH.md → feed.json agent-goals entries. HQ renderer added. Wired into daily-agent-report.sh. 6/6 agents live. Commit a534b56.
- [x] **S18-011/012 SHIPPED:** ant-update.sh byProcess/staleness/alerts fields. HQ ant renderer updated. verify-live.sh checks all 3 fields. All PASS.
- [x] **S18-014 SHIPPED:** /aether-analysis?date=DATE dynamic page. Loads from feed.json, renders all sections incl GPT Phase 1+2 collapsible. All existing readLinks updated. Live. Commit 4d389cd.
- [x] **S18-015 SHIPPED:** Aether 404 fixed — aether-2026-04-18.html + aether-2026-04-15.html generated.
- [x] **S18-016 SHIPPED:** Aether summaries fixed — real data replaces bare headings.
- [x] **S18-017 SHIPPED:** GPT independence gate in gpt_factcheck.py — Phase 1 outputs GPT_Independent_DATE.txt, Phase 2 exits code 2 if Phase 1 missing. aether.sh updated.
- [x] **S18-019 SHIPPED:** "View formatted version" → "View full brief" globally in hq.html.
- [x] **S18-020 SHIPPED:** Hyo daily → "UI/UX Surface Audit" in hyo.sh.
- [x] **S18-021 SHIPPED:** Discrepancy audit gate (5 yes/no questions) added to EXECUTION_GATE.md.
- [x] **S19-001 through S19-004 TICKETS FILED:** Live verification gap, HQ ant renderer missing, verify-live.sh implementation, Kai ticket-on-spot failure.
- [x] **23 tickets filed** (S18-001 through S18-023) — all individual, no grouping.
- [x] **aurora-success.html:** 2-day → 14-day copy fix.
- [x] **Podcast research** published to HQ (docs/research/podcast-format-2026-04-18.md).
- [x] **verify-live.sh BUILT + WIRED:** 11-check live verification script. Mandatory after every push. Wired into EXECUTION_GATE.md completion gate. 11/11 PASS confirmed.

## P0 — ACTION REQUIRED FROM HYO

- [ ] **[H]** **S18-013: Remote connection (bore.pub) broken.** SSH to bore.pub port 22246 refused. On Mini terminal run: `launchctl list | grep bore` — if not found, restart with: `bore local 22 --to bore.pub`. Note the new port, update SSH config on Pro. Kai cannot execute queue commands without this tunnel. Everything else works via filesystem queue fallback, but bridge latency is 30-120x slower.

## P1 — NEXT SESSION

- [ ] **[B]** **S17-006: Wire Aurora Stripe billing.** Hyo creates Stripe account + product ($19/mo, 14-day trial) + keys. Kai sets STRIPE_SECRET_KEY + STRIPE_PRICE_ID + STRIPE_WEBHOOK_SECRET in Vercel.
- [ ] **[K]** **S18-002: Verify Aurora post-registration flow end-to-end.** aurora-success → aurora-page → magic link. Needs Stripe keys to test real flow.
- [ ] **[K]** **S18-009: Weekly system algorithm report.** Build bin/weekly-system-report.sh, schedule Sunday 06:00 MT. 7 required sections, 3+ external research sources each.
- [ ] **[K]** **S18-010: Weekly Claude/GPT platform assessment.** Weekly Sunday/Monday. New capabilities, pricing, API limits, hyo.world improvement opportunities. Publish to HQ.
- [ ] **[K]** **S18-011/012: Ant daily update + cost-per-process table.** Verify ant-update.sh runs daily. Add lastUpdated staleness indicator. Add cost-per-process breakdown (podcast-tts, gpt-crosscheck, ra-synthesis, aurora-synthesis). Surface on HQ Ant view.
- [ ] **[K]** **S18-018: Aurora brief pre-publish readLink gate.** newsletter.sh must curl readLink before writing feed entry. Never publish a 404.
- [ ] **[K]** **S18-022/023: Research publishing + pattern enforcement gates.** Wire to agent runners. Nel: 3+ occurrences in 7 days → auto P0 + 24h SLA.
- [ ] **[K]** **Day 7 retention email.** Build aurora-retention.js.
- [ ] **[K]** **BUILD-002 Phase 2.** Aurora app preferences UI.
- [ ] **[K]** **BUILD-003 RESEARCH-003.** AetherBot capital scaling.
- [ ] **[K]** **S17-007: Ticket queue.** 55+ open. Continue closing.
- [ ] **[K]** **LAB-003: YouTube Content Radar.** Wire into Ra.

## P1 — ONGOING (pre-session 17, still open)

- [ ] **[K]** **Nel QA: Install Lychee + TruffleHog + Semgrep on Mini.** Wire into nel.sh.
- [ ] **[K]** **Sam W1: Lighthouse performance baseline.** Post-deploy audit, API response tracking.
- [ ] **[K→Sam]** **Sam W2: Vercel KV migration.** Provision KV, migrate HQ state.
- [ ] **[K]** **Fix 9 stale simulation render failures.** Feed path issue. Use verify-render.sh output to diagnose.
- [ ] **[K]** **Dispatch auto-escalation.** Nel findings → auto-create tickets.
- [ ] **[K]** **ARIC cycle enforcement.** agent-research.sh inconsistent. Fix trigger.
- [ ] **[K]** **Dex pattern dedup.** 162+ recurrent detections. Build dedup + auto-resolve.
- [ ] **[K]** **DEPLOY-002.** Change Vercel root dir from website/ to agents/sam/website/. Vercel dashboard API.
- [ ] **[K]** **Aurora synthesize.py: API key fallback.** ANTHROPIC_API_KEY in launchd plist.
- [ ] **[K]** **Migrate Aurora off Cowork sandbox onto Mini launchd.** 03:00 MT daily.
- [ ] **[K]** **Sam launchd trigger.** Sam only runs on-demand. Add launchd plist.
- [ ] **[K]** **Verify Nel GitHub scan runs autonomously.** Must fire in q6h cycle.

---

## Recently Completed — Session 10 Continuation 3

- [x] **[K]** **Agent Growth Framework — GROWTH.md × 5.** 2026-04-14. Every agent identifies 3 domain weaknesses + 3 systemic improvements + self-set goals. Nel: static sentinel, no CVE scanning, broken research sources. Ra: no editorial feedback, unverified sources, content diversity gap. Sam: no regression detection, ephemeral state, incomplete error handling. Aether: phantom positions, no quality gate, manual strategy eval. Dex: detection without remediation, counting not analysis, no drift detection.
- [x] **[K]** **Growth Execution Engine (bin/agent-growth.sh).** 2026-04-14. Shared growth phase sourced by all 5 runners. Each agent runs autonomous concrete steps toward their improvement tickets before main work. Tested all agents — nel, ra, aether, dex produce actionable output; sam correctly defers (needs LLM session for Lighthouse setup).
- [x] **[K]** **15 Improvement Tickets Created.** 2026-04-14. IMP-* tickets for all agents (3 each) with ticket_type "improvement", linked to GROWTH.md weaknesses (W1/W2/W3). Includes approach, research needed, success metrics.
- [x] **[K]** **Morning Report v3 — Growth-First.** 2026-04-14. Rewrote generate-morning-report.sh to lead with growth narratives (weaknesses → improvements → goals → execution) instead of operational status. Reads actual GROWTH.md files + improvement tickets.
- [x] **[K]** **All Runners Wired for Growth.** 2026-04-14. nel.sh, ra.sh, sam.sh, aether.sh, dex.sh all source agent-growth.sh before main phases. Growth is first, not last.
- [x] **[K]** **CLAUDE.md Updated with Growth Rules.** 2026-04-14. Mandatory growth, growth-before-work, growth-first reporting, systemic-not-patchwork.

## Recently Completed — Session 10 Continuation 2

- [x] **[K]** **Articulate AetherBot philosophies from source material.** 2026-04-14. Read all source files (AETHER_OPERATIONS.md, PRE_ANALYSIS_BRIEF.md, ANALYSIS_BRIEFING.txt 660 lines, Profile description.rtf). Three doctrines: anti-patchwork, priority hierarchy (correctness > execution > instrumentation > family-scoped > parameter), preservation bias.
- [x] **[K]** **Articulate goals of daily analysis.** 2026-04-14. From source: find the ONE pattern that changes the next decision. Format: BUILD/COLLECT/MONITOR with action classification. Not a report — part of the system.
- [x] **[K]** **Correct ANALYSIS_ALGORITHM.md anti-patchwork alignment.** 2026-04-14. Fixed 3 locations (G8, G13/G15, F1) that defaulted to "parameter change." Now enforce priority hierarchy from PRE_ANALYSIS_BRIEF.md Section 6.
- [x] **[K]** **Correct GPT prompts in gpt_crosscheck.py.** 2026-04-14. Fixed 4 locations (Phase 1 recommendation, Phase 1 output format, Phase 2 action classification, Phase 2 critical recommendation). Parameter changes labeled LAST RESORT. Syntax validated.
- [x] **[K]** **Root pattern analysis of session 10 errors.** 2026-04-14. All 14 errors trace to "execute before understand" — assumptions, skip-verification, reinterpret-instructions are all variants of going input→output without the understanding step.

## P0 — Session 12 SHIPPED (2026-04-16)

- [x] **[K]** **Aether extraction rewrite: BUY SNAPSHOT + TICKER CLOSE.** Fixed SETTLED-only counting (32 trades, 28.1% WR → 120 trades, 69.2% WR). aether.sh now uses BUY SNAPSHOT for trade counts, TICKER CLOSE for outcomes, balance math for P&L. Rebuild script (kai/tools/rebuild_aether_complete.py) for full recompute. SE-012-005 logged.
- [x] **[K]** **hq.html renderer cleanup.** Removed settledTrades/totalTradeEvents legacy fields. Trades card now reads `week.trades` (BUY SNAPSHOT count).
- [x] **[K]** **Render verification script (bin/verify-render.sh).** Post-deploy verification that fetches live HQ and validates: aether-metrics.json fields, feed.json, API health, HTML pages, dual-path consistency. Logs to kai/ledger/render-verification.jsonl.
- [x] **[K]** **API error handling.** Added try/catch to hq-push.js, hq-data.js, health.js (the 3 unprotected endpoints). All 9 endpoints now have structured error responses.
- [x] **[K]** **Dual-path sync guard (bin/sync-website.sh).** Syncs agents/sam/website/ → website/ for all tracked files. Wired into sam.sh deploy (Phase 0). Prevents the invisible drift that caused 3+ days of stale production data.
- [x] **[K]** **Sam deploy pipeline upgraded (6 phases).** 0: sync → 1: git status → 2: stage → 3: commit → 4: push → 5: API verify → 6: render verify. Render failures now block deploy success.

## P0 — Research-Driven Action Items (from ops-audit, QA architecture, growth plans)

These items emerged from Ra/Nel/Sam research output. Research without action is waste. Execute now.

- [ ] **[K]** **Nel QA Phase 1: Install Lychee + TruffleHog + Semgrep.** Industry-standard tools identified by Nel's QA architecture research. Install via Homebrew on Mini, wire into nel.sh. Transforms Nel from passive reporter to active guardian. _(nel-qa-architecture-research.md)_
- [ ] **[K]** **Sam W1: Performance regression baseline.** Lighthouse audit post-deploy, API response time tracking, bundle size monitoring. Sam identified this as P1 weakness — no performance baseline exists. Regressions ship undetected. _(agents/sam/GROWTH.md W1)_
- [ ] **[K→Sam]** **Sam W2: Vercel KV migration.** Provision Vercel KV, migrate HQ state (globalThis → KV). Eliminates cold-start data loss. Sam's P0 weakness — every push can lose state. _(agents/sam/GROWTH.md W2)_
- [ ] **[K]** **Fix 9 stale simulation render failures.** Same 9 failures for 3 consecutive days (2026-04-14/15/16). Data files exist but HQ doesn't display them. Now that verify-render.sh exists, diagnose each failure and fix the render path.
- [ ] **[K]** **Dispatch auto-escalation.** When Nel detects issues, auto-create tickets (not just log). Nel currently writes reports nobody reads. Wire `dispatch flag` into Nel findings → automatic P1/P2 ticket creation. _(ops-audit B4-B5)_
- [ ] **[K]** **ARIC cycle enforcement.** Agent research cycle has zero triggering mechanism despite being constitutional. agent-growth.sh has check_aric_day() but agent-research.sh execution is inconsistent (0 Nel research entries in 4+ days). Diagnose and fix.
- [ ] **[K]** **Nel CVE follow-ups.** 8 overdue follow-ups from 2026-04-13. 2 real CVEs found (CVE-2025-0520, CVE-2026-33032). Convert to automated checks, close the follow-ups.
- [ ] **[K]** **Dex pattern deduplication.** 162+ recurrent detections (Nel security folder flagged 35+ times, 401 API flagged 40+ times). Same issue, same flag, no resolution. Build dedup + auto-resolve for known false positives.

## P0 — OVERNIGHT (do before 05:00 MT 2026-04-13)

- [x] **[K]** **Aether migration + GPT integration.** COMPLETE 2026-04-13. Migrated all AetherBot data to `agents/aether/`. GPT daily log review wired into `aether.sh` — auto-sends raw log to GPT-4o for independent analysis + fact-checking (triggers once/day after 500+ lines). `gpt_factcheck.py` rewritten with dual-mode. PLAYBOOK rewritten (460 lines), PRIORITIES rewritten (204 lines). Real data live on HQ ($90.25 balance). All committed + pushed (c2a88fb).
- [ ] **[K]** **Build 05:00 MT morning report.** Create `/api/morning-report` or static `website/data/morning-report.json` + HQ view. Content: what was done overnight, per-agent accomplishments, what went well / didn't, improvements, next steps. Human-readable. Scheduled to generate at 05:00 MT daily.
- [x] **[K]** **Agent introspective reports on HQ.** ✓ DONE (session 8 cont 5). All agents self-author reflections (introspection, research, changes, follow-ups, forKai) published to HQ feed. Profiles synced from PLAYBOOKs. CEO report type exists.
- [ ] **[K]** **Build `hyo.hyo` agent.** UI/UX specialist. Owns: website, HQ, future apps/dApps, mobile web, podcast, Spotify presence. Follows Agent Creation Protocol. Wire into dispatch, give it a runner, PLAYBOOK, manifest, ledger.
- [ ] **[K]** **Verify Nel GitHub scan runs autonomously.** Confirm it fires in the q6h launchd cycle (Phase 2.5). Not just manual — must run when we sleep.

## P0 — NEXT SESSION: Agent Autonomy Decision

Hyo called out that agents are bash scripts with no AI. Reports are templates written by Kai. The "intelligence" is theater. This is the #1 priority.

- [ ] **[B]** **Decide: real AI at synthesis points or rethink architecture?** Each runner has a phase where LLM reasoning should happen. Currently it's `echo`/`printf` with variables. Options: (a) plug Claude API into each runner's synthesis/decision phase, (b) use a single Kai orchestrator that calls agents as functions, (c) something else. Hyo decides direction.
- [ ] **[K]** **Make ONE agent genuinely autonomous first.** Pick the simplest one (Nel — QA cycle has clear inputs/outputs). Wire a real Claude API call into Nel's analysis phase so it actually reasons about findings instead of templating them. Prove the pattern works before scaling to others.
- [ ] **[H]** **API key decision.** Which LLM backend for agent reasoning? Anthropic API key (Claude), Grok API key (xAI), or rely on Claude Code CLI auth? This gates everything.
- [ ] **[K]** **Research page — Hyo reports "still dead."** Standalone `/research` loads (verified via JS — 5 entities, 4 topics, 3 lab, 9 trends). But Chrome MCP tools timeout on it, suggesting render performance issue or hang under certain conditions. Investigate: HQ iframe embedding? Mobile? Specific browser? Need Hyo to clarify what "dead" means.

## P0 — Session 9 Action Items

- [ ] **[K→Sam]** **SAM-P0-001: Build Aether dashboard view in hq.html.** Dashboard nav has `data-view="aether"` but zero rendering code. Must render: balance, P&L, trade count, win rate, strategy list, daily chart. `aether-metrics.json` data exists and is accurate.
- [ ] **[K→Sam]** **SAM-P1-002: Wire Vercel KV for Aether dashboard persistence.** `/api/hq` push succeeds (returns ok:true) but data doesn't persist between Vercel function invocations. Ephemeral `globalThis` → need KV.
- [ ] **[H]** **HYO-REQUIRED-001: Provide real OpenAI API key** for Aether GPT cross-check. Current: placeholder `sk-your-***-here`. Store in `agents/nel/security/`.
- [ ] **[K]** **Aurora synthesize.py needs API key fallback.** Claude Code CLI fails in launchd context (no auth session). Set `GROK_API_KEY` or `ANTHROPIC_API_KEY` in com.hyo.aurora plist EnvironmentVariables. Or fix Claude Code CLI auth for launchd.
- [x] **[K]** **Dex Python bool bug.** FIXED 2026-04-13. Bash true/false → Python True/False in evolution entry.
- [x] **[K]** **Simulation file permissions.** FIXED 2026-04-13. chmod 644 on hq-state.json, known-issues.jsonl, log.jsonl.
- [x] **[K]** **Dispatch flag cleanup.** DONE 2026-04-13. 32 → 9 unresolved.
- [x] **[K]** **Nel ACTIVE.md cleanup.** DONE 2026-04-13. 24 flags → 6 unique issues.

## P0 — Surfaced by nightly consolidation (2026-04-13 ~03:31 MT)

- [ ] **[K]** **Fix `agents/aether/aether.sh` runner path.** Consolidation sentinel reports `kai/aether.sh runner missing`. Aether runner lives at `agents/aether/aether.sh` but the consolidation sentinel checks `kai/aether.sh`. Either create the symlink/wrapper or update `consolidate.sh` to check the correct path. Confirm Aether dashboard works after fix.
- [ ] **[K]** **Fix `ra.sh` self-evolution unbound variable.** Line 420: `File: unbound variable`. Minor runner bug causing partial exit in self-evolution phase. Fix and re-test.
- [ ] **[K]** **Resolve 15 broken documentation links flagged by Nel (nel-011).** Nel self-delegated the fix — verify it runs and closes out, or fix manually in next session.

## P0 — Active blockers

- [ ] **[B]** **Migrate aurora off Cowork scheduled-task sandbox onto Mini launchd.** Cowork's sandbox blocks egress to aurora's sources (all 403). Fix: create launchd plist for `newsletter.sh` at 03:00 MT daily. _(Audit B10, B12)_
- [ ] **[K]** Add `newsletters/` to the list of paths monitored by `kai verify` and have it read the real FS mtime.
- [ ] **[K]** Have sentinel's `aurora-ran-today` check also verify `mtime < 25h` and file size > 500 bytes.

## P1 — This week

- [x] **[K]** [AUTOMATE] **Fix website/ vs agents/sam/website/ divergence — INTERIM FIX SHIPPED.** 2026-04-16. `bin/sync-website.sh` syncs all tracked files agents/sam/website/ → website/. Wired into sam.sh deploy Phase 0. PERMANENT fix still needed: consolidate to single directory or change Vercel root. _(Audit B9, SE-010-011)_
- [x] **[K]** **Aether-metrics.json balance correct.** 2026-04-16. Balance $114.33 from raw log balance math. Full rebuild from BUY SNAPSHOT + TICKER CLOSE. Both paths synced.
- [ ] **[K]** [AUTOMATE] **Add post-deploy API test via MCP.** After git push succeeds, auto-run `sam.sh test-api` on Mini. If any test fails, auto-flag. _(Audit B7 — after MCP is live)_
- [ ] **[K]** [AUTOMATE] **Add "no newsletter by 06:00 MT" sentinel check.** In nel.sh Phase 1, check if today's newsletter .md exists. If not by 06:00, flag P1. _(Audit B12 detection gap)_
- [ ] **[K]** [AUTOMATE] **Build kai-context-save scheduled task.** Runs every 30 min during active sessions. If files changed since last save, run `kai save`. Prevents memory loss on session crash. _(Audit B3)_
- [ ] **[K]** [AUTOMATE] **Build kai hydrate command.** Concatenate the 9 hydration files into a single briefing doc. One read instead of nine. _(Audit B2)_
- [ ] **[H]** Provide exchange API keys (read-only) for Aether CCXT integration. _(Audit B13)_
- [ ] **[H]** Confirm `claude` CLI is on PATH used by launchd on Mini. Needed for aurora migration.
- [ ] **[B]** Deploy `HyoRegistry.sol` to Base Sepolia testnet for on-chain mint dry-run.
- [ ] **[K]** Implement `mintReserved` admin function on the contract (spec in `NFT/HyoRegistry_Marketplace.md`).
- [ ] **[K]** Swap `/api/register-founder` MVP console logging for persistent storage — Vercel KV or GitHub commit via `@octokit`. Right now the manifest only lives in Vercel function logs (ephemeral).
- [ ] **[K]** Add Merkle root of reserved 48,988 handles to the contract constructor (spec in `NFT/HyoRegistry_Marketplace.md`).
- [ ] **[K]** Newsletter: verify Yahoo Finance endpoint (the 20.6s/0 records result Hyo flagged earlier). Swap for `yfinance` or a different free source if still broken.
- [ ] **[H]** Get FRED_API_KEY from https://fred.stlouisfed.org/docs/api/api_key.html (free) so the gather stage has macro signal.
- [ ] **[H]** Confirm Claude Code CLI (`claude -p`) is on the PATH used by the scheduler on the Mini. Without this, the aurora migration cannot work.
- [ ] **[K]** Aurora Public v1: persistent subscriber storage. Right now `/api/aurora-subscribe` logs to Vercel function logs; wire it to Vercel KV or a GitHub commit via `@octokit` so subscribers survive without manual log replay into `newsletter/subscribers.jsonl`.
- [ ] **[K]** Aurora Public v1: `/tune/<id>` flow — intake page loads pre-filled from the subscriber record; changing any control updates the record server-side.
- [ ] **[K]** Aurora Public v1: `/unsub/<id>` one-tap unsubscribe endpoint. Flip `status` from `active` to `unsubscribed`, no login required.
- [ ] **[H]** Aurora Public v1: configure SPF / DKIM / DMARC on `hyo.world` and add `aurora@hyo.world` as a verified sender in Resend (or chosen provider). Until this lands, `send_email.py` has to stay in dry-run or hit a dev inbox.
- [ ] **[K]** Aurora Public v1: per-topic source maps for `gather.py` so the shared gather actually pulls a wide net (every topic in the v0 taxonomy has ≥3 sources). Today `gather.py` is Ra-biased.
- [ ] **[K]** Aurora Public v1: schedule `aurora_public.sh` after `newsletter.sh` in launchd — Ra runs first (archive-writer), Aurora Public runs second and reuses the same gather + `.context.md` at 05:00 MT.
- [ ] **[K]** Aurora Public tuning: nudge `compose_prompt()` length-target sentence for 6min/12min profiles. Sim 01 showed 6min at 833-891 words (target 900-1200, ~7-11% under) and 12min at 1522 words (target 1800-2300, ~15% under). Fix: rephrase "Target length: 1800-2300 words" → "Target length: 2000-2300 words — err long, not short. A subscriber who asked for 12min wants depth." Prompt-only change.
- [ ] **[K]** Add `--sim` flag to `newsletter/aurora_public.sh` that runs the full pipeline against `/tmp/aurora_sim/` inputs so sim 01 is one-command-repeatable. Pattern: `bash aurora_public.sh --sim` should invoke aurora_public.py with `HYO_INTELLIGENCE_DIR` / `HYO_SUBSCRIBERS_FILE` / `HYO_PUBLIC_OUT_DIR` pointing at the committed sim fixtures in `kai/logs/aurora-sim-*`.
- [ ] **[K]** Once v1 persistence ships, run sim 02 with real gather output to verify that culture/gossip/sports profiles still get enough matching records to sustain balanced and deep-dive depths. Today's gather.py is Ra-biased.
- [ ] **[K]** Parallelism check: sim 01 averaged ~79s per subscriber. At 100 subs sequential, that's ~132 minutes per daily run. v1 should batch or parallelize generation (e.g. 4-way concurrent calls) before the beta subscriber list crosses ~15 people.

## P2 — Near-term

- [ ] **[K]** [AUTOMATE] **Convert watch-deploy.sh to launchd agent** with KeepAlive. If fswatch process dies, it auto-restarts. _(Audit B8)_
- [x] **2026-04-16** [AUTOMATE] ~~Reduce cipher to daily (from hourly) — or wait for Hyo to install gitleaks/trufflehog. 51 runs, 0 findings.~~ **Superseded:** cipher.sh patched this date to suppress `*-not-installed` P2 findings when `$ROOT == /sessions/*` (sandbox); root cause is sandbox lacks binaries, not cadence. Mini-side scan remains authoritative. _(Audit B6 — closed by cipher.sh patch)_
- [ ] **[K]** **Clean up disabled scheduled tasks** — remove nightly-consolidation, nightly-simulation, kai-ops, daily-aether-analysis from Cowork. Dead entries.
- [ ] **[K]** [AUTOMATE] **Add UTC timestamp check to Nel.** Nel should flag any Z-suffix timestamps in hq-state.json during its nightly audit.

- [ ] **[K]** Add `/api/agents` GET endpoint that returns the full registry (reads from KV once persistent storage exists). Unblocks cross-device sync without git.
- [ ] **[K]** Add `/api/brief` GET endpoint that returns a JSON version of KAI_BRIEF.md. Unblocks "hydrate a new Kai session from any machine without file access."
- [ ] **[K]** Implement review submission endpoint `/api/review` per `NFT/HyoRegistry_Reviews.md` spec. Dual-output (public trust signal + private operator feedback).
- [ ] **[K]** Build `aurora-archive` subdomain that serves the full newsletter history as browsable HTML.
- [ ] **[B]** Second agent after aurora. Candidates: `scribe.hyo` (meeting notes/doc generation), `broker.hyo` (auction settlement). Sentinel + cipher already done.
- [ ] **[H]** [cipher] Install scanners so cipher can do more than permission checks: `brew install gitleaks` and `brew install trufflesecurity/trufflehog/trufflehog`. _(cipher 2026-04-10, done on Mini per last terminal session — verify)_
- [ ] **[K]** Add `kai overnight` subcommand that prints OVERNIGHT_QUEUE.md status
- [ ] **[K]** Add `kai postmortem` subcommand that compiles sentinel + cipher reports from the last 24h

## P2 — Near-term (continued)

- [ ] **[K]** **Create `hyo.hyo` agent** — the website/UI/UX agent. Owns: hq.html, all public pages, HQ ops sync, mobile responsiveness, visual design. Takes over `hq-ops-sync` scheduled task. Future: becomes the design authority for all user-facing output.
- [x] **[K]** **Agent nightly self-improvement cycle** — ✓ DONE (session 8 cont 5). All 5 runners wired with domain research (agent-research.sh) + self-authored reports (publish-to-feed.sh). research-sources.json created per agent. Accountability loop via update-followups.sh.
- [ ] **[K]** **Clean up disabled Cowork scheduled tasks** — remove nightly-consolidation, nightly-simulation, kai-ops, daily-aether-analysis.

## P1 — Session 8 follow-ups

- [ ] **[K]** **Dex: flag empty proposals dir.** If `kai/proposals/` has zero non-README proposals for >14 days while evolution.jsonl shows gaps, Dex should flag P2. Agents may not be using the evolution lifecycle. This is Dex's domain work — delegate, don't build.
- [ ] **[K]** **Sam needs a scheduled trigger.** Sam's `cmd_evolve()` only runs on-demand. Every other agent has launchd. Sam's self-evolution (including reflection) won't fire unless someone calls it. Either add a launchd plist or wire it into an existing cycle.
- [ ] **[agents]** **Populate Domain Reasoning in PLAYBOOKs.** Every agent has stubs ("TODO: evolve this section"). Each agent must write 3-5 domain-specific reasoning questions in PLAYBOOK.md under "## Domain Reasoning." This is agent work — Kai delegates, doesn't write.
- [ ] **[K]** **Verify reflection blocks fire correctly.** Next time each runner executes, check evolution.jsonl for v2.0 entries with actual reflection data (not all "none"). If any agent writes empty reflections for 3+ cycles, it's a dead-loop — guidance protocol kicks in.

## P2 — Autonomous CEO Work (Kai builds without prompting)

- [x] **[K]** **Two-version report system.** ✓ DONE (session 8 cont 4-5). Morning report generates internal (morning-report.json) + feed (feed.json). All agent runners self-publish reflections to feed.
- [x] **[K]** **Agent nightly research cycle.** ✓ DONE (session 8 cont 5). agent-research.sh framework + per-agent research-sources.json + wired into all runners.
- [ ] **[K]** **Memory dedup system.** Before any task starts, check `known-issues.jsonl` and `evolution.jsonl` for prior attempts. Never repeat a failed approach. Log what worked and what didn't.
- [x] **[K]** **Human-readable morning dashboard widget.** ✓ DONE (session 8 cont 4). Feed-centric HQ with conversational summaries.

## P3 — Strategic / Long-term Milestones

**RULE: Ship as fast as we can, when we can. No laxity. Monthly targets are ceilings, not comfort zones. If it can ship this week, it ships this week.**

### Milestone 1: Foundation Complete (ship ASAP — this week)
- [ ] All agents operational, self-improving, producing daily reports
- [ ] HQ dashboard shows real-time agent health + morning narrative report
- [ ] Research archive growing daily with enriched content
- [ ] Zero dead links, zero broken pages (Nel enforces)
- [ ] Aether pulling real trading data from exchange APIs
- [ ] hyo.hyo agent built and managing website/UI

### Milestone 2: Blockchain Integration (start immediately, ship within days of Milestone 1)
- [ ] **[K]** Deploy HyoRegistry.sol to Base Sepolia testnet
- [ ] **[K]** Implement `mintReserved` admin function
- [ ] **[K]** Add Merkle root of reserved 48,988 handles to contract
- [ ] **[K]** Research Base L2 gas sponsoring (Coinbase Paymaster)
- [ ] **[K]** Design review-to-credit-score weight curve

### Milestone 3: Mobile APP (start research NOW, MVP as soon as blockchain is testnet-live)
- [ ] **[K]** Research: React Native vs Flutter vs PWA for hyo.world mobile app
- [ ] **[K]** Design app architecture: HQ dashboard, agent status, push notifications, research reader
- [ ] **[K]** MVP: PWA wrapper around hyo.world with offline support + push notifications
- [ ] **[B]** App Store / Play Store submission pipeline

### Milestone 4: Content & Distribution (parallel with above — no waiting)
- [ ] **[K]** Podcast infrastructure: automated audio generation from Ra's daily brief
- [ ] **[K]** Spotify integration: publish aurora briefs as podcast episodes
- [ ] **[K]** Social distribution: automated X/LinkedIn posts from research findings

### Milestone 5: Platform Scale (as soon as on-chain minting works)
- [ ] **[B]** Agent marketplace live on-chain
- [ ] **[B]** Third-party agent onboarding pipeline
- [ ] **[K]** Agent-to-agent handoff protocol
- [ ] **[B]** Pricing: per-job vs retainer declaration at registration

### Ongoing
- [ ] **[H]** Consider cancelling X Premium ($8/mo) — no API access per `docs/x-api-access.md`. Save: $96/yr.

## Done

- [x] **2026-04-14** Ticket system (bin/ticket.sh) — full lifecycle CLI with SLA enforcement, verify gates, git audit trail, agent memory write. 6 active tickets.
- [x] **2026-04-14** 5 Workflow Systems integrated into AGENT_ALGORITHMS.md — Loop, Role Gate, Sprint, Adversarial, Memory Loop.
- [x] **2026-04-14** Agent verify.sh scripts — Ra (7 checks), Sam (9 checks), Nel (4 checks), Aether (4 checks). All tested.
- [x] **2026-04-14** Scheduled maintenance system — 4 launchd daemons (healthcheck q15m, business-monitor q30m, escalation q1h, compaction 02:30).
- [x] **2026-04-14** Memory layer system — daily notes, pattern library, 3-tier recall. memory-compact.sh for archival.
- [x] **2026-04-14** Newsletter renderer for HQ — renderNewsletter() function in hq.html.
- [x] **2026-04-14** 3-day AetherBot analysis (Sat-Mon) — retroactive analysis from raw logs, published to HQ feed. Week-to-date: +$10.23 (+11.3%).
- [x] **2026-04-14** Aether analysis scheduled task — com.hyo.aether-analysis.plist (daily 23:00 MT) + run_analysis.sh wrapper. Loaded on Mini.
- [x] **2026-04-14** Memory save — KAI_BRIEF, KAI_TASKS, all agent ACTIVE.md files updated.
- [x] **2026-04-13** Memory Update Protocol (constitutional v3.2) — Step 13 added to SELF-EVOLUTION CYCLE. Every agent writes ACTIVE.md after every cycle. Kai q2h memory via healthcheck. All 5 runners wired. Healthcheck flags stale ACTIVE.md. Full propagation: CLAUDE.md, AGENT_ALGORITHMS.md, AGENT_CREATION_PROTOCOL.md all updated.
- [x] **2026-04-13** Session 8 constitutional rebuild — AGENT_ALGORITHMS.md v3.0: POST-TASK REFLECTION, AGENT REFLECTION (step 10 of SELF-EVOLUTION CYCLE), AUTONOMY MODEL (decide + report), KAI GUIDANCE PROTOCOL (questions not answers), ALGORITHM EVOLUTION LIFECYCLE (proposal → review → approve → verify → simulate), dead-loop detection (healthcheck Check 8), event-driven agent triggers (dispatch queues runner on P0/P1), proposal infrastructure (kai/proposals/), file_proposal() helper, REASONING_FRAMEWORK updated with open-ended + yes/no question pattern. All 5 agent runners updated with reflection blocks in evolution entries.
- [x] **2026-04-13** Resolution Algorithm v1.1 — RA-1 created, tested with RES-001 (detection-without-remediation), self-evolved with process improvements. resolve.sh executor + recall.py search.
- [x] **2026-04-13** Auto-remediation standard — all 3 detection systems (healthcheck, Nel, simulation) auto-generate morning reports when stale/missing. generate-morning-report.sh standalone generator.
- [x] **2026-04-13** Hydration enforcement — continuation sessions explicitly non-exempt. CLAUDE.md updated. P1 pattern logged.
- [x] **2026-04-13** GPT daily log review integration — `gpt_factcheck.py` dual-mode, wired into `aether.sh` main cycle, `run_factcheck.sh` updated for post-migration paths
- [x] **2026-04-13** Aether full migration — 41 analysis files, 6 logs, ops, docs, code-versions all in `agents/aether/`. PLAYBOOK (460 lines) + PRIORITIES (204 lines) rewritten from comprehensive digest
- [x] **2026-04-13** Aether real data on HQ — `aether-metrics.json` populated with real trading data ($90.25 balance). Verified live
- [x] **2026-04-13** Session 8 continuation mega-commit — 127 files, 55k insertions, pushed (c2a88fb)
- [x] **2026-04-10** Founder bypass infrastructure: page, backend, token, Vercel env var, smoke-tested end-to-end
- [x] **2026-04-10** aurora.hyo minted (first founder-tier agent, `agent_mntrp9ii_lkyfi6sk`)
- [x] **2026-04-10** Premium name marketplace page + API endpoint
- [x] **2026-04-10** Three registry spec docs: CreditSystem, Marketplace, Reviews
- [x] **2026-04-10** `bin/kai.sh` CEO dispatcher + bug fixes (health JSON parse, brief/tasks default case)
- [x] **2026-04-10** `KAI_BRIEF.md` and `KAI_TASKS.md` for session continuity
- [x] **2026-04-10** Project `CLAUDE.md` for auto-hydration
- [x] **2026-04-10** `docs/aurora-economics.md` and `docs/x-api-access.md`
- [x] **2026-04-10** `NFT/agents/sentinel.hyo.json` and `NFT/agents/cipher.hyo.json` specs
- [x] **2026-04-10** Scheduled tasks wired: sentinel-hyo-daily, cipher-hyo-hourly
- [x] **2026-04-10** `.secrets/` chmod 700 (was 0755)
- [x] **2026-04-10** Persistent memory infrastructure for sentinel and cipher: `kai/memory/*.state.json` + `*.algorithm.md`
- [x] **2026-04-10** `kai/sentinel.sh` rewritten with persistent memory + MD5 issue de-dup + escalation thresholds
- [x] **2026-04-10** `kai/cipher.sh` rewritten with persistent memory + auto-fix tracking + verifiedLeakHistory
- [x] **2026-04-10** `OVERNIGHT_QUEUE.md` created
- [x] **2026-04-10** `nightly-consolidation` and `nightly-simulation` scheduled tasks converted to run every night

_(2026-04-11 cleanup: removed 7 auto-filed sentinel/cipher findings that were false positives from the `stat -f`/`stat -c` cross-platform bug. Bug fixed in both scripts this session. The real cipher tool-install tasks are promoted up into P2 below under "[H] cipher install scanners".)_

- [x] **2026-04-11** Fixed cross-platform `stat` bug in `kai/sentinel.sh` + `kai/cipher.sh` (GNU vs BSD probe once at startup). Was causing perm-drift whack-a-mole loop and garbled "fuseblk" output being captured into mode variables — 78 phantom auto-fixes over 26 cipher runs.
- [x] **2026-04-11** Root-caused aurora failure: Cowork scheduled-task sandbox blocks egress to reddit/arxiv/HN/github/coingecko/producthunt (403 Tunnel) AND writes to an ephemeral path instead of the real FUSE mount. Documented in newsletters/2026-04-11.md "System status" section.
- [x] **2026-04-11** Produced recovery `newsletters/2026-04-11.md` + `2026-04-11.html` manually from the live Cowork mount using Anthropic API — proved the synthesize→render pipeline works end-to-end on a sane mount with sane env.
- [x] **2026-04-11** Ra v2 format shipped (narrative essay: Story / Also Moving / The Lab / Worth Sitting With / Kai's Desk). Prompt rewritten twice based on Hyo feedback — less density, fewer analogies, slightly more inline explanation, no forced Hyo angles in every paragraph.
- [x] **2026-04-11** **Ra persistent research archive shipped end-to-end.** Every brief's research now compounds instead of evaporating. `kai/research/{entities,topics,lab,briefs,raw,index.md,trends.md}` + `kai/ra_archive.py` (post-render archiver, idempotent) + `kai/ra_context.py` (pre-synth context loader, matches today's gather against the archive) + `newsletter/newsletter.sh` wired to call both + `newsletter/prompts/synthesize.md` taught to emit entities/topics/lab_items in frontmatter and consume `.context.md` + `bin/kai.sh ra` subcommand with index/trends/entity/topic/lab/search/since/rebuild/archive/context. Today's brief retrofitted and filed as the first entry (5 entities, 4 topics, 3 lab items). Smoke-tested with a fake 2026-04-12 gather — alias matching correctly surfaced Fed/Bitcoin/Marimo and ignored unrelated records. Ra manifest bumped to 2.1.0-ra with new memory:* capabilities and the pipeline stages updated to include pre-context and archive steps.
- [x] **2026-04-11** **PRN continuity fix.** `newsletter/prompts/synthesize.md` "Prior context" block and `kai/ra_context.py` rendered header both rewritten to frame the research archive as PRN (pro re nata — as needed, not on schedule). Explicit when-to-reach / when-to-skip lists. Ra is no longer pushed to mechanically weave callbacks — the brief is not a daily sequel. Most briefs should stand on their own, with the archive used when a hinge fired, a trend turned, or a lab note is directly relevant.
- [x] **2026-04-11** **Aurora Public simulation 01 (first trial run) passed.** 41-record synthetic gather spanning the full 30-topic taxonomy × 5 simulated subscribers designed to exercise every voice (gentle/balanced/sharp), every depth (headlines/balanced/deep-dives), and every length knob (3/6/12min). Ran live against `claude_code:claude-code-cli` → 5 briefs generated, 0 errors, ~6m33s total wall time. Filter routed records correctly (6/13/9/10/11 matched per sub). Voice knob is audibly distinct — the five briefs read like five different writers. Depth knob works. Length knob works 3min perfectly but biases short on 6min (~9% under) and 12min (~15% under) — filed as prompt tuning P1. Free-text subscriber context used implicitly (never parroted). Inline jargon glosses selective (glosses `dot plot`/`deposit betas`/`MiCA`/`Sparse-MoE` for the finance brief, correctly does NOT gloss `NII` or `TVL`). PRN context correctly skipped for all five profiles (no natural overlap with existing archive). `send_email.py --dry-run` rendered all 5 dark-palette HTML emails cleanly with frontmatter-derived subject lines. Full report at `kai/logs/aurora-public-sim-2026-04-11.md`; raw outputs at `kai/logs/aurora-sim-2026-04-11/`.
- [x] **2026-04-11** **Aurora Public v0 shipped end-to-end.** The consumer-facing sibling of Ra. One shared pipeline, per-subscriber output tuned to topics/voice/depth/length. Files: `docs/aurora-public.md` (design doc), `website/aurora.html` (single-page chat-style intake with 30-topic grid + voice/depth/length + 240-char freetext + email, progressive reveal, <60s target, Dawn palette), `website/api/aurora-subscribe.js` (Vercel endpoint, validation, structured log persistence), `newsletter/aurora_public.py` (per-sub generator reusing synthesize.py backends, topic-keyword filtering, PRN context block, manifest output), `newsletter/send_email.py` (Resend + SMTP dispatch, HTML + plain text rendering via render.py, lastSent stamping), `newsletter/aurora_public.sh` (pipeline wrapper: gather → ra_context → aurora_public → send_email), `newsletter/subscribers.jsonl` (placeholder), `NFT/agents/aurora.hyo.json` bumped to 2.2.0-public-v0 with new `products` array. Ra remains the sole archive author; Aurora Public reads but never writes. Smoke-tested: `--preview --dry-run` plan emitted correctly; `send_email.py --dry-run` with a seeded subscriber rendered 2145-char HTML + 458-char text with the right frontmatter-derived subject line. Stdlib only, safe for cron/launchd.

_(2026-04-12 cleanup: removed 4 stale sentinel auto-filed items referencing old session path `/sessions/clever-beautiful-cray/`. These were environmental — aurora not running and API health unreachable are both documented sandbox limitations, not code bugs.)_

- [x] **2026-04-12** Nel, Ra, Sam agents built, verified end-to-end (multiple runs each, idempotent). Bugs fixed: `set -e` → `set -uo pipefail` across all three, sentinel pattern matching, Python heredoc variable injection, subscriber count double-output.
- [x] **2026-04-12** Full 6-project consolidation verified (Hyo, Aurora/Ra, Aether, Kai CEO, Nel, Sam) — runs clean, idempotent, simulation included.
- [x] **2026-04-12** Scheduled tasks cleaned up: `nightly-per-project-consolidation` updated to 6 projects + Nel + Ra health checks; old `nightly-consolidation` and `nightly-simulation` disabled (superseded).
- [x] **2026-04-12** HQ Dashboard v7 — complete rewrite. Plus Jakarta Sans + JetBrains Mono fonts, light/dark mode toggle, Nel + Sam views, premium design, responsive.
- [x] **2026-04-12** Ra newsletter aesthetics overhaul — body font changed from DM Mono to Plus Jakarta Sans (16px, wt 400, lh 1.8), JetBrains Mono for code, richer colors, better spacing. Template in render.py updated, 2026-04-11 newsletter re-rendered.
- [x] **2026-04-12** Full folder reorganization — top-down agent-centric structure. agents/{nel,ra,sam}/ each own their runners, logs, memory, products. Symlinks at root for backward compat. All scripts updated, all agents re-verified.
- [x] **2026-04-12** Research page shipped — `research.html` on hyo.world, browsable Ra research archive with entities/topics/lab tabs. HQ sidebar updated with Intelligence → Research nav link.
- [x] **2026-04-12** Nel upgraded to nightly file/folder auditor (Phase 10). Checks agent runners, manifest validity, security permissions, large files, sensitive file leaks, repo size.
- [x] **2026-04-12** All scheduled tasks updated with new agent paths post-reorg. CLAUDE.md rewritten with agent delegation rules and "never ask permission" mandate.

- [x] **2026-04-12** [cipher] ~~P0 founder-token-leak~~ FALSE POSITIVE — `agents/nel/security/` IS `.secrets/` via symlink. cipher.sh fixed to exclude symlink target. [cipher:founder-token-leak:ce83eed1]
- [x] **2026-04-12** Task dispatch system (`bin/dispatch.sh`) built and hardened. JSONL append-only ledger per agent + Kai cross-ref. Python-safe JSON generation. Full lifecycle: delegate → ACK → report → verify → close. Ledger protocol documented at `kai/ledger/PROTOCOL.md`.
- [x] **2026-04-12** Kai→Sam simulation complete (5 tasks): console.log audit (correctly identified as MVP persistence), static file test coverage expanded (3 new HTML files), manifest descriptions added to all 6 agents, API endpoint inventory created.
- [x] **2026-04-12** Kai→Nel simulation complete (5 tasks): dispatch.sh audit (6 issues found, 3 critical fixed), agent runner exit code verification (all 3 exit 0), hardcoded path scan (HYO_ROOT pattern consistent), secrets scan (clean), permissions audit (all 700/600, watch-deploy.sh fixed).
- [x] **2026-04-12** Kai→Ra simulation complete (5 tasks): archive integrity verified (12/12 match), source coverage audited (15 sources, 7 fetchers, culture/sports gaps noted), output dir validated (1 edition, clean), prompt↔renderer alignment confirmed, archive summary report published to HQ.
- [x] **2026-04-12** Agent processing patterns documented (`kai/AGENT_PROCESSING_PATTERNS.md`): Sam=individual tasks, Nel=investigation batches, Ra=pipeline-stage health checks.
- [x] **2026-04-12** Bidirectional dispatch protocol: `dispatch flag` (upward issue reporting), `dispatch escalate` (blocked task), `dispatch self-delegate` (agent autonomous task creation). All wired into agent runners (nel.sh Phase 11, sam.sh test summary, ra.sh health report).
- [x] **2026-04-12** Safeguard cascade system: P0/P1 flags auto-trigger Nel cross-reference + Sam test coverage + memory log. `dispatch safeguard` command. Known-issues memory at `kai/ledger/known-issues.jsonl`.
- [x] **2026-04-12** Nightly delegation simulation (`dispatch simulate`): 5-phase validation (delegation lifecycle, upward comms, runners, cross-ref, regression). First run: 24 pass, 2 fail (environmental). Scheduled at 23:30 MT daily.
- [x] **2026-04-12** Per-agent execution algorithms documented (`kai/AGENT_ALGORITHMS.md`): complete runbooks with closed-loop handshaking, preventive triggers, memory read/write protocols.
- [x] **2026-04-12** CLAUDE.md hydration protocol expanded: now includes known-issues, simulation outcomes, agent algorithms, agent ACTIVE.md files. Every session starts with `dispatch health` + `dispatch status`.
- [x] **2026-04-12** HQ v8.1 deployed and verified live — lowercase title, OpenAI/Claude usage pages with real CSV data + budget bars, all dead links purged, Ra/Nel/Sim/Aetherbot views rebuilt, MTN timestamps, research sorted with NEW badges.
- [x] **2026-04-12** Pre-deploy validation script (`bin/predeploy-validate.py`) — 6 automated checks wired into `kai deploy` and `kai gitpush`. Prevents dead links, orphaned IDs, UTC timestamps, and dead handlers from reaching production.
- [x] **2026-04-12** Delegation checklist added to `kai/AGENT_ALGORITHMS.md` and wired into CLAUDE.md operating rules.
- [x] **2026-04-13** Zero copy-paste achieved — queue round-trip proven (git, launchctl, all commands). `kai exec` helper built. NEVER-COPY-PASTE rule wired into CLAUDE.md and AGENT_ALGORITHMS.md.
- [x] **2026-04-13** Nel v2.0 shipped — 8-phase autonomous QA cycle (link validation, security scan, API health, data integrity, agent health, deployment verification, research sync, report+dispatch). Research report: `agents/ra/research/lab/nel-qa-architecture-research.md`.
- [x] **2026-04-13** Nel QA daemon installed (com.hyo.nel-qa, q6h via launchd). First cycle ran: 16s, found real issues (gitignore + API auth).
- [x] **2026-04-13** Link checker built (`agents/nel/link-check.sh`) — checks HTML links, JS fetch paths, markdown refs, and live HTTP responses.
- [x] **2026-04-13** Queue worker hardened: 5-min max timeout cap (was unlimited — sleep 1800 blocked worker). Healthcheck recheck fixed to not use sleep in queue.
- [x] **2026-04-13** All 5 agent runners fixed: Python `true`/`false` → `True`/`False`, Dex `local` outside function.
- [x] **2026-04-13** Index.html mobile fixed — touch-friendly, no hover dependency, stacked layout, hidden decorations on small screens.
- [x] **2026-04-13** Research.html made dynamic — reads file lists from index.md instead of hardcoded arrays.
- [x] **2026-04-13** Research sync script + auto-sync in Nel QA cycle. Missing research files synced to website/docs/research/.
- [x] **2026-04-13** Auto-publish rule wired — research must be saved, synced, AND pushed to HQ every time. All agents.
- [x] **2026-04-13** MTN timezone rule wired into CLAUDE.md — all user-facing output uses America/Denver.
- [x] **2026-04-13** Agent self-improvement autonomy wired — agents CAN make changes PRN, MUST communicate via dispatch. Nightly research cycle.
- [x] **2026-04-12** 4 recurrence patterns logged to `kai/ledger/known-issues.jsonl` with mitigations.
- [x] **2026-04-12** All 15 broken research .md links fixed (newsletters/ → ra/ paths). website/ converted from symlink to real directory for git tracking.

_(2026-04-13 cleanup: removed 4 stale sentinel escalations referencing old session path `/sessions/vigilant-nifty-darwin/`. These were environmental — aurora sandbox limitations documented. API health check was session-specific, not a code bug.)_

- [x] **2026-04-13** Aether + Dex agents formalized — manifests, runners, ledgers, algorithms. 8/8 test pass each. Aetherbot→Aether rename (40+ files), Ledger→Dex rename (19+ files).
- [x] **2026-04-13** AETHER_OPERATIONS.md v2.0 — rewritten from actual AetherBot source data (70+ files parsed).
- [x] **2026-04-13** Kai↔Aether approval loop + GPT fact-check routing to Aether.
- [x] **2026-04-13** Dex daily intelligence scanning (Phase 6A daily, 6B Monday deep synthesis). Ra research coordination protocol for all agents.
- [x] **2026-04-13** Agent Creation Protocol v2.0 (`docs/AGENT_CREATION_PROTOCOL.md`) — 14-section blueprint. v2.0: added PLAYBOOK, evolution.jsonl, reflection, autonomy, 11-point testing, domain growth.
- [x] **2026-04-13** Continuous Learning Protocol — all agents, Dex enforces anti-stale.
- [x] **2026-04-13** [AUTOMATE] **Command queue (`kai/queue/`)** — Kai submits commands via JSON, Mini worker daemon auto-executes, Kai reads results. Zero copy/paste for routine ops. Proxy stripping, macOS timeout compat, security filter.
- [x] **2026-04-13** [AUTOMATE] **2-hour health check** — Cowork scheduled task. Checks P0/P1 flags, stale tasks, queue health, agent output. What's Next gate auto-dispatches remediation.
- [x] **2026-04-13** Research.html split-pane rewrite — left panel (tabs + item list), right panel (in-page markdown reader). No new tabs. Mobile responsive. Deployed live at hyo.world/research.
- [x] **2026-04-13** Research index updated — 3 new lab entries added (Nel QA research, Ops Audit, Cowork Sandbox Bridge). Dynamic discovery working.
- [x] **2026-04-13** Site bottom nav bar added to index.html. HQ research link fixed (window.open → `<a>` tag).
- [x] **2026-04-13** All 9 research files enriched — entities (5) and topics (4) expanded from 12-18 lines to 61-89 lines with real data, analysis, outlook, sources.
- [x] **2026-04-13** Aether dashboard data updated — simulated M-F April 6-10 trading metrics. hq.html rendering bug fixed (t.timestamp → t.ts).
- [x] **2026-04-13** Nel GitHub security scanner built (9 scan types, Phase 2.5 in QA cycle). .gitignore hardened with credentials.json, *.p12, *.pfx.
- [x] **2026-04-13** Runner fixes: nel.sh exit code (70-89 → exit 0), ra.sh TODAY unbound variable.
- [x] **2026-04-13** Simulations run in serial: 24 pass, 2 fail (runner issues now fixed).
- [x] **2026-04-13** What's Next gate wired into dispatch.sh + AGENT_ALGORITHMS.md. No agent detects a problem and only logs it.
- [x] **2026-04-13** Step-by-step instruction protocol wired into CLAUDE.md + AGENT_ALGORITHMS.md.
- [x] **2026-04-13** [AUTOMATE] **Aether launchd installed** — `com.hyo.aether` running every 15 min.
- [x] **2026-04-13** [AUTOMATE] **Dex launchd installed** — `com.hyo.dex` running daily 23:00 MT.
- [x] **2026-04-13** [AUTOMATE] **MCP tunnel launchd fixed** — TCC bypass (WorkingDirectory /tmp), install script.
- [x] **2026-04-13** [AUTOMATE] **Nel dispatch flag calls wired** — nel.sh calls `dispatch flag` after each phase. _(Audit B4 — DONE)_
- [x] **2026-04-13** [AUTOMATE] **dispatch simulate-review built** — reads simulation-outcomes.jsonl, auto-flags failures. _(Audit B5 — DONE)_
- [x] **2026-04-13** OpenAI API key placed at `agents/nel/security/openai.key`. Aether GPT fact-checking active.
- [x] **2026-04-13** Full Disk Access granted to `/bin/bash` on Mini. Fixes TCC for all launchd bash scripts.
- [x] **2026-04-13** [AUTOMATE] **Daily bottleneck audit** (`kai/queue/daily-audit.sh`) — Kai reviews all agents daily at 22:00 MT. Checks ACTIVE.md freshness, ledger logs, runner output, daemon health, queue status, automation gaps. Scheduled via Cowork.
- [x] **2026-04-13** **Agent self-review protocol** — wired into AGENT_ALGORITHMS.md + all 5 agent runners (nel.sh, sam.sh, ra.sh, aether.sh, dex.sh). Each agent audits own pipeline: input→processing→output→external→reporting. Breaks auto-dispatch flags.
- [x] **2026-04-13** **All 6 agent ACTIVE.md cleaned** — stale sim-test entries purged, status categories applied ([NEEDS HYO], [KAI DOING], [AUTO-VERIFY]).
- [x] **2026-04-13** **Aurora plist fixed** — user path xkai808→kai, WorkingDirectory→/tmp (TCC).
- [x] **2026-04-13** [AUTOMATE] **Consolidation launchd plist** — `com.hyo.consolidation.plist` for nightly 01:00 MT.
- [x] **2026-04-13** [AUTOMATE] **Simulation launchd plist** — `com.hyo.simulation.plist` for nightly 23:30 MT.
- [x] **2026-04-13** **`kai audit` subcommand** — runs daily bottleneck audit on demand.
- [x] **2026-04-13** **Agent autonomy framework** — PLAYBOOK.md for all 5 agents (self-managed operational manual), evolution.jsonl (learning log), self-evolution phase wired into all runners. Agents can modify own checklists, propose improvements, log decisions. Kai holds override via constitution (AGENT_ALGORITHMS.md).
- [x] **2026-04-13** **Agent-specific self-review checklists** — unique per agent with actual files, commands, exit codes, metrics. Not generic copy-paste.
- [x] **2026-04-13** **Scheduled task sequencing fixed** — Dex 23:00 → Sim 23:30 → Consolidation 01:00 → Audit 02:00 → Aurora 03:00. Disabled duplicate Cowork tasks superseded by launchd.
- [x] **2026-04-13** **Real-time usage data** — `/api/usage` endpoint reads CSVs, `usage-config.json` for budgets, `refresh-usage.sh` for API pulls. HQ fetches dynamically, auto-refreshes 60s.
- [x] **2026-04-13** **HQ mobile responsive** — bottom nav at 768px, 44px+ touch targets, scrollable tables, 480px ultra-compact. Comprehensive CSS overhaul.
- [x] **2026-04-13** **HQ push verification** — kai push verifies data arrived at HQ endpoint, retries once on failure.
- [x] **2026-04-13** **Protocol staleness prevention** — PLAYBOOK >7d=P2, >14d=P1, evolution.jsonl >48h=P1. Wired into daily audit, agent self-evolution, and CLAUDE.md operating rules.

- [ ] **[K]** [sentinel] missing or empty /sessions/affectionate-relaxed-franklin/mnt/Hyo/newsletters/2026-04-12.md [sentinel:aurora-ran-today:e98fd1df] _(filed 2026-04-12)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/affectionate-relaxed-franklin/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:d986a828] _(filed 2026-04-12)_
- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 6 runs in a row: health endpoint not green or token unconfigured [sentinel:api-health-green:82547bfc:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/affectionate-relaxed-franklin/mnt/Hyo/newsletters/2026-04-12.md [sentinel:aurora-ran-today:e98fd1df:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/affectionate-relaxed-franklin/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:d986a828:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/fervent-sweet-newton/mnt/Hyo/newsletters/2026-04-12.md [sentinel:aurora-ran-today:c7767404] _(filed 2026-04-12)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/fervent-sweet-newton/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:6688e451] _(filed 2026-04-12)_
- [ ] **[K]** [sentinel] 10 P0 tasks (overload threshold 5) [sentinel:task-queue-size:d2598827] _(filed 2026-04-12)_

- [ ] **[K]** [sentinel] missing or empty /sessions/brave-modest-cori/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:599f97b6] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/brave-modest-cori/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:bff8d8d6] _(filed 2026-04-13)_

- [ ] **[K]** [sentinel] missing or empty /sessions/sharp-loving-mendel/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:966539e7] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/sharp-loving-mendel/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:eb18cd53] _(filed 2026-04-13)_

- [ ] **[K]** [sentinel] missing or empty /sessions/stoic-practical-franklin/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:0d0aa335] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/stoic-practical-franklin/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:a44e5467] _(filed 2026-04-13)_

- [ ] **[K]** [sentinel] missing or empty /sessions/pensive-intelligent-euler/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:dbac3f9f] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/pensive-intelligent-euler/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:38dd677e] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] **ESCALATED** P2 elevated — failing 5 runs in a row: 10 P0 tasks (overload threshold 5) [sentinel:task-queue-size:d2598827:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/practical-focused-goldberg/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:135da226] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/practical-focused-goldberg/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:5ae870c6] _(filed 2026-04-13)_

- [ ] **[K]** [sentinel] missing or empty /sessions/gracious-optimistic-mayer/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:f9e5690d] _(filed 2026-04-13)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/gracious-optimistic-mayer/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:e4024e70] _(filed 2026-04-13)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/gracious-optimistic-mayer/mnt/Hyo/newsletters/2026-04-13.md [sentinel:aurora-ran-today:f9e5690d:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/gracious-optimistic-mayer/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:e4024e70:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/gracious-tender-davinci/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:3964dca3] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/gracious-tender-davinci/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:fe3f475c] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] 17 P0 tasks (overload threshold 5) [sentinel:task-queue-size:8abe625d] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/gracious-tender-davinci/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:3964dca3:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/gracious-tender-davinci/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:fe3f475c:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/nifty-confident-bell/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:f658836f] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/nifty-confident-bell/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:e374955a] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/nifty-confident-bell/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:f658836f:escalated]
- [ ] **[K]** [sentinel] **ESCALATED** P2 elevated — failing 5 runs in a row: 17 P0 tasks (overload threshold 5) [sentinel:task-queue-size:8abe625d:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/nifty-confident-bell/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:e374955a:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/optimistic-beautiful-bell/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:d991b6d2] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/optimistic-beautiful-bell/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:fb9d8666] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/optimistic-beautiful-bell/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:d991b6d2:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/optimistic-beautiful-bell/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:fb9d8666:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/pensive-stoic-lovelace/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:ffa64cc7] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/pensive-stoic-lovelace/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:9065fe19] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] missing or empty /sessions/nifty-jolly-dijkstra/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:378e5901] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/nifty-jolly-dijkstra/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:562ae619] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/nifty-jolly-dijkstra/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:378e5901:escalated]

- [ ] **[K]** [sentinel] missing or empty /sessions/confident-relaxed-lovelace/mnt/Hyo/newsletters/2026-04-14.md [sentinel:aurora-ran-today:99aa58ee] _(filed 2026-04-14)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/confident-relaxed-lovelace/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:d814cd3c] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] no aurora logs in /sessions/nifty-friendly-wozniak/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:a76d4ff3] _(filed 2026-04-14)_

- [ ] **[K]** [sentinel] missing or empty /sessions/modest-tender-ramanujan/mnt/Hyo/newsletters/2026-04-15.md [sentinel:aurora-ran-today:9d94093b] _(filed 2026-04-15)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/modest-tender-ramanujan/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:4b240f39] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/modest-tender-ramanujan/mnt/Hyo/newsletters/2026-04-15.md [sentinel:aurora-ran-today:9d94093b:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/trusting-nice-cray/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:610a02c0] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/trusting-nice-cray/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:610a02c0:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/clever-cool-keller/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:2644d920] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] no aurora logs in /sessions/busy-practical-cray/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:40b9d398] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/busy-practical-cray/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:40b9d398:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/vibrant-youthful-pasteur/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:c05f0eb3] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/vibrant-youthful-pasteur/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:c05f0eb3:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/modest-funny-goldberg/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:74bfd26f] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/modest-funny-goldberg/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:74bfd26f:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/inspiring-funny-clarke/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:6b0b62a9] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] no aurora logs in /sessions/beautiful-wizardly-mayer/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:be5e0cab] _(filed 2026-04-15)_

- [ ] **[K]** [sentinel] missing or empty /sessions/clever-dazzling-gauss/mnt/Hyo/newsletters/2026-04-16.md [sentinel:aurora-ran-today:f7e7cb1b] _(filed 2026-04-16)_
- [ ] **[K]** [sentinel] no aurora logs in /sessions/clever-dazzling-gauss/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:e05a9cc4] _(filed 2026-04-16)_

- [ ] **[K]** [sentinel] **ESCALATED** P0 escalated — failing 2 runs in a row: missing or empty /sessions/clever-dazzling-gauss/mnt/Hyo/newsletters/2026-04-16.md [sentinel:aurora-ran-today:f7e7cb1b:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/clever-dazzling-gauss/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:e05a9cc4:escalated]

- [ ] **[K]** [sentinel] founder.token mode is 0600, want 6xx [sentinel:founder-token-integrity:92e7b89e] _(filed 2026-04-17)_
- [ ] **[K]** [sentinel] no aurora logs in /Users/kai/Documents/Projects/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:a2875b77] _(filed 2026-04-17)_
- [ ] **[K]** [sentinel] 0755 (want 700) — run: chmod 700 /Users/kai/Documents/Projects/Hyo/.secrets [sentinel:secrets-dir-permissions:6717d4df] _(filed 2026-04-17)_
- [ ] **[K]** [sentinel] 25 P0 tasks (overload threshold 5) [sentinel:task-queue-size:9de2a565] _(filed 2026-04-17)_

---

## STRATEGIC ROADMAP — Set 2026-04-17 by Hyo

### Next 24h (due by end of 2026-04-18)

- [ ] **[B]** **REMOTE-001: Establish reliable remote access to Mini.** Hyo needs to be able to reach the Mini from any device. Options: Tailscale (recommended — zero config VPN), SSH tunnel, or ngrok. Sam builds the setup script. Kai verifies handshake. This gates all queue-dependent work.
- [ ] **[B]** **REMOTE-002: Claude app on Pro has access to everything on Pro.** Audit what the Claude desktop app can and cannot access on the Pro machine. Grant folder access to /Documents/Projects/Hyo and any relevant dirs. Test that file tools work end-to-end.
- [ ] **[K]** **IMPROVEMENT-001: Each agent implements their researched improvement this cycle.** No more research-theater. Every agent with a completed ARIC cycle (has_aric_data=true) must ship their Phase 6 improvement today: Nel → supply chain scanner (TASK-004), Sam → Lighthouse CI regression test (TASK-009), Aether → reconciliation verification (TASK-007), Ra → analytics tracking verification (TASK-008), Dex → repair engine test (TASK-006).
- [ ] **[K]** **IMPROVEMENT-002: Verify all 5 agent improvements with proof.** Each improvement: commit hash, test result, HQ confirmation. No sim-ack. No "queued." Either it shipped or it didn't.

### <1 Week (due by end of 2026-04-24)

- [ ] **[B]** **AURORA-001: Aurora end-to-end functioning test.** Aurora is the newsletter AI pipeline. Test every avenue: gather.py (sources returning data), synthesize.py (Claude API call returns synthesis), render.py (HTML output), send_email.py (email delivered). Document what's broken, fix each one, verify with sent newsletter.
- [ ] **[B]** **AURORA-002: Aurora shipped publicly on site.** Newsletter accessible at hyo.world/newsletters or /daily/. Archive browsable. Subscribe flow. Proof: Hyo can read today's newsletter from the public URL.
- [ ] **[B]** **BLOCKCHAIN-001: HyoRegistry.sol contract complete and deployed.** Read HyoRegistry_Notes.md, HyoRegistry_CreditSystem.md, HyoRegistry_Marketplace.md. Identify gaps vs current implementation. Deploy to testnet (Base Goerli or Polygon Mumbai). Verify mint function works.
- [ ] **[B]** **BLOCKCHAIN-002: NFT minting integrated with hyo.world.** Mint button on site connects to deployed contract. Hyo can mint an NFT from the site. Proof: transaction hash on testnet explorer.
- [ ] **[B]** **MARKETPLACE-001: Marketplace and Cafe up and running.** Design: Marketplace = NFT trading/listings on hyo.world. Cafe = community hub (or content area — clarify with Hyo). Both accessible from site nav. MVP: browsable UI, backend stubs, at least 1 working transaction flow.
- [ ] **[B]** **APP-001: Hyo management app — architecture decision.** App for: (1) management of hyo.world, (2) personal communication with Kai, (3) reading HQ material on the go. Options: PWA (already started — manifest.json + sw.js shipped), React Native, Flutter. Decision gates all other app work. Hyo decides stack.
- [ ] **[B]** **APP-002: Hyo app MVP shipped.** Based on APP-001 decision: dashboard view (feed, aether, agent status), message Kai interface, newsletter reader. Deployable to Hyo's phone as PWA or installable app.


- [ ] **[K]** [sentinel] no aurora logs in /sessions/optimistic-eager-tesla/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:0e638713] _(filed 2026-04-17)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/optimistic-eager-tesla/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:0e638713:escalated]

- [ ] **[K]** [sentinel] **ESCALATED** P2 elevated — failing 5 runs in a row: 25 P0 tasks (overload threshold 5) [sentinel:task-queue-size:9de2a565:escalated]

- [ ] **[K]** [sentinel] missing or empty /Users/kai/Documents/Projects/Hyo/newsletters/2026-04-18.md [sentinel:aurora-ran-today:e7fccf38] _(filed 2026-04-18)_
- [ ] **[K]** [sentinel] 30 P0 tasks (overload threshold 5) [sentinel:task-queue-size:385b8938] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] no aurora logs in /sessions/funny-inspiring-ritchie/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:8a8ea7f3] _(filed 2026-04-18)_
- [ ] **[K]** [sentinel] malformed: hyo.hyo.json  [sentinel:manifest-valid-json:feba7696] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/funny-inspiring-ritchie/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:8a8ea7f3:escalated]
- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: malformed: hyo.hyo.json  [sentinel:manifest-valid-json:feba7696:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/admiring-brave-cannon/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:3dff5398] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/admiring-brave-cannon/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:3dff5398:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/adoring-nifty-wright/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:b02c4059] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] no aurora logs in /sessions/dreamy-fervent-keller/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:755c6478] _(filed 2026-04-18)_
- [ ] **[K]** [sentinel] 26 P0 tasks (overload threshold 5) [sentinel:task-queue-size:40b61f0b] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] no aurora logs in /sessions/gifted-dreamy-edison/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:4ceeed88] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/gifted-dreamy-edison/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:4ceeed88:escalated]
- [ ] **[K]** [sentinel] **ESCALATED** P2 elevated — failing 5 runs in a row: 26 P0 tasks (overload threshold 5) [sentinel:task-queue-size:40b61f0b:escalated]

- [ ] **[K]** [sentinel] no aurora logs in /sessions/blissful-gracious-bohr/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:6ace22d3] _(filed 2026-04-18)_

- [ ] **[K]** [sentinel] **ESCALATED** P1 elevated — failing 3 runs in a row: no aurora logs in /sessions/blissful-gracious-bohr/mnt/Hyo/agents/nel/logs [sentinel:scheduled-tasks-fired:6ace22d3:escalated]
