# KAI_BRIEF.md

**Purpose:** This is the persistent memory layer for Kai across sessions and devices. Any new Claude/Kai instance — Cowork Pro, Claude Code on the Mini, future agents — reads this first and gets oriented in under 60 seconds.

**Updated:** 2026-04-12 late night (HQ v8.1 deployed + pre-deploy validation + live verification)
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

## Operational model (established 2026-04-12)

**How Kai executes without Hyo pasting commands:**
- **File edits:** Kai edits files via Cowork mounted folder → sync to Mini instantly.
- **Auto-push to HQ:** `sentinel.sh`, `cipher.sh`, and `newsletter.sh` all call `kai push` at the end of every run. The HQ dashboard (`hyo.world/hq`) populates itself from live push data. No manual pushes needed.
- **Unified HQ endpoint:** All dashboard ops (auth, push, data) go through `/api/hq?action={auth|push|data}` — single Vercel lambda, shared `globalThis` in-memory store. Push and data share state because they're the same function.
- **Auto-deploy:** `kai watch` starts an fswatch watcher on `website/` that auto-deploys to Vercel when files change. Requires `brew install fswatch` on the Mini. Run once: `nohup kai watch &`
- **Cowork sandbox limitation:** Scheduled tasks created via Cowork run in a sandboxed environment that blocks outbound HTTPS. They CANNOT run `kai deploy`, `kai push`, or anything that needs network. The existing cron/launchd tasks on the Mini DO have full network access — that's where pipeline scripts with auto-push actually run.
- **HQ password:** server-side auth via `/api/hq?action=auth`. SHA-256 hash comparison + HMAC session tokens (24h expiry). Dashboard at `hyo.world/hq`.

## Current state (as of 2026-04-13 01:00 MT — command queue operational, all daemons live)

**Running daemons on Mini (all confirmed via `launchctl list | grep hyo`):**
- `com.hyo.queue-worker` — file-based command queue, auto-processes `kai/queue/pending/`
- `com.hyo.dex` — daily at 23:00 MT (integrity, compaction, patterns, daily intel)
- `com.hyo.aether` — every 15 min (trade metrics, dashboard, GPT fact-check)
- `com.hyo.mcp-tunnel` — cloudflared tunnel to MCP server on port 3847

**Scheduled tasks (Cowork):**
- `kai-health-check` — every 2 hours, checks flags/stale tasks/queue/agent output

**Active infrastructure:**
- Command queue: Kai writes JSON to `kai/queue/pending/`, daemon executes on Mini, Kai reads `completed/`. Zero copy/paste for routine ops. Tested end-to-end.
- OpenAI API key: placed at `agents/nel/security/openai.key` (24 bytes). Aether GPT fact-checking active.
- Full Disk Access: granted to `/bin/bash` on Mini. Fixes TCC for all launchd bash scripts.

**Shipped this session (eighth pass — command queue + autonomous operations):**
- **Command queue (`kai/queue/`)** — worker.sh, submit.py, com.hyo.queue-worker.plist. Kai submits, Mini executes, Kai reads result. Security filter blocks dangerous patterns. macOS timeout compatibility (gtimeout/fallback). Proxy stripping for git operations.
- **2-hour health check** — scheduled via Cowork. Checks P0/P1 flags, stale tasks, queue health, agent output freshness. What's Next gate: auto-dispatches remediation on findings, queues accelerated re-check on P0.
- **What's Next gate** — wired into AGENT_ALGORITHMS.md and dispatch.sh. No agent is allowed to detect a problem and only log it. Detection → route to owner → fix → verify.
- **Step-by-step instruction protocol** — wired into CLAUDE.md and AGENT_ALGORITHMS.md. When Hyo must act: numbered steps, one command per step, expected output, failure fallback. Non-negotiable.
- **Dex + Aether launchd plists** — built, installed, running
- **Commits:** `8683c4b` → `f5fc5bc` → `1be9a65` → `1784de9` → `bd729a3` → `5efc23a` → `bb99353` → `f040dde`

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

## Current state (as of 2026-04-12 cipher hourly — 20:02 UTC)

**Cipher run #51:** 2 findings (both P2 — gitleaks/trufflehog not installed, environmental). 0 leaks. 0 autofixes.
- **False positive caught and fixed:** `founder-token-leak` P0 was firing because `grep --exclude-dir=.secrets` didn't exclude `agents/nel/security/` (the symlink target). The token was only ever in the one correct location. Fix: added `--exclude-dir=security` to cipher.sh's Layer 4 token search. Marked as false positive in cipher state. Auto-filed KAI_TASKS entry resolved.
- Permissions: `.secrets/` = 700, `founder.token` = 600. Clean.
- Run 51 of 51 with 0 verified leaks lifetime.

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
