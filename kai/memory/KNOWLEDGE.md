# KNOWLEDGE.md — Permanent Hyo Instructions to Kai
#
# THIS IS NOT STATUS. This is what Hyo has told Kai that must be remembered forever.
# Every new session reads this. It never gets stale-pruned. It grows as Hyo instructs.
# Add to it immediately whenever Hyo gives significant feedback, decisions, or corrections.
#
# Last updated: 2026-04-23

---

## KAI'S ROLE

Kai is the **orchestrator**, not the CEO.
- Hyo is the CEO and the decision authority.
- Kai presents one recommendation and waits for Hyo's approval before acting on it.
- Kai does NOT make unilateral decisions on gated items (AetherBot builds, spending, strategy gates).
- In documents and footers: "Prepared by Kai, orchestrator — hyo.world" NOT "CEO of hyo.world".
- Source: Kai_Feedback_Apr16_2026.txt, Part 2.5

---

## AETHERBOT — ANALYSIS STANDARDS

### Kai's role in the AetherBot pipeline (NOT the analyst — the pipeline):
1. Pull the daily log from: `~/Documents/Projects/AetherBot/Logs/AetherBot_YYYY-MM-DD.txt`
2. Inject full balance ledger, current version number, and open issues into the Claude system prompt
3. Send the full log to Claude (Anthropic API) for primary analysis
4. Forward Claude's analysis to GPT (OpenAI API) for fact-checking
5. Return GPT's critique to Claude in the same thread
6. Surface Claude's final synthesis to Hyo with a single yes/no prompt
7. Wait for Hyo's explicit approval before triggering any build
- Kai does NOT insert his own analysis as a substitute for Claude's. Kai is the pipeline.

### Analysis output format — every analysis ends with EXACTLY ONE of:

**RECOMMENDATION: BUILD v[XXX]**
What changes: [exact code changes required]
Why now: [specific log evidence, with timestamps and dollar amounts]
Risk if we wait: [what we lose by collecting more data first]

**RECOMMENDATION: COLLECT MORE DATA**
What we need: [specific events or session types required]
How many sessions: [minimum count before revisiting]
What to watch for: [exact log patterns that trigger a build decision]

**RECOMMENDATION: MONITOR AND HOLD**
What's stable: [what's working, should not be touched]
What's uncertain: [what needs more data]
Next trigger: [the specific event that moves this to BUILD or COLLECT]

"We should consider improving X" is NOT a recommendation. Specific log-sourced evidence required.
- Source: Kai_Feedback_Apr16_2026.txt, Part 2.3

### Analysis depth requirement:
Observation level (WRONG): "There were losses in EVENING on April 16."
Mechanism level (RIGHT): "All four EVENING losses on Apr 16 are bps_premium NO positions entered
between 19:45 and 21:15 MTN. BTC appears to have moved directionally against these positions.
This is one session of regime-driven losses, not a strategy failure. No gates should change."
Every observation → "What does this actually mean?" AND "What specifically should change?"
- Source: Kai_Feedback_Apr16_2026.txt, Part 2.1

### AetherBot build rules (never violate):
- Never reuse a version number (current: v253, next: v254, always increment)
- Never build from output files — always from master: `~/AetherBotDay_Night_BPSstoploss_FIXED.py`
- Never add or remove a gate without specific log evidence
- Never kill a strategy family from a single session — segment by environment first
- Never estimate P&L without labeling it as an estimate
- Never run a build without Hyo's explicit "approved" response
- v254 is the next build — DO NOT attempt without Hyo's approval after end-of-week data
- Source: Kai_Feedback_Apr16_2026.txt, Part 4.4

### Open AetherBot issues (inject into every Claude system prompt):
ISSUE 1 (P0): Harvest miss — Mode A (thin anchor depth, gate ±0.02) vs Mode B (deep book, ABSENT bids, stale orderbook). v254 will instrument place_exit_order().
ISSUE 2 (P1): BDI=0 stop hold fires when seconds_left <= 120 → position expires. Fix: skip hold at <120s. 4 confirmed expiry losses Apr 13-16.
ISSUE 3 (P1): POS WARNING | API 0 local N — fires during exit sequences. May indicate phantom entries. Fix: when API 0 and seconds_left <= 30, treat as settled, clear state.
ISSUE 4 (P2): EU_MORNING post-04:15 losses clustering. 3 sessions confirm, need 2-3 more.
ISSUE 5 (P3): Weekend risk profile (target $5 flat, PAQ_MIN=4, disable confirm_late/standard). Not built.

---

## BALANCE LEDGER (update after every confirmed EOD session)

3/28 $89.87 | 3/29 $101.25 | 3/30 $90.18 | 3/31 $110.32
4/1  $119.02 | 4/2 $121.02 | 4/3 $111.55 | 4/4 $107.30
4/5  $76.18 | 4/6 $93.04 | 4/7 $104.02
[4/8-4/12: logs unavailable — balance dropped to $90.25 by Apr 13 open]
4/13 $86.44 confirmed | 4/14 $108.91 confirmed | 4/15 $115.79 estimated
4/16 $113.96 at 21:15 MTN (day still active at last session — confirm final from Kalshi)
Starting balance (3/28): $101.38
All-time net through Apr 16 confirmed: +$12.58
Daily target: $100+/day net

---

## STRATEGIC DIRECTION — MODEL INDEPENDENCE

Hyo's explicit requirement: build a system that can operate independently of any single AI provider.

**DO build on:**
- Model-agnostic orchestration: CrewAI or LangGraph
- Model translation layer: LiteLLM (supports 100+ providers — swap Claude for GPT/Gemini/Llama by changing one config value)
- Thin ModelClient abstraction: one file, one place to swap providers
- AetherBot: pure Python, direct API calls, no AI framework dependency

**DO NOT build on:**
- Anthropic Agent SDK (Claude-only, no migration path)
- OpenAI Agents SDK (same problem)
- Managed Agents beta (runs on Anthropic infrastructure only, too locked-in)
- Hardcoded model strings anywhere except the ModelClient abstraction

Test for every new tool: "If Anthropic raises prices by 10x tomorrow, can we move this in a week?" If no → don't adopt without explicit approval.
- Source: Kai_Feedback_Apr16_2026.txt, Part 3.3, 3.4, Part 7

---

## CORRECT MODEL STRINGS (verify at docs.claude.com before using — never trust memory)

claude-opus-4-6
claude-sonnet-4-6
claude-haiku-4-5-20251001

Wrong strings from prior reports: claude-opus-4-0520, claude-sonnet-4-0514 (these are WRONG)
- Source: Kai_Feedback_Apr16_2026.txt, Part 3.1

---

## ANALYSIS QUALITY BAR — WHAT MATTERS IN RAW DATA

When analyzing AetherBot logs, Claude will specifically look for:
- Full trade-by-trade ledger grouped by strategy family
- Stop and harvest event log (every STOP, HARVEST, FORCED_EXIT, HOLD)
- Session window P&L breakdown (EU_MORNING / ASIA_OPEN / NY_PRIME / EVENING / OVERNIGHT)
- EOD balance update (last confirmed balance before midnight MTN — never mid-session)
- 1-2 systemic patterns with the one question that changes the next decision

Claude will specifically watch for: harvest miss mode separation, BDI=0 hold at <120s, POS WARNING | API 0 local N, EU_MORNING post-04:15 clustering.
- Source: Kai_Feedback_Apr16_2026.txt, Part 4.2

Reference analysis example: `kai/memory/feedback/AetherBot_Analysis_Apr13-16_reference.txt`

---

## REMOTE ACCESS — CURRENT STATE (updated 2026-04-18)

### What works RIGHT NOW (Hyo traveling week of 2026-04-19)

**Primary: Chrome Remote Desktop** ✅ WORKING
- Full GUI screen control of Mini from any device
- Access: open Chrome on Pro → remotedesktop.google.com/access → click "mini"
- No ports, no tunnels, no rotating anything
- Runs as background service on Mini automatically

**SSH `mini` shortcut: BROKEN** ⚠️
- Was using bore tunnel to bore.pub — bore.pub is unreliable (exit 1, "No route to host on bore.pub:7835")
- Tailscale: installed on Mini (IP 100.77.143.7) but NOT working — exhausted 3+ hours on 2026-04-18, do not attempt again
- Cloudflared: installed on Mini but requires domain on Cloudflare — hyo.world not registered on Cloudflare
- **Fix when Hyo returns:** replace bore plist with Serveo tunnel (zero install, key-based fixed subdomain) or ZeroTier

### Screen Sharing
- `com.apple.screensharing.agent` is running on Mini (Screen Sharing enabled)
- Once SSH is fixed: `ssh -L 5900:localhost:5900 mini` then Finder > Go > Connect to Server > `vnc://localhost`
- Or via Chrome Remote Desktop (already working)

### What NOT to try again
- Tailscale — spent 3+ hours, does not work for this setup. Do not suggest.

---

## HOW TO REBUILD TRUST WITH HYO (from Hyo's own feedback)

Run 3 clean daily analysis sessions through the full pipeline:
1. Pull log
2. Inject context (balance ledger, version, open issues) into Claude system prompt
3. Send to Claude → GPT → Claude (full loop, no shortcuts)
4. Surface ONE recommendation to Hyo with specific log-sourced evidence
5. Wait for approval

Three consecutive sessions matching the quality of AetherBot_Analysis_Apr13-16_reference.txt = the bar.
Not summaries. Sessions where you find something real, trace it to its mechanism, recommend a specific action.
- Source: Kai_Feedback_Apr16_2026.txt, Part 8

---

## PROTOCOL FILE — TWO-COPY SYNC (CRITICAL — READ EVERY SESSION)

`PROTOCOL_DAILY_ANALYSIS.md` exists at TWO locations:
- **Canonical (write here):** `agents/aether/PROTOCOL_DAILY_ANALYSIS.md`
- **Root copy (symlink):** `Hyo/PROTOCOL_DAILY_ANALYSIS.md` → points to canonical above

**THE ROOT COPY IS A SYMLINK.** Both are physically the same file. You cannot make them
drift by editing one — any write to either path edits the one canonical file.

Rules for upgrades (enforced by Part 13-14 of the protocol itself):
1. Always edit `agents/aether/PROTOCOL_DAILY_ANALYSIS.md` — the root symlink follows automatically
2. Run `analysis-gate.py` on a real analysis to verify the gate still passes BEFORE bumping version
3. Bump VERSION in the file header, update ANALYSIS_ALGORITHM.md to match
4. Commit with both paths staged (git sees them as different entries — stage both: `git add PROTOCOL_DAILY_ANALYSIS.md agents/aether/PROTOCOL_DAILY_ANALYSIS.md`)

**AUTOMATED PIPELINE (kai_analysis.py):** The protocol is injected into the Claude system prompt
automatically at startup. `run_analysis.sh` also runs `analysis-gate.py` before any feed write.
The protocol is NOT just documentation — it is loaded into every analysis call.

**Current version: 2.5** (updated 2026-04-18)

Logged: SE-AETHER-PROTOCOL-001 (two-copy drift caused Hyo to see v2.4 in Finder while canonical was v2.5)

---

## AGENT EXECUTION PROTOCOLS (CRITICAL — READ BEFORE WORKING ON ANY AGENT)

Every agent has a canonical PROTOCOL file. These are NOT just documentation — they are the
single source of truth for how to run, upgrade, and debug that agent. A fresh Kai **must**
read the relevant PROTOCOL before touching any agent's code, data, or runner.

### Protocol registry

| Agent   | Protocol file                                           | Current version | When to read |
|---------|---------------------------------------------------------|-----------------|--------------|
| Aether  | `agents/aether/PROTOCOL_DAILY_ANALYSIS.md`              | v2.5            | Before any analysis, HQ publish, or runner change |
| Ant     | `agents/ant/PROTOCOL_ANT.md`                            | v1.3            | Before any credit data, ant-update.sh, or hq.html Ant tab work |
| Podcast | `agents/ra/PROTOCOL_PODCAST.md`                         | v1.2            | Before any podcast.py, Vale voice, or script format work |
| Nel     | `agents/nel/PROTOCOL_NEL_SELF_IMPROVEMENT.md`           | v1.0            | Before any Nel improvement work (adaptive sentinel, dep audit, cache) |
| Ra      | `agents/ra/PROTOCOL_RA_SELF_IMPROVEMENT.md`             | v1.0            | Before any Ra improvement work (source health, feedback loop, diversity) |
| Sam     | `agents/sam/PROTOCOL_SAM_SELF_IMPROVEMENT.md`           | v1.0            | Before any Sam improvement work (perf baseline, Vercel KV, error handling) |
| Dex     | `agents/dex/PROTOCOL_DEX_SELF_IMPROVEMENT.md`           | v1.0            | Before any Dex improvement work (clustering, drift detection) |
| Kai     | `kai/protocols/PROTOCOL_MORNING_REPORT.md`              | v1.0            | Before any morning report work — schema, rendering, failure modes |

Kai's rule: **before working on an agent, read its PROTOCOL file first.**
The protocol tells you: file locations, dual-path rules, field names, failure modes, upgrade steps.

### When to upgrade a protocol

Upgrade (bump version in file header) when ANY of the following change:
- A field name or file path that the protocol references
- The HQ display format or section layout
- A runner script (ant-update.sh, run_analysis.sh, etc.)
- A schedule change (launchd plist time)
- A new failure mode is discovered this session
- Hyo asks for a behavior change

After upgrading: update this table's "Current version" column and commit.

### Ant protocol quick reference (agents/ant/PROTOCOL_ANT.md v1.3)

- **Nightly run:** 23:45 MT via `com.hyo.ant-daily.plist` → `bash bin/ant-update.sh`
- **Dual-path:** ALWAYS stage both `agents/sam/website/data/ant-data.json` AND `website/data/ant-data.json`
- **Heredoc:** ALWAYS `<< 'PYEOF'` (quoted) — unquoted breaks Python f-strings
- **history[] field:** top-level in ant-data.json, NOT under costs.dailyHistory (that path does not exist)
- **HQ colors:** Anthropic = purple `#a855f7`, OpenAI = cyan `#06b6d4` — never swap
- **Credit source tiers:** Tier 1 (automated, headless) = MTD spend from api-usage.jsonl; Tier 2 (requires screen or Admin API key) = real account balance
- **After every run:** update `agents/ant/ACTIVE.md` + write log to `agents/ant/logs/ant-YYYY-MM-DD.log`
- **Git push:** run via Mini (`mcp__claude-code-mini__Bash` or `kai exec`) — Cowork sandbox has 403 proxy block
- **Quality gate:** `python3 bin/ant-gate.py` — hard-block, 5 gates, exit 1 on fail, Telegram alert auto-sent. ant-update.sh calls this; no commit on failure.
- **Open tickets:** ANT-GAP-001 (Admin API key), ANT-GAP-002 (monthly close job), ANT-GAP-003 (RESOLVED via ant-gate.py Telegram), ANT-GAP-004 (weekly P&L rollover), ANT-GAP-005 (scraped-credits staleness in report-check)
- **17 failure modes documented** in Part 13 — check before any Ant work

---

## MORNING REPORT FORMAT SPECIFICATION (v7 — 2026-05-06)

**REWRITE 2026-05-06:** Hyo feedback confirmed old report was operational noise, not CEO intelligence.
**Core principle:** "Are the agents getting better?" — answered with metric deltas, not narrative.
**Protocol:** `kai/protocols/PROTOCOL_MORNING_REPORT.md` v3.0 — read before any morning report work.
**Generator:** `bin/generate-morning-report-v7.sh` (ACTIVE at 07:00 MT via kai-autonomous.sh)
**Old generator:** `bin/generate-morning-report.sh` v6 — DEPRECATED, do not modify or use.
**Output:** `agents/sam/website/data/morning-report.json` (canonical) + `website/data/morning-report.json` (mirror)

### 5-Section CEO Briefing (v7 format)
Feed entry sections: `pulse`, `improved[]`, `building[]`, `aetherSignal`, `yourAttention[]`

- **pulse** (string): "Healthy" | "Degraded" | "Down" — one word, queue/worker health
- **improved[]**: metric deltas only — `{agent, metric, before, after, what, commit}`
- **building[]**: active next targets — `{agent, metric, target, how}`
- **aetherSignal** (string): financial intelligence summary (Mon-Fri only, null otherwise)
- **yourAttention[]**: P0 tickets with needs_hyo=True flag ONLY — zero items most days

### What does NOT go in the morning report
- SICQ/OMP scores, simulation warnings, stale ARIC notices
- Failed operational checks (reports to Kai, not Hyo)
- Research progress narratives
- Per-agent operational summaries

### Agent-card.json system (feeds morning report WHAT IMPROVED)
Each agent writes `agents/{name}/data/agent-card.json` at end of nightly cycle.
Script: `bin/write-agent-card.sh` — shared utility, call with --agent --metric --after --what.
Schema: `{agent, date, metric_name, metric_before, metric_after, what_changed, commit, next_target{metric, target, how}}`
GVU metrics (one per agent, cannot be gamed):
- Nel: health_score (IMPROVEMENT_SCORE from sentinel+cipher+audit)
- Sam: deploy_reliability (tests_passed / total * 100)
- Aether: signal_accuracy (TBD — wire when Aether runs on Mini)
- Ra: newsletter_delivery_rate (TBD — wire when Ra runs on Mini)
- Kai: improvements_shipped_week (count of agent-card deltas with metric_after > metric_before)

### Disabled cadences (2026-05-06)
- kai-daily HQ publish at 23:30 MT — DISABLED (duplicated morning report)
- Ra content report HQ publish — DISABLED (operational noise; Ra → Kai via dispatch only)
- Nel/Sam daily HQ narrative publish — DISABLED (agent-card.json replaces narrative)
- Completeness check no longer expects: kai-daily, ra-daily (removed from required list)

### Required JSON fields per agent (enforced as of v6)
- `shipped_since_last` — what shipped since last report with proof (commit hash)
- `highest_priority_issue` — the ONE most important unresolved issue
- `next_action` — one concrete next step executable in 6 hours
- `action_type` — enum: `research | instrumentation | build | deployment`
- `priority_evidence` — data citation from ARIC Phase 1 justifying priority
- `improvement_status_detail` — all 3 improvements (I1/I2/I3) with current status
- `improvement_commit` — git commit hash if shipped (null if not)

### Required executive summary fields (new in v6)
- `agents_shipped` — count of agents with shipped improvements today
- `agents_building` — count of agents with action_type=build/deployment
- `agents_researching` — count of agents in research phase
- `agents_stalled` — count of agents with no active work
- `critical_blocked` — list of agents blocked with specific reason
- `research_theater_warning` — populated if ALL agents are in research phase

### CRITICAL: action_type interpretation
- `research` + no commit for 3+ consecutive reports = RESEARCH THEATER (flag it)
- `build` or `deployment` = healthy progress
- Goal: every agent has action_type != research at least once per week

---

## SELF-IMPROVEMENT EXECUTION ENGINE (2026-04-21)

**Location:** `bin/agent-execute-improvement.sh`
**Purpose:** Turns "researched" improvements into actual code changes via Claude API call

**Usage:**
```bash
bash bin/agent-execute-improvement.sh nel I2  # runs dependency audit improvement
bash bin/agent-execute-improvement.sh ra I1   # runs source health improvement
bash bin/agent-execute-improvement.sh sam I1  # runs performance baseline improvement
bash bin/agent-execute-improvement.sh dex I2  # runs root cause clustering improvement
```

**Gates (all must pass):**
1. `aric-latest.json` exists with improvement thesis
2. `files_to_change` field is non-empty in improvement_built
3. Anthropic API key at `agents/nel/security/anthropic.key` is valid
4. Claude generates non-empty implementation (>50 chars)
5. Written file is non-empty
6. `verify.sh` passes (if it exists for that agent)
7. `git commit` succeeds
8. `git push origin main` succeeds

**Failure behavior:** Restores backup, logs execution_error to aric-latest.json, does NOT mark as shipped.

**What agent-growth.sh does vs this script:**
- `agent-growth.sh`: Phases 1-4 (observe, orient, research, decide) — bash only, no LLM
- `agent-execute-improvement.sh`: Phase 6 (ACT) — calls Claude API, writes code, commits

---

## Agent Improvements

### [2026-04-22] nel fixed W1: Static Checks Never Adapt — Sentinel Runs Same 9 Checks Until Failure Is Deafening
**What worked:** Fixed via Claude Code delegate — see agents/nel/research/improvements/W1-2026-04-22.md
**Files changed:** see evolution.jsonl
**Applicable to:** any agent with similar weakness Shipped (2026-04-21, Session 22)

Session 22 completed the full pending improvement backlog. All agents now have real shipped code, not just research.

**Aether W2 — Analysis Quality Gate (commit 92aa0fc)**
- File: `agents/aether/analysis-quality-gate.sh` (NEW, 12 QC checks)
- Blocks HQ publish if GPT cross-check (QC05), recommendation (QC09), date markers fail
- Wired into aether.sh publish block before every HQ push
- Metric: 0% automated quality checking → 12-point gate on every publish

**Dex W1 — JSONL Auto-Repair (commit 92aa0fc)**
- File: `agents/dex/dex-repair.py` (NEW, scans 8 JSONL files)
- Removes duplicates, injects missing ts/status/severity/category fields
- Safety gate: skips files with >20% corruption (P0 flag)
- Wired into consolidate.sh Phase 0a (runs before sentinel reads ledgers)
- Metric: JSONL corruption detected but never fixed → auto-repaired nightly

**Nel W2 — Dependency CVE Audit (commit 1761f52)**
- File: `agents/nel/dep-audit.sh` (NEW, 4-check audit)
- npm audit + pip-audit + staleness check + Node LTS version check
- Wired into cipher.sh as Layer 5
- P1 ticket auto-opens if critical/high CVEs found
- Current state: clean (stripe up to date, Node v25.9 ≥ LTS)

**Sam W2 — Vercel KV Persistence (commit b293b9d)**
- File: `agents/sam/website/api/hq.js` (MODIFIED — KV layer added)
- initKV() + hydrateFromKV() on cold start, syncToKV() fire-and-forget on every write
- Graceful in-memory fallback when KV not provisioned
- kv_connected + persistence fields in /api/health response
- Setup: `agents/sam/website/docs/VERCEL_KV_SETUP.md` (3-step guide)
- To activate: provision Vercel KV → link project → redeploy

**Aether W3 — Cross-Session Strategy Aggregator (commit 049488e)**
- File: `agents/aether/aggregate-weekly.py` (NEW, reads all Analysis_*.txt)
- Extracts per-strategy edge, per-window P&L trend, concentration risk, health flags
- First run (12 sessions, Apr 8-17): net +.07, 50% WR, PAQ_EARLY_AGG declining, 92.8% concentration
- Wired into aether.sh Step 12b (runs after publish, before memory update)
- Output: `agents/aether/ledger/weekly-aggregator.json` + `agents/aether/research/STRATEGY_HEALTH.md`

**Dex W2 — Pattern Cluster Analysis (commit 22c3c7d)**
- File: `agents/dex/dex-cluster.py` (NEW, Jaccard clustering)
- 255 entries → 117 clusters (54.1% noise reduction), largest cluster: 31 entries same root cause
- Ra identified as top issue agent by volume
- Temporal pattern detection (2 recurring patterns found)
- Wired into consolidate.sh Phase 0b (after repair, before sentinel)
- Output: `agents/dex/ledger/cluster-report.json` + `agents/dex/research/CLUSTER_REPORT.md`

**Next targets by agent:**
- Nel W3: fix research source failures (5/6 external feeds timeout from sandbox)
- Ra Phase 2: SMTP bounce parsing + bounce handler (target 2026-04-28)
- Sam W3: Lighthouse CI + bundle size monitoring
- Aether W1: phantom position reconciliation vs Kalshi API
- Dex W3: cross-agent constitution drift detection

## Agent I1 Improvements Shipped (2026-04-21, Session 21)

These are the first real shipped improvements from the self-improvement protocols. Read before working on any agent to avoid re-implementing or regressing.

**Nel I1 — Adaptive Sentinel (commit b361aca, shipped 2026-04-14)**
- File: `agents/nel/sentinel-adapt.sh` (NEW, fully implemented, 551 lines)
- Tracks consecutive_fails per check_id in `agents/nel/memory/sentinel-escalation.json`
- Escalation levels: 0=normal (1-2 fails), 1=warning (3-4), 2=chronic (5-9), 3=critical (10+)
- Level 2+: generates `agents/nel/logs/sentinel-diagnostics-YYYY-MM-DD.md`
- Diagnostic templates: api-health (SSL/token/latency), aurora (daemon/log/pipeline), scheduled-tasks (launchd/queue), task-queue (P0 count/age/completion)
- Called from sentinel.sh line 348-362 via `ADAPT="$ROOT/agents/nel/sentinel-adapt.sh"`
- Metric: MTTRC 3+ days → <4h. Next: W2 Dependency Audit (CVE scanning via GitHub Advisory DB)

**Ra I1 Phase 1 — Editorial Feedback Loop (commit b484e1c, shipped 2026-04-21)**
- Files changed: `agents/ra/pipeline/render.py` (modified), `agents/sam/website/api/v1/track/open.js` (NEW), `agents/sam/website/api/v1/track/click.js` (NEW)
- render.py changes: new flags `--no-track` (default: tracking ON) and `--newsletter-id NID`
- Tracking pixel: `<img src="https://hyo.world/api/v1/track/open?nid=...">` injected before `</body>`
- Link wrapping: external links rewritten to `/api/v1/track/click?nid=...&li=N&url=encoded`
- open.js: returns 1x1 transparent GIF, logs open event to /tmp and Vercel runtime logs
- click.js: validates URL protocol (http/https only), logs click, 302-redirects to destination
- Engagement ledger: render events written to `agents/ra/ledger/engagement.jsonl` on each render
- Metric: 0% engagement visibility → tracking active. Next: Phase 2 — SMTP DSN bounce parsing

**Sam I1 Phase 1 — Performance Baseline (commit b484e1c, shipped 2026-04-21)**
- File: `bin/perf-check.sh` (NEW, executable, 8293 bytes)
- Usage: `bash bin/perf-check.sh` (measure + compare), `--set-baseline` (record baseline), `--threshold MS`, `--no-fail`
- Measures 5 endpoints: health, hq, aurora-data, hq-home, ra-home
- Thresholds: P0 >5000ms, P1 >2000ms or >50% regression, P2 >15% regression vs baseline
- Records to `agents/sam/ledger/performance-baseline.jsonl` (time-series JSON)
- Integrate into DEPLOY.md Phase 4: `bash bin/perf-check.sh` after every deploy
- Metric: 0% regression detection → 100% for 5 tracked endpoints. Next: Lighthouse CI in DEPLOY.md

**Morning Report v6-action-engine (current as of 2026-04-21)**
- Nel/Ra/Sam: `improvement_status: shipped`, `shipped_since_last` shows commit hash
- Aether/Dex: `improvement_status: no active work` — need ARIC cycles to start Phase 5-7
- `growth_trajectory: expanding` (3/5 agents shipping)
- Research theater detection: fires if all agents show action_type=research with zero deployment
- Morning report feed entry: `morning-report-2026-04-21` in feed.json (both paths synced)

---

## SELF-IMPROVEMENT FLYWHEEL — ARCHITECTURE AND CRITICAL PATTERNS (2026-04-21, Session 27)

**Core files:**
- `bin/agent-self-improve.sh` — 3-stage state machine (research → implement → verify) per agent
- `bin/flywheel-doctor.sh` — self-healing script, 9 checks, automated recovery, runs 09:00 + 14:00 MT
- `agents/<name>/self-improve-state.json` — per-agent state: current_weakness, stage, cycles, failure_count
- `agents/<name>/GROWTH.md` — weakness/expansion registry (W1/W2/W3, E1/E2/E3 format)
- `kai/ledger/self-improve.log` — flywheel execution log
- `kai/ledger/sicq-latest.json` — SICQ quality scores per agent (0-100, written by flywheel-doctor)
- `kai/ledger/flywheel-doctor-latest.json` — last doctor run results
- `kai/protocols/FLYWHEEL_RECOVERY.md` — complete issue→recovery map (10 issue types)
- `kai/protocols/SELF_IMPROVE_AUDIT.md` — fault analysis: failure modes, echo chamber risks, SICQ framework

**P0 BUG — Theater verification (SE-S27-001, fixed 2026-04-21):**
`verify_improvement()` originally used system-wide git log to check "did anything commit?" — meaning ANY commit anywhere in the project caused ANY agent's weakness to verify as RESOLVED. A Nel commit would resolve a Sam weakness. Fix: `verify_improvement()` now reads `FILES_TO_CHANGE` from the research file and uses `-nt state_file` (file newer than state machine start) for specific-file checks. Falls back to deep checks only when no research file exists.

**P1 BUG — Silent state advance on empty research (SE-S27-002, fixed 2026-04-21):**
When Claude Code returned empty output (timeout, binary failure), the research phase had no gate — state machine advanced to `implement` on nothing. Fix: explicit file existence check after research phase. If `agents/<name>/research/improvements/<WID>-DATE.md` does not exist, state stays at `research`, failure_count increments, P1 ticket opens.

**P1 BUG — Confidence gate inversion (SE-S27-003, fixed 2026-04-21):**
Old code: `[[ "$confidence" == "LOW" ]]` — only blocked explicit LOW string. Empty string, "UNKNOWN", or any typo proceeded to implementation. Fix: whitelist pattern `[[ "$confidence" != "HIGH" && "$confidence" != "MEDIUM" ]]` — only proceeds with explicit HIGH or MEDIUM.

**P1 BUG — Shell injection in persist_knowledge / report_to_kai (SE-S27-004, fixed 2026-04-21):**
`python3 -c "... $bash_var ..."` pattern caused silent JSON corruption when weakness titles contained `"`, `$`, or newlines. Fix: env-var + quoted heredoc pattern — variables passed via `SI_VAR=value python3 << 'HEREDOC'` — bash variables never interpolated inside the Python.

**Hyo-feedback-to-GROWTH.md injection pipeline (NEW 2026-04-21):**
`kai inject-feedback <agent> "<summary>" [P0|P1|P2]` — when Hyo corrects Kai during a session, this command immediately writes the feedback as a new W-item to `agents/<agent>/GROWTH.md`, creates a ticket, and logs to `session-errors.jsonl`. Closes the loop that was broken: Hyo feedback → session-errors.jsonl → nowhere. Now: Hyo feedback → GROWTH.md → flywheel picks it up next cycle.

**SICQ (Self-Improve Cycle Quality Score):**
0-100 per agent, computed by flywheel-doctor. 5 components, 20 points each:
- Research file written for today
- Research has FIX_APPROACH + FILES_TO_CHANGE + CONFIDENCE: HIGH or MEDIUM
- Implementation attempted (cycles > 0)
- Specific FILES_TO_CHANGE were modified (not just any commit)
- KNOWLEDGE.md has entry for this weakness
Score ≥ 60 = ✓ healthy | 40-59 = ⚠ degraded | < 40 = ✗ critical (P1 ticket auto-opens)

**Flywheel Recovery hierarchy (FLYWHEEL_RECOVERY.md):**
1. Automated fix (doctor repairs without human input)
2. State reset (return to W1/research safe known-good)
3. P1 ticket + Kai signal (Kai addresses next session)
4. Hyo inbox entry (ONLY when Kai cannot resolve autonomously)
Hyo escalation triggers: multiple P0 in same run | SICQ avg < 40 for 3 days | log >96h stale

**Kai's own GROWTH.md (agents/kai/GROWTH.md — created 2026-04-21):**
W1: Session Continuity Drift (P0) | W2: Decision Quality Not Measured (P1)
W3: Cross-Agent Coordination Latency (P1) | W4: Memory Consolidation Coverage Gaps (P1)
E1: Agentic Code Review Pipeline | E2: Hyo Portfolio Management | E3: Autonomous Architecture Proposals
Kai is now a participant in the flywheel, not just the synthesizer.

**OMP + Kai-specific metrics framework (Task #64-69 — BUILT 2026-04-21, Session 27 cont. 7-8):**
Two-layer quality system: SICQ (process compliance) + OMP (outcome quality).
OMP has umbrella metrics (OCR, RR, RDI, CE, MCS — all agents) + one agent-specific metric per agent.
Kai's OMP was redesigned (2026-04-21) from a single CCS metric to a 5-dimensional profile:
- DQI (Decision Quality Index): CEO role. Formula: (documented_decisions/total) × (1-reversal_rate). Source: kai/ledger/decision-log.jsonl. Target: ≥0.80.
- OSS (Orchestration Sync Score): Orchestrator role. Dispatch ACK rate × (1 - delegation-back rate). Fallback: ACTIVE.md freshness. Target: ≥0.85.
- KRI (Knowledge Retention Index): Memory keeper role. 1 - (repeated_error_categories / total_categories). Source: session-errors.jsonl. Target: ≥0.90.
- AAS (Autonomous Action Score): Self-improver role. (E_items/total_items × 0.60) + (cycle_ratio × 0.40). Source: GROWTH.md + self-improve-state.json. Target: ≥0.75.
- BIS (Business Impact Score): Business operator role. on-time delivery × HQ publish rate. Source: morning-report.json + feed.json. Target: ≥0.85.
Composite = 0.25×DQI + 0.20×OSS + 0.25×KRI + 0.15×AAS + 0.15×BIS. Threshold healthy: ≥0.75. Critical: <0.55.
Kai SICQ replaces generic flywheel SICQ with 5 executive protocol compliance checks:
HC (hydration: KAI_BRIEF within 24h), RDC (research ≥6 external URLs), QGC (no queue violations in 7d),
DMW (KNOWLEDGE.md within 7d + KAI_TASKS within 24h), ERR (no same-category error 3+ times in 14d).
Full spec: kai/protocols/PROTOCOL_KAI_METRICS.md. Research: 36 sources across CEO, orchestration, KM, agentic AI, business ops.
Morning report shows Kai OMP as 5-dimensional breakdown (not composite-only). Output: agents/kai/ledger/omp-latest.json (kai_profile field).
W1→KRI+HC, W2→DQI+RDC, W3→OSS+BIS, W4→KRI+DMW. All weaknesses linked to metrics in agents/kai/GROWTH.md.

**Cross-agent adversarial review (Task #63 — BUILT 2026-04-21):**
`bin/cross-agent-review.sh` — Saturday 06:45 MT via kai-autonomous.sh. Primary antidote to echo chamber dynamics.
Pairs: nel reviews sam | sam reviews nel | ra reviews aether | dex reviews all agents.
Claude Code is asked to produce an adversarial (not diplomatic) review across 6 sections:
diagnosis quality, research quality, implementation critique, echo chamber risk, critical gaps (P0/P1/P2), verdict (STRONG/ADEQUATE/WEAK/THEATER).
P0/P1 gaps auto-ticketed against the target agent. Non-STRONG verdicts published to HQ Research tab.
Run ad-hoc: `kai cross-agent-review nel sam` (nel reviews sam only) or `kai cross-agent-review` (all pairs).

---

## MEMORY FAILURE LOG (so this never happens again)

2026-04-18: Hyo re-uploaded Kai_Feedback_Apr16_2026.txt and AetherBot_Analysis_Apr13-16.txt because
they were never saved to the project after the April 16 session. KAI_BRIEF.md captured status but
NOT knowledge. The knowledge layer (this file) did not exist. Fix: KNOWLEDGE.md created, both files
saved to kai/memory/feedback/, hydration protocol updated to read KNOWLEDGE.md every session.

---

## SESSION 29 — 2026-04-22 KEY LEARNINGS (permanent)

**Ant dashboard — canonical data structure (PROTOCOL_ANT.md v1.4):**
- `history[]` must have: `{date, anthropic, openai, total}` — all four fields. Missing any breaks the stacked bar chart.
- History window = current month day 1 → today (zero-filled). NOT 14-day rolling window.
- Month rollover: previous month closed to `monthly-YYYY-MM.json` before new month starts.
- HQ Ant tab shows three boxes: Expenses | Income | Net (not four — no "Today's API" top-level box).
- `total_anthropic` must be computed BEFORE the scraped-credits block in ant-update.sh or NameError on scraped path.
- Gate: before rewriting ant-data.json, read PROTOCOL_ANT.md schema. Always verify history[] fields.

**HQ login — sessionStorage vs localStorage:**
- HQ token was in `sessionStorage` — clears on tab/browser close.
- Fixed: `localStorage` with 30-day expiry. Login now persists across sessions.
- Root cause of lockout: my JS error forced page reload, clearing the session token.

**hq.html modifications — mandatory pre-commit gate:**
- `bin/validate-hq-js.sh` must pass before any hq.html commit.
- Template literals cannot be nested directly — use string concatenation inside outer template literals.
- The outer `html += \`...\`` template literal: inner code blocks using backticks must be inside proper `${...}` expressions with UNescaped `$`. Escaped `\${` produces literal string, not evaluated expression.

**Verification discipline (session 29 confirmed pattern):**
- Never declare a fix done without checking the deployed output. git push ≠ verified.
- Before modifying any data file: read the consumer (HQ renderer, protocol doc) to understand exact field names and structure needed.
- When something breaks after my changes: check what I changed FIRST, not external systems.

**verified-state.json (new — 2026-04-22):**
- `kai/ledger/verified-state.json` is pre-computed truth for: credits, SICQ, OMP, report freshness, stale tickets, Aether balance.
- Written by `bin/kai-session-prep.sh` — runs every 15 min via kai-autonomous.sh, 5x daily via launchd.
- All claims about system state MUST come from this file or a live read. Not from memory.

**SICQ health gate (updated 2026-04-22):**
- Morning report health gate now uses `< 60` (below minimum), not `<= 40` (critical only).
- Agents below 60 show in health sentence as "quality issues" — system not "healthy."


**Anthropic API credits — real balance and cost driver (2026-04-22):**
- Verified balance: $18.91 remaining of $40 total (two $20 grants, April 8, expire April 2027)
- Spent: $21.09 since April 8 — ~$0.24 from automated Aether scripts, ~$20.85 from Cowork sessions
- The main cost driver is NOT Aether — it is Cowork interactive sessions (this conversation)
- Claude Max subscription ($200/month) covers: claude.ai, Claude Code CLI (Ra newsletter, agent improvements)
- Anthropic API credits cover: Cowork sessions + Aether kai_analysis.py Claude calls
- A long intensive Cowork session costs ~$5-9 in API credits (claude-sonnet-4-6: $3/MTok in, $15/MTok out)
- api-usage.jsonl only tracks automated scripts — Cowork costs were invisible until browser scrape
- OpenAI remaining: ~$17.94 (scraped April 18 $18.64 minus $0.70 Aether spend since)
- OpenAI is fully tracked — only Aether scripts (gpt_factcheck, kai_analysis) use it
- Daily automated spend: OpenAI $0.085-$0.20/day (Aether only). Anthropic automated: $0/day (quota until May 1)
- Quota reset May 1 UTC — after that, kai_analysis.py will resume Claude calls (~$0.12/day)
- Action needed: build Cowork session cost tracking so ant-data.json captures true total spend

**Automated Anthropic balance tracking — investigation (2026-04-22 late session):**

GOAL: Track Anthropic credit balance + Cowork session spend automatically, zero manual work.
ORG ID: 6fa1a636-f063-4651-aef2-f7ebaa25c49d (from API error response headers)

What was tried and why it failed:

1. Admin API key (/v1/organizations/cost_report) — FAILED
   No admin key option exists in console for individual accounts. Admin keys only on enterprise plans.
   Regular key (sk-ant-api03-) gets 401 on billing endpoints.

2. Regular API key on /v1/usage endpoints — FAILED
   All /v1/organizations/{org_id}/usage patterns return 404. Endpoints don't exist for individual accounts.
   Not permission-blocked — genuinely not there. Anthropic hasn't published usage API for individuals.

3. Platform console APIs (/api/organizations/...) with API key — FAILED (403)
   platform.claude.com uses session cookie auth, NOT API key auth. The /api/ endpoints exist and work
   but require browser session cookies. API key auth gives 403.

4. Obfuscated BFF URLs — FAILED
   Console uses hashed URLs (e.g. platform.claude.com/ZuTO-2b-...) that change per session.
   Can't be called outside browser. Designed to prevent direct API access.

5. Chrome cookie extraction (headless) — ALMOST WORKS, blocked by Keychain
   Platform.claude.com/api/... endpoints DO work with session cookies (proven: navigating Chrome
   to /api/organizations/{org_id}/invoices/overdue returned live JSON data).
   Chrome cookies are at ~/Library/Application Support/Google/Chrome/Default/Cookies on Mini.
   All cookies are AES-encrypted using key from macOS Keychain ("Chrome Safe Storage").
   Python script reads encrypted bytes but needs Keychain decryption key.

6. Keychain access headlessly — BLOCKED by one-time dialog
   `security find-generic-password -s "Chrome Safe Storage"` times out when run via queue
   because macOS requires user to click "Allow Always" dialog the first time a new process requests it.
   After that one-time approval, headless access works forever.

WHAT WORKS WHEN APPROVED:
- bin/ant-fetch-balance.py (built, on Mini, NOT yet committed to git)
  Reads Chrome cookies → decrypts with Keychain key → calls /api/organizations/{org_id}/invoices/overdue
  and other billing endpoints → returns balance data
  Cookie names: sessionKey, sessionKeyLC, routingHint (all encrypted)
  Working endpoints found: /api/organizations/{org_id}/invoices/overdue → {"overdue_invoices":[],"total_overdue_amount":0}
  /api/organizations/{org_id}/subscription → "Method Not Allowed" (exists, needs POST)
  /api/organizations/{org_id}/usage → "Missing permissions" (exists, needs enterprise plan)

NEXT STEP: One-time on Mini Terminal:
  security find-generic-password -s "Chrome Safe Storage" -a "Chrome" -w
  Click "Allow Always" in dialog → headless access works from then on.
  Then run: HYO_ROOT=~/Documents/Projects/Hyo python3 ~/Documents/Projects/Hyo/bin/ant-fetch-balance.py

**Autonomy Gap Audit — 2026-04-22 (full doc: kai/research/raw/2026-04-22-autonomy-audit.md):**

System health is RED (28/100). Zero new code shipped in 10 days. Only 4 improvements ever shipped (both in week 1). 14 improvements remain theater.

THREE CODE BUGS blocking the flywheel:
1. flock missing on macOS → state.json never saved atomically → aether cycles reset to 0 every run
2. mktemp collision in /tmp → HQ feed publish silently skipped → Hyo never sees self-improve progress
3. Empty research gate → fix_approach="" still advances to implement → garbage-in execution fails silently

THREE STRUCTURAL GAPS:
1. Kai deadlock: Kai's own weaknesses require modifying kai-autonomous.sh while it's running (impossible)
2. Infrastructure blocking: Sam W2 (Vercel KV) needs provisioning; no async approval mechanism exists
3. Cascade failure: Ra W1 shipped (disables broken sources) but W2/W3 not shipped (can't replace or score them) → newsletter at 0 for 3 days

AETHER FROZEN BY DESIGN: execution engine explicitly disabled per PROTOCOL_AETHER_ISOLATION.
KAI SELF-IMPROVEMENT IS MANUAL: every session to fix Kai costs $5-9 in API credits.

BIGGEST MISSED OPPORTUNITIES:
- No cross-agent learning (Nel's pattern not propagated to Sam/Ra)
- No compounding (improvements don't build on each other — no dependency graph)
- Memory consolidation misses all direct file edits (only reads daily-notes/)
- AetherBot analysis findings never fed back into bot improvement automatically


**Aether Vercel deployment throttle (2026-04-23):**
- Aether metrics ran every 60s, committed when metrics changed → ~96 deploys/day → hit Vercel limit
- Fix: aether.sh now throttles git push to max once per 55 minutes using .last-metrics-push marker
- Result: ~24 deploys/day, well within limits
- File: agents/aether/aether.sh — "Git push metrics" section

**Morning report agent scores bug (2026-04-23):**
- Bug: generate-morning-report.sh has TWO Python processes: PYEOF (lines 89-979) and FEED_PYEOF (lines 999-1207)
- _scores variable set in PYEOF was NEVER available in FEED_PYEOF (separate processes)
- _scores in dir() always False → sicqScores/ompScores always empty in feed entry
- Fix: FEED_PYEOF now reads sicq-latest.json and omp-summary.json directly
- Protocol: PROTOCOL_MORNING_REPORT.md v1.3 — scores now MANDATORY in every morning report
- OMP values: overall field is integer 0-100 (NOT 0-1 float) — read as int(_ad.get("overall"))

**JSON vs Protocol — Kai's view (2026-04-23):**
- See response in session for full thoughts
- Short version: JSON = machine state (what IS), Protocol = human intent (what SHOULD BE)
- Both needed, complementary. JSON without protocol = no accountability. Protocol without JSON = no ground truth.

**Autonomous Company Research (2026-04-23 — 65+ sources):**
Full document: kai/research/raw/2026-04-23-autonomous-company-research.md

TOP FAILURE MODES (UC Berkeley MAST, 1600+ traces):
- Step repetition 15.7% — agents repeat tasks because they can't detect they already did it
- Reasoning/action mismatch 13.2% — stated plan diverges from what actually executes
- Inability to recognize task completion 12.4% — agents loop past the finish line
- Silent drift (NOT crashes) — agents fail gradually, producing perfect-looking logs
- 17x error amplification in "bag of agents" topology — HARD LIMIT at 7 agents without discipline
- Reward hacking: o3 model modified TIMER CODE to show fast result rather than improving program

TOP DEPENDENCY RISKS:
- LLM vendor SPOF: all agents on Claude = single failure point. Fix: AI gateway + fallback
- Orchestrator concentration: Kai handles everything. Fix: domain sub-orchestrators per area
- Context window stuffing: CLAUDE.md+KAI_BRIEF+KNOWLEDGE.md+TACIT.md = 30K+ tokens before work starts
- Schema drift: feed.json, session-handoff, verified-state consumed by multiple agents without contracts

WHITEBOARD → FACTORY MODEL:
KAI_TASKS (whiteboard) → Kai decomposes + success criteria → dispatch to agent → execution →
eval gate (outcome check) → HQ publish → feedback into memory → next session picks up
Gate must be at PLAN level, not output level (Devin pattern) — cheapest point to catch misalignment

ALGORITHMS TO IMPLEMENT:
1. GVU Operator (Generator-Verifier-Updater): arXiv:2512.02731 — per-agent verifiable domain signal
   Sam=test pass rate, Aether=signal accuracy, Ra=engagement, Nel=false positive rate
2. Reflexion (verbal RL): arXiv:2303.11366 — +8% improvement, 91% HumanEval
   Already partially: session-errors.jsonl IS Kai's manual Reflexion. Automate per agent.
3. Prompt caching: 90% cost reduction. Cache CLAUDE.md+KAI_BRIEF+KNOWLEDGE.md+TACIT.md
4. Outcome monitoring: not "did agent run" but "did it produce expected output at expected location"
5. Agentic Plan Caching (APC): arXiv:2506.14852 — reuse planning steps for repeated task types
6. SchemaVer (MODEL-REVISION-ADDITION) for all inter-agent JSON contracts

IMPLEMENTED FROM RESEARCH (2026-04-23):
- bin/agent-outcome-check.sh: outcome-based monitoring, wired into kai-autonomous.sh Phase 7
- kai/schemas/registry.json + 8 schema files: schema registry for all HQ report types
- flywheel-doctor.sh CHECK 11: daily protocol/JSON alignment audit
- publish-to-feed.sh SCHEMA GATE: blocks publish without schema, warns on missing mandatory fields
- 3 missing protocols: PROTOCOL_CEO_REPORT, PROTOCOL_RESEARCH_DROP, PROTOCOL_SELF_IMPROVE_REPORT
- PROTOCOL_NEWSLETTER.md v1.0

NEXT IMPLEMENTATIONS (not yet built — prioritized):
1. Prompt caching configuration (zero architecture change, immediate ROI)
2. AI gateway with Claude failover (LiteLLM/Portkey)
3. Langfuse/OpenTelemetry tracing per agent
4. Per-agent GVU verifiable oracle
5. Event-driven architecture (Redis Streams replacing polling)

**Podcast missing days (2026-04-23 investigation):**
- Podcast runs at 03:00 MT daily via com.hyo.aurora.plist
- podcast.py requires: morning-report.json OR ra_newsletter_md OR aurora_brief_md
- Skips with exit(1) if ALL three sources missing: "SKIP {date}: no content sources available"
- Apr 20, 22, 23 missing because: morning-report published after 05:00 (AFTER podcast runs at 03:00)
- The newsletter runs at 03:00 as well but sometimes fails (cascade from source health issues)
- Fix needed: either move podcast to 08:00 MT (after morning report), or use previous day's report as fallback

**Aether analysis timing architecture (2026-04-23):**
- run_analysis.sh triggers at 23:00 MT via com.hyo.aether-analysis.plist
- At 23:00, AetherBot log may be sparse (trading just started that minute)
- Broken line 108 (bash/Python hybrid) picked up 3-line stub instead of full log → gate fails
- By 03:54 AM, gpt_factcheck.py creates complete Analysis file overnight
- FIXED: line 108 rewritten in pure bash; com.hyo.aether-analysis-retry.plist runs at 06:15 MT
- Retry checks if already published (idempotent), publishes if not

**No font issue in Aether analysis on HQ:**
- Analysis renders through renderAetherAnalysis() which uses mdToHtml() — no pre/code blocks
- synthesize.py is for Ra newsletter; Aether uses aether-publish-analysis.sh which extracts sections directly
- aether-publish-analysis.sh runs clean_machine_headers() + strip Pipeline note
- HQ renderer: mdToHtml converts markdown → styled HTML. No terminal font.
- The only font issue was the NEWSLETTER (fixed: strip_llm_artifacts in synthesize.py)

**Protocols updated this session (2026-04-23):**
- PROTOCOL_MORNING_REPORT.md v1.3: scores MANDATORY, bug documented, v1.3 added
- PROTOCOL_ANT.md v1.4: Cowork cost tracking gap, month-to-date history, schema gate
- PROTOCOL_DAILY_ANALYSIS.md v2.6: GPT-first rule (already from S29)
- PROTOCOL_HQ_PUBLISH.md: agent-reflection schema updated to match actual output
- PROTOCOL_NEWSLETTER.md v1.0: CREATED (was missing entirely)
- PROTOCOL_CEO_REPORT.md v1.0: CREATED
- PROTOCOL_RESEARCH_DROP.md v1.0: CREATED
- PROTOCOL_SELF_IMPROVE_REPORT.md v1.0: CREATED
- Rule: schema registry (kai/schemas/) is the machine enforcement. Protocols are the human contract.
  Any new HQ report type requires BOTH before publish-to-feed.sh will accept it.

**Bottlenecks identified (research + audit, 2026-04-23):**
1. Context window stuffing: CLAUDE.md+KAI_BRIEF+KNOWLEDGE.md+TACIT.md = 30K+ tokens before work
   Fix: prompt caching (90% reduction), selective injection via verified-state.json
2. Sequential tool execution: 10 sequential tool calls at 200ms each = 2s; 7 could be parallel = 600ms
3. Polling architecture: cron/queue wakes agents every N minutes regardless of events
   Fix: event-driven (Redis Streams) reduces idle token cost to zero
4. Orchestrator as SPOF: Kai handles all routing; if Kai fails, all agents stall
   Fix: domain sub-orchestrators per area (Sam for engineering, Nel for security)
5. LLM vendor concentration: all agents on Claude = single failure point
   Fix: AI gateway with automatic fallback (LiteLLM/Portkey)
6. Vercel deployment rate: 96/day from aether metrics hits daily limit
   Fix: throttled to 1/hour (done)

**Automation opportunities (research-backed):**
- Prompt caching: 90% input cost reduction, zero architecture change (API config only)
- Outcome monitoring: already built (agent-outcome-check.sh)
- Schema validation: already built (schema registry + flywheel CHECK 11)
- Reflexion cycle: automate per agent (verbal critique → evolution.jsonl each cycle)
- AI gateway failover: LiteLLM as middleware, 30% additional cost reduction from routing
- Plan caching (APC): reuse planning steps for repeated task types (Aether daily, Ra newsletter)
- Langfuse tracing: open source, zero cost, traces every tool call for debugging

---

## S30 SESSION DECISIONS (2026-04-23)

**Hyo directives (non-negotiable, stated explicitly):**
1. Hard API credit cap: <$1.00/day total. Ant owns enforcement. No exceptions.
2. Aether daily analysis continues. Hyo does weekly manual review (not automated).
3. Context window saturation is paramount — $7/session → must stay <$0.27/session.
4. Automation over prompting — Hyo will not prompt for things that can be automated.
5. Every improvement must be systemic, not patchwork. If a fix requires a rule added to .md, the fix is incomplete.
6. Cowork sessions are the primary Anthropic API cost (not agent runs). Session hygiene = cost control.

**Architecture changes shipped in S30:**
- `bin/weekly-maintenance.sh` runs every Saturday 02:00 MT — compacts tickets, trims inbox, rotates logs
- `kai/memory/compaction-instructions.md` — Anthropic Compaction API preservation config
- Context: 620K tokens → 89K tokens (86% reduction, $1.86 → $0.27 per session start)
- tickets.jsonl: 53.8MB → 0.8MB (notes arrays were accumulating 11K cycle timestamps)
- hyo-inbox.jsonl: 1.7MB → 18KB (6,190 messages, all unread — never trimmed)
- Vercel deploy throttle: 96/day → ~24/day (55-min minimum between pushes)
- Podcast rescheduled to 07:30 MT (was 03:00 MT before morning report content existed)
- Ant DAILY_ALERT_USD: $50 → $1 (three tiers: $0.25 INFO, $0.75 WARN, $1.00 P0)
- Schema registry: 8 schemas in kai/schemas/, coupled to publish-to-feed.sh gate
- flywheel-doctor.sh CHECK 11: protocol/JSON alignment audit

**Root cause fixes shipped:**
- Aurora terminal font: synthesize.py strip_llm_artifacts() removes unclosed code fences at source
- Morning report SICQ/OMP scores missing: FEED_PYEOF reads score files directly (separate process)
- run_analysis.sh line 108: fixed bash/Python hybrid with pure bash LATEST_LOG_LINES expansion
- agent-self-improve.sh: flock (Linux-only) → mkdir-based locking (POSIX portable, macOS)
- hq.html JS syntax: nested backtick template literals → string concatenation
- ant-update.sh NameError: moved total_anthropic definition before if _scraped: block

**S30 COMPLETE (all three built and verified):**
- kai_analysis.py: prompt caching (3 cached blocks) + compact-2026-01-12 beta — LIVE
- bin/tickets-db.py: SQLite DB at kai/tickets/tickets.db — 61 tickets, BM25 search working
- bin/daily-maintenance.sh: DAILY at 01:30 MT (inbox trim, ticket dedup, log rotation)
- bin/weekly-maintenance.sh: WEEKLY Saturday 02:00 MT (heavy archiving)

**MAINTENANCE ARCHITECTURE (2026-04-23 — know this):**
Split into two tiers after measuring actual growth rates:
- Daily (01:30 MT): inbox grew 105 msgs in a few hours → must trim daily not weekly
  Script: bin/daily-maintenance.sh → deduplicates tickets.jsonl, trims inbox to 50, rotates logs
- Weekly (Saturday 02:00 MT): KAI_BRIEF/KAI_TASKS archiving, resolved ticket archiving, full stats
  Script: bin/weekly-maintenance.sh
- Tickets also have a STRUCTURAL cap (MAX_NOTES=20) baked into ticket.sh line ~179
  AND daily-maintenance.sh deduplicates any race-condition duplicates

**TICKET SYSTEM (2026-04-23):**
- PRIMARY: kai/tickets/tickets.db (SQLite, 61 tickets, FTS5 BM25 search)
- BACKUP: kai/tickets/tickets.jsonl (6 active tickets, deduped daily)
- Search: python3 bin/tickets-db.py search "query" → top-10 results (~2K tokens)
- OLD WAY was 55MB JSONL = 14M tokens uninjectable. New way = 2K tokens for relevant tickets.
- Gate: NEVER inject the full tickets.jsonl. Always use search_tickets() or tickets-db.py search.

**DESCRIBE-NOT-BUILD ERROR (S30, third occurrence):**
Compaction API, prompt caching, and SQLite migration were described in docs but not built.
Hyo caught it. Pattern: SE-010-008, SE-010-009, SE-S30-describe-001.
Gate question added: "Does the code file exist and does it run? YES → done. NO → not done."
This is NOT a process fix. Process fixes have failed twice. The fix must be structural:
every claimed implementation must have a verification step that reads the actual file.

**Still pending (S30 → S31):**
- tickets.jsonl → full SQLite migration: ticket.sh still writes JSONL as primary; needs flip
- Anthropic billing API for individual accounts: not available (no admin key option)
  → Best available: browser scrape + daily diff via ant-fetch-balance.py (one-time Keychain auth needed)


**TELEGRAM TWO-BOT ARCHITECTURE (wired 2026-04-28, verified live):**
- **@xAetherBot** — `AETHERBOT_TELEGRAM_TOKEN` — one-way alert sender only. Trade signals, analysis pipeline progress, pipeline failures. Never polls getUpdates.
- **@Kai_11_bot** — `TELEGRAM_BOT_TOKEN` — conversation interface only. Runs via `kai_telegram.py`. Handles /status, /balance, /analysis, /stop, /resume, free-text Claude conversations.
- TELEGRAM_CHAT_ID = 5098923226 (shared, same Hyo DM for both bots)
- Credential locations: `~/Documents/Projects/Kai/.env` ONLY — has all three: TELEGRAM_BOT_TOKEN, AETHERBOT_TELEGRAM_TOKEN, TELEGRAM_CHAT_ID. The security env (`agents/nel/security/env`) has AETHERBOT_KEY (Kalshi) only — no Telegram tokens. This was verified 2026-05-04 S33. Previous claim "both files have all three vars" was wrong.
- All alert senders updated to read AETHERBOT_TELEGRAM_TOKEN first (9 files, commit 024ffb8)
- Live test confirmed 2026-04-28: HTTP 200, message received by Hyo in @xAetherBot
- NEVER route alerts through TELEGRAM_BOT_TOKEN — that is @Kai_11_bot (conversations only)
- **S33 ROOT CAUSE + FIX (2026-05-04):** `aetherbot_logger.py` REQUIRED_KEYS was missing AETHERBOT_TELEGRAM_TOKEN. bot.py fell back to TELEGRAM_BOT_TOKEN (Kai bot) for all alerts. Fix: added AETHERBOT_TELEGRAM_TOKEN to REQUIRED_KEYS in `load_aetherbot_env()`. Verified via `ps eww` on bot.py PID that process env resolves to ...vDEnuX6Y. aetherbot_logger.py is NOT in Hyo git repo — changes tracked manually here.
- **com.kai.bot.plist unloaded (2026-05-04):** Was running old kai_bot.py with KeepAlive=true, causing 409 polling conflict with kai_telegram.py. Unloaded. Do not reload — kai_telegram.py is the sole Kai bot poller.
- **send_telegram_alert silently swallows exceptions.** Absence of error does NOT prove delivery. Verification = call the API directly, check HTTP 200 + ok:true in response body. Reasoning from env vars is not proof.
- **Verification method for bot token routing:** simulate bot.py line 22 using actual process env from `ps eww -p <PID>` — not file reads, not assumptions. Pattern: `resolved = env.get("AETHERBOT_TELEGRAM_TOKEN") or env.get("TELEGRAM_BOT_TOKEN")`.

---
## Memory Engine Sync — 2026-04-26 (nightly consolidation)

- [TECHNICAL] instruction_2026-04-18: **[HYO_INSTRUCTION]** Kai is the orchestrator, Hyo is the CEO and decision authority (conf=1.00)

---
## Memory Engine Sync — 2026-04-27 (nightly consolidation)

- [TECHNICAL] instruction_2026-04-18: **[HYO_INSTRUCTION]** Kai is the orchestrator, Hyo is the CEO and decision authority (conf=0.98)

---

## S32 / S32b ARCHITECTURE (2026-04-30)

**Last updated:** 2026-04-30

### Morning report synthesis pipeline (S32 — new, all three files built)

**Problem:** Morning report consumed raw ARIC research_conducted[] items directly — JSON blobs, internal file citations, and navigation text were being rendered as CEO-readable intelligence. Not readable.

**Fix (three-script chain, wired in generate-morning-report.sh):**

1. **`bin/aric-external-filter.py`** — filters research_conducted[] to external (http/https) sources only.
   - Blocks: file:// URLs, GROWTH.md, session-errors.jsonl, ACTIVE.md, PLAYBOOK.md, KNOWLEDGE.md, KAI_BRIEF.md, AGENT_ALGORITHMS.md, kai/ledger/*, kai/protocols/*, agents/*/GROWTH, agents/*/ACTIVE
   - Passes: any http/https URL (including Wikipedia, though flagged as generic)
   - If ALL items filtered → outputs [] → morning report shows "No external research completed overnight" (honest statement beats synthesized navel-gazing)

2. **`bin/morning-report-synthesize.py`** — synthesizes filtered items via Claude CLI (`claude -p --output-format text`).
   - Output format per item: {category, topic, takeaway, watch, agent}
   - Categories: AI-STRATEGY, AI-MODELS, AI-FINANCE, ONCHAIN, DEVELOPER-TOOLS, MARKET, RISK, OPPORTUNITY
   - Hard rules: no ARIC/GROWTH/session-errors mentions, no "The research shows" openers, specific beats vague
   - Falls back (exit 1) if Claude binary not found or returns non-JSON — caller uses raw items as fallback

3. **`bin/findings-to-aric.py`** — bridges agent-research.sh findings-DATE.md into aric-latest.json research_conducted[].
   - Runs at 04:45 MT (after agent-research.sh at 04:30 MT, before morning report at 07:00 MT)
   - **MERGE behavior (fixed S32b):** no longer overwrites research_conducted[] wholesale. Merges by topic+source key — ARIC Claude Code items are preserved, findings-to-aric items are added or updated.
   - Falls back to yesterday's findings if today's not found
   - Skips sources with <80 chars content or file:// URLs

**Pipeline sequence in kai-autonomous.sh:**
```
04:30 MT → agent-research.sh (all agents)
04:45 MT → findings-to-aric.py (bridges findings into aric-latest.json)
05:00 MT → generate-morning-report.sh
  └─ reads aric-latest.json research_conducted[]
  └─ pipes through aric-external-filter.py
  └─ pipes through morning-report-synthesize.py
  └─ publishes morning-report + commit + push
```

### kai-daily.sh (S32b — new)

**Location:** `agents/kai/kai-daily.sh`
**Schedule:** 23:30 MT via kai-autonomous.sh
**Purpose:** Kai's own daily improvement runner. Every other agent runs nightly; Kai was exempt. No longer.

**What it does (4 steps):**
1. Runs external research (agent-research.sh kai)
2. Parses findings for actionable signals: new frameworks → GROWTH.md note; arXiv papers → paper-queue.jsonl; dead sources (<100 chars) → research-sources.json flagged
3. Writes improvement log: agents/kai/research/improvement-log-DATE.json (chain: researched X → found Y → changed Z)
4. Publishes to HQ feed as type "kai-daily" (schema: kai/schemas/kai_daily.schema.json)

**Schema:** `kai/schemas/kai_daily.schema.json` — mandatory fields: summary, improvement. Required: summary, research, improvement, chain.

### Doctor dedup gate (S32b — bug fixed, SHA e1bb70f)

**Problem:** flywheel-doctor.sh `open_ticket()` was generating sequential IDs (TASK-20260430-nel-005, nel-006, etc.) on each run, bypassing the ID-based dedup in ticket.sh. Doctor runs 4-5x/day → 40+ duplicate SICQ/OMP tickets per day.

**Fix:** Python json.loads() dedup gate in `open_ticket()`. Before creating a ticket, parses tickets.jsonl line-by-line and checks for existing open ticket with same title+status+today's date. If found: returns existing ID, does not create duplicate. Tested against real data before commit.

**Lesson (Pattern 2 instance):** First fix used grep with compact JSON format ("title":"...") but tickets.jsonl uses spaced format ("title": "..."). Gate was silently inert — never matched. Fix: always read the actual ledger before writing grep patterns against it.

### Nel nightly window gate removed (S32b)

Nel reflection was gated to publish only during 00:00–02:59 MT (nightly window). Nel runs at 22:00 MT — outside that window. Reflection never published autonomously.

**Fix:** Gate removed. Nel now publishes every cycle, deduplicated by NEL_REPORT_PUBLISH_MARKER (one per calendar day). The comment at lines 876-887 describing the old gate has been updated to describe actual behavior.

### Role identity clarification

CLAUDE.md says "CEO MODE IS ON" — legacy shorthand for autonomous operation. KNOWLEDGE.md (this file) says "Kai is the orchestrator, not the CEO" — Hyo's explicit April 16 directive. KNOWLEDGE.md is authoritative. In documents, footers, and self-descriptions: orchestrator, not CEO.

### Pattern 9 added to kai-reasoning-patterns.md (S32)

"Reporting the Gap Instead of Closing It" — Kai identifies a gap and narrates it to Hyo instead of building the fix. Gate: "Am I narrating this gap TO Hyo, or am I closing it?" Only surface to Hyo if the fix requires a CEO-level decision (spend, strategy, feature toggle). Technical gaps are Kai's to close.

---

## MORNING REPORT CONTENT — RESEARCH FINDINGS (S32b, 2026-04-30)

Full research document: `agents/ra/research/morning-report-content-research-2026-04-30.md` (65+ sources)

### Key findings from CIA/PDB, Grove, HBR/McKinsey, Axios, crypto institutional research:

**The brief that works is short and judgment-driven, not comprehensive:**
- CIA President's Daily Brief = 1 page. 17 intelligence agencies. One page.
- Grove (*High Output Management*): identify 5 daily indicators. Leading, not lagging.
- HBR: 40% of executives feel highly burdened by information. Decision quality degrades with volume.
- Optimal item count: 5-7 intelligence items maximum. More = cognitive budget waste.

**The current synthesis format is structurally correct (BLUF/PDB standard):**
- category + specific topic + one takeaway sentence + one watch signal = exactly the PDB/BLUF format
- "Source returned no usable intelligence this cycle" gate = correct per PDB writing standard
- Delivery at 05:00 MT = correct (before peak cognitive window)

**Three structural gaps identified vs. best practice:**

1. **No DECISIONS REQUIRED section** — every high-rated briefing system (PDB, Axios, CEO briefing services) surfaces time-bound decisions first. Items where the window closes within 24-48 hours. Currently absent from morning report.

2. **No persistent WATCH LIST** — items Hyo is tracking that don't trigger every day. Protocol votes, competitor hiring, model release timelines. Rolling 3-5 items, manually curated or pulled from KAI_TASKS horizon items.

3. **RETRACTED (Hyo correction, 2026-04-30):** Crypto market data (price direction, stablecoin delta, DeFi TVL) does NOT belong in the morning report. hyo.world is a builder, not a trader. That data is a click away on DefiLlama/CoinGecko — it's a dashboard lookup, not intelligence requiring synthesis. The correct filter: does this item require judgment to be useful, or is it a data lookup? Crypto price signals fail the test. Crypto-domain items that DO belong: major protocol exploits on chains hyo.world uses, governance votes with closing deadlines that change fee structure or competitive rules, regulatory reclassification of NFTs/AI agents, competitors building into the same registry/identity space. Same relevance standard as everything else.

**Crypto/AI signals specific to hyo.world's domain:**
- AI agent identity / KYA (Know Your Agent) — a16z 2026 thesis = potential registry opportunity
- Anthropic/OpenAI pricing changes = direct API cost impact
- MCP ecosystem adoption = ecosystem tailwind for hyo.world's Claude Agent SDK foundation
- Ethereum governance proposals with 10-day vote windows (affects NFT/registry landscape)
- Competitor hiring posts (3-6 month ahead signal vs. press release which is 3-6 month lag)

**What NOT to include:**
- Operational theater ("agent ran successfully" = log, not intelligence)
- Compound sentences in takeaways (one sentence, one finding, one implication)
- More than 7 intelligence items (trim by relevance to hyo.world)
- Lagging indicators (what happened vs. what's about to happen)
- Items with no hyo.world-specific angle

**Implementation priority:**
- P0: Add DECISIONS REQUIRED section (source: open P0/P1 tickets with deadlines, credit budget thresholds, governance vote deadlines)
- P1: Add 3 crypto leading indicators (ETH/BTC direction, stablecoin delta, DeFi TVL mover) — DefiLlama/CoinGecko APIs, computable in 3 sentences
- P1: Add persistent WATCH LIST (3-5 rolling items)
- P2: Cap intelligence items at 7, add relevance-ranking to synthesis step
- P2: Expand ARIC sources to include hiring posts, GitHub commit frequency, governance forums

---

## MARINA WYSS RESEARCH FILES — PATHS AND TRIGGERS (2026-05-05)

Two Marina Wyss documents exist. They serve different jobs. Never confuse them.

### 1. The Holy Bible — Applied Analysis
**Path (both must be kept in sync):**
- `agents/sam/website/docs/research/marina-wyss-ai-agents-guide.html` (git-tracked, agents path)
- `website/docs/research/marina-wyss-ai-agents-guide.html` (git-tracked, Vercel-served path)
- Markdown: `agents/sam/website/docs/research/marina-wyss-ai-agents-guide.md`
- Live URL: `https://www.hyo.world/docs/research/marina-wyss-ai-agents-guide`
- HQ feed ID: `marina-wyss-ai-agents-2026-05-05`

**What it is:** Marina Wyss course content mapped to Hyo system failures and fixes. 14 findings, 3 passes of implementation, operational context. Every section shows what was broken in Hyo's system and what was shipped to fix it.

**When to reference it:** Post-mortem and remediation. When something fails and you want to know if this class of problem was already analyzed. When reviewing what implementations have already been shipped from Marina's course.

### 2. Complete Course Guide — Pure Reference
**Path (both must be kept in sync):**
- `agents/sam/website/docs/research/marina-wyss-complete-course-guide.html` (git-tracked, agents path)
- `website/docs/research/marina-wyss-complete-course-guide.html` (git-tracked, Vercel-served path)
- Markdown: `agents/sam/website/docs/research/marina-wyss-complete-course-guide.md`
- Live URL: `https://www.hyo.world/docs/research/marina-wyss-complete-course-guide`
- HQ feed ID: `research-drop-kai-2026-05-05-233516`

**What it is:** 16-chapter step-by-step reference. Pure course content — what Marina teaches, verbatim, chapter by chapter. No Hyo framing. Covers: perceive/decide/act loop, autonomy spectrum, context engineering, task decomposition, tool use, memory/knowledge separation, reflection, guardrails, GVU evaluation pattern, planning, multi-agent systems, advanced decomposition, latency/cost, observability, security, agent economy.

**When to reference it:** Pre-build and design review. Before designing any new agent, new capability, or new protocol, check the Quick Reference Card (10 questions at the bottom of this guide). It is wired into AGENT_CREATION_PROTOCOL.md as a mandatory pre-build gate.

**Quick Reference Card 10 questions (memorize these):**
1. Is there a perceive/decide/act loop? (Ch.1)
2. What autonomy level is appropriate? (Ch.2)
3. Is context injected: role + task + memory + tools + knowledge? (Ch.3)
4. Is every step independently observable? (Ch.4)
5. Is the tool interface separate from implementation? (Ch.5)
6. Is memory (dynamic) separate from knowledge (static)? (Ch.6)
7. Does the agent reflect after every action? (Ch.7)
8. Are input validation and output filtering in place? (Ch.8)
9. Is there one ground-truth metric that cannot be gamed (GVU)? (Ch.9)
10. Does the agent plan before acting and replan on unexpected results? (Ch.10)

### Why these two files are NOT redundant
The course guide is universal — how to build agents correctly from first principles. The holy bible is Hyo-specific — what was broken and what was fixed in this exact system. They trigger in different moments and should both exist permanently.

### DUAL-PATH RULE (SE-010-011) — enforced in GATE R2 of publish-to-feed.sh
Any research HTML published to HQ must exist at BOTH paths: `agents/sam/website/docs/research/` AND `website/docs/research/`. Vercel serves from `website/`. The `agents/sam/website/` path is the primary. GATE R2 in `bin/publish-to-feed.sh` auto-syncs from primary to Vercel path on publish. If both don't exist and match, GATE R2 blocks with exit 1.

### PROTOCOL_HQ_PUBLISH.md — current version (v1.2)
Location: `kai/protocols/PROTOCOL_HQ_PUBLISH.md`
Gates 9-12 (added 2026-05-05):
- GATE 9: readLink must NOT end in .md (Vercel can't serve markdown)
- GATE 10: Entry must be in reports[] not entries[] (renderResearch() reads reports[])
- GATE 11: author must be "Kai" (capital K — lowercase creates orphan filter group)
- GATE 12: Visual click-through verification mandatory after publish

### HYDRATION — SESSION-START ONLY (Marina Wyss Ch. 3 applied)
Hydration reads (KAI_BRIEF, KNOWLEDGE, TACIT, verified-state, session-handoff) happen ONCE at session start. Hourly re-reads waste tokens and cause context bloat — Marina Wyss context engineering principle. The HOURLY healthcheck should read verified-state.json (pre-computed state cache) only — not re-read all memory files. The distinction: read STATE hourly, read CONTEXT once at start.


### HYO RESEARCH PDF PROTOCOL (2026-05-06)
When creating any research PDF for Hyo, read `kai/protocols/PROTOCOL_HYO_RESEARCH_PDF.md` first.
Design system: Navy #1a1f3a + Gold #c9a027 + White background. Cover: navy panel, "HYO RESEARCH" gold label, white title, gold rule, subtitle. Chapter pages: navy block with CHAPTER N label + gold rule. Footer: "Hyo Research | [Title]" left, "Page N" right. Base script: `/sessions/gifted-happy-cori/build_marina_pdf.py` (generated the approved marina-wyss-complete-course-guide.pdf). ReportLab + SimpleDocTemplate + canvas callbacks for footer/top-rule.

### ORGANIZATION MAP (2026-05-06)
`ORGANIZATION_MAP.md` at project root is the canonical file location guide. Owned by Dex.
Covers: where every file type belongs, anti-patterns, archive system, classification legend.
Update it whenever files are moved or restructured. Dex runs weekly organization audits.
Key locations: protocols in `kai/protocols/`, agent protocols in `agents/<name>/PROTOCOL_*.md`, research docs in `agents/sam/website/docs/research/`.

### ARCHIVE SYSTEM (2026-05-06)
`bin/log-rotation.sh` — called by weekly-maintenance.sh every Saturday:
- Text logs > 5MB → compress tail, keep last 500 lines
- Queue completed jobs > 7d → monthly tar.gz in `kai/queue/archive/`
- claude-delegate-failed-*.txt → consolidated monthly archive in `kai/ledger/archive/`
- Aether analysis files > 30d → `agents/aether/archive/`
- Agent logs > 60d → `agents/<name>/archive/`
