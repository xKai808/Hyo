# KAI_TASKS Done Archive (pre 2026-04-23)

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
