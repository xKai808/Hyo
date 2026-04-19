# KNOWLEDGE.md — Permanent Hyo Instructions to Kai
#
# THIS IS NOT STATUS. This is what Hyo has told Kai that must be remembered forever.
# Every new session reads this. It never gets stale-pruned. It grows as Hyo instructs.
# Add to it immediately whenever Hyo gives significant feedback, decisions, or corrections.
#
# Last updated: 2026-04-18

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

## REMOTE ACCESS — HYO TRAVELING SOON

Before departure:
1. Install Tailscale on Mac mini (private encrypted network, no port forwarding)
2. Enable Remote Login (SSH): System Settings → General → Sharing
3. Install Tailscale on travel device, sign into same account
4. Note Mac mini's Tailscale IP (100.x.x.x format)
5. Test SSH: `ssh username@100.x.x.x`
6. Confirm aetherbot_logger.py is running via nohup (survives terminal close):
   `nohup /opt/homebrew/bin/python3 ~/aetherbot_logger.py > ~/aetherbot_logger_console.txt 2>&1 &`

Remote check once traveling:
- `ps aux | grep aetherbot_logger`
- `tail -f ~/Documents/Projects/AetherBot/Logs/AetherBot_$(date +%Y-%m-%d).txt`
- Source: Kai_Feedback_Apr16_2026.txt, Part 6

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

| Agent   | Protocol file                                  | Current version | When to read |
|---------|------------------------------------------------|-----------------|--------------|
| Aether  | `agents/aether/PROTOCOL_DAILY_ANALYSIS.md`     | v2.5            | Before any analysis, HQ publish, or runner change |
| Ant     | `agents/ant/PROTOCOL_ANT.md`                   | v1.2            | Before any credit data, ant-update.sh, or hq.html Ant tab work |

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

### Ant protocol quick reference (agents/ant/PROTOCOL_ANT.md v1.2)

- **Nightly run:** 23:45 MT via `com.hyo.ant-daily.plist` → `bash bin/ant-update.sh`
- **Dual-path:** ALWAYS stage both `agents/sam/website/data/ant-data.json` AND `website/data/ant-data.json`
- **Heredoc:** ALWAYS `<< 'PYEOF'` (quoted) — unquoted breaks Python f-strings
- **history[] field:** top-level in ant-data.json, NOT under costs.dailyHistory (that path does not exist)
- **HQ colors:** Anthropic = purple `#a855f7`, OpenAI = cyan `#06b6d4` — never swap
- **Credit source tiers:** Tier 1 (automated, headless) = MTD spend from api-usage.jsonl; Tier 2 (requires screen or Admin API key) = real account balance
- **After every run:** update `agents/ant/ACTIVE.md` + write log to `agents/ant/logs/ant-YYYY-MM-DD.log`
- **Git push:** run via Mini (`mcp__claude-code-mini__Bash` or `kai exec`) — Cowork sandbox has 403 proxy block
- **Open tickets:** ANT-GAP-001 (Admin API key), ANT-GAP-002 (monthly close job), ANT-GAP-003 (failure alert)
- **17 failure modes documented** in Part 13 — check before any Ant work

---

## MEMORY FAILURE LOG (so this never happens again)

2026-04-18: Hyo re-uploaded Kai_Feedback_Apr16_2026.txt and AetherBot_Analysis_Apr13-16.txt because
they were never saved to the project after the April 16 session. KAI_BRIEF.md captured status but
NOT knowledge. The knowledge layer (this file) did not exist. Fix: KNOWLEDGE.md created, both files
saved to kai/memory/feedback/, hydration protocol updated to read KNOWLEDGE.md every session.
