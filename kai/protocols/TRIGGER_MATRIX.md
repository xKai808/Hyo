# TRIGGER_MATRIX.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Status: AUTHORITATIVE — every artifact in the system must have an entry here

---

## PURPOSE

Every artifact (script, protocol, tool, check, daemon, spec) must have a documented trigger.
No dead files. No orphaned code. If something exists, it runs. If it runs, it's documented here.

"Every artifact has a trigger. No dead files. When creating anything — a script, a check,
a protocol, a spec — always ask: (1) How is it triggered? (2) When would it be missed?
(3) What ensures no miss?" — CLAUDE.md operating rules

---

## ALGORITHM-FIRST: THE TRIGGER AUDIT GATE

```
TRIGGER AUDIT GATE (Kai runs weekly as part of PROTOCOL_PROTOCOL_REVIEW.md GATE 4):

GATE 1: Is every .py and .sh file in agents/ and bin/ listed here?
  → find agents/ bin/ -name "*.py" -o -name "*.sh" | sort
  → Compare against entries in this file
  → Any file NOT listed → open task ticket: "add TRIGGER_MATRIX entry for <file>"

GATE 2: Does every listed trigger actually exist and run?
  → For cron/launchd triggers: verify plist exists and is loaded
  → For runner-phase triggers: grep the runner for the filename
  → For manual triggers: verify the kai.sh subcommand exists
  → NOT FOUND → flag as orphaned artifact

GATE 3: Has any artifact been created in the last 7 days without a TRIGGER_MATRIX entry?
  → find agents/ bin/ -name "*.py" -o -name "*.sh" -newer kai/protocols/TRIGGER_MATRIX.md
  → YES → open task ticket for each unlisted file

GATE 4: Are all listed protocols referenced from AGENT_ALGORITHMS.md?
  → grep -l "PROTOCOL_" kai/protocols/ | while read f; do
      grep -q "$(basename $f)" kai/AGENT_ALGORITHMS.md || echo "UNREFERENCED: $f"
    done
  → Any unreferenced protocol → open task ticket
```

---

## FORMAT

Each entry documents:
- **Artifact**: file path (relative to Hyo root)
- **Type**: script | protocol | config | data | runner
- **Trigger**: what causes it to run (cron, runner-phase, queue command, manual, event)
- **Schedule**: when (cron expression or plain English)
- **Execute**: what it does (one line)
- **Verify**: how to confirm it ran correctly (command or output location)
- **Owner**: which agent or Kai owns this artifact
- **Status**: ACTIVE | ORPHANED | PROPOSED | DEPRECATED

---

## SECTION 1: RUNNER SCRIPTS (Agent Runners)

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `agents/nel/nel.sh` | runner | launchd `com.hyo.nel` | 21:00 MT daily | Nel QA + security + ARIC + growth phases (8 total) | nel-report-DATE in feed.json | Nel | ACTIVE |
| `agents/ra/ra.sh` | runner | launchd `com.hyo.ra` | 03:00 MT daily | Ra newsletter + research + ARIC + growth phases | ra-report-DATE + newsletter-DATE in feed.json | Ra | ACTIVE |
| `agents/sam/sam.sh` | runner | launchd `com.hyo.sam` | 22:00 MT daily | Sam deploy check + API health + ARIC + growth phases | sam-report-DATE in feed.json | Sam | ACTIVE |
| `agents/aether/aether.sh` | runner | launchd `com.hyo.aether` | 22:30 MT Mon-Fri | Aether analysis + GPT crosscheck + HQ publish | aether-analysis-DATE in feed.json | Aether | ACTIVE |
| `agents/dex/dex.sh` | runner | launchd `com.hyo.dex` (via consolidate.sh) | 01:00 MT daily | Dex repair + cluster + dedup + integrity check | dex-report-DATE in feed.json | Dex | ACTIVE |

---

## SECTION 2: BIN/ UTILITIES

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `bin/kai.sh` | dispatcher | manual `kai <cmd>` | On demand | Routes subcommands to queue/local execution | Exit code + output | Kai | ACTIVE |
| `bin/kai.sh cmd_deploy` | script | manual `kai deploy` | On demand | Posts to Vercel deploy hook → triggers production deploy | Vercel job ID returned; `kai health` confirms live | Kai | ACTIVE |
| `bin/agent-growth.sh` | script | sourced by all runners | Before runner's Phase 1 | Runs growth cycle (ARIC research, improvement ticket check, weakness scan) | `growth-log-DATE.md` in agent's research/ dir | Kai | ACTIVE |
| `bin/agent-research.sh` | script | called by `check_aric_day()` in agent-growth.sh | Daily (first runner run per day) | 7-phase ARIC cycle: weakness ID, research, findings, improvement ticket | `findings-YYYY-MM-DD.md` in agent's research/ dir | Kai | ACTIVE |
| `bin/generate-morning-report.sh` | script | launchd `com.hyo.morning` | 05:00 MT daily | Generates growth-first morning report for all agents | morning-report-DATE in feed.json | Kai | ACTIVE |
| `bin/publish-to-feed.sh` | script | called by agent runners' final phase | Per runner schedule | Validates schema → writes to feed.json → dual-path sync | Both feed.json paths updated; live site shows entry | Kai | ACTIVE |
| `bin/report-completeness-check.sh` | script | launchd `com.hyo.completeness` | 07:00 MT daily | Verifies all required reports published; opens P1 ticket + auto-remediates missing | Completeness ticket opened if missing; `kai health` | Kai | ACTIVE |
| `bin/verify-live.sh` | script | post-publish (called by runners) | After every publish | Fetches live hyo.world/data/feed.json, confirms new entry visible | Returns PASS/FAIL; FAIL → `kai deploy` triggered | Kai | ACTIVE |
| `bin/ticket.sh` | script | manual or agent runner | On demand / runner phase | Creates/updates/resolves/closes tickets in tickets.jsonl | Ticket entry in `kai/tickets/tickets.jsonl` | Kai | ACTIVE |
| `bin/dispatch.sh` | script | manual `dispatch <cmd>` | On demand | Routes dispatch commands: delegate, report, simulate, health | Exit code; agent ACK in ledger | Kai | ACTIVE |
| `bin/goal-staleness-check.py` | script | launchd `com.hyo.goal-staleness` | 06:00 MT daily (PROPOSED) | Scans GROWTH.md + evolution.jsonl per agent; flags stale goals | Staleness flags in morning report; P1/P2 tickets opened | Kai | PROPOSED |
| `bin/weekly-report.sh` | script | launchd `com.hyo.weekly` | 06:00 MT Saturday | Generates weekly agent summary + archives reports | weekly-report-DATE in feed.json; research-archive.json | Kai | ACTIVE |
| `bin/archive-to-research.sh` | script | called by weekly-report.sh | 06:00 MT Saturday after weekly | Moves week's reports to research-archive.json by agent+month | research-archive.json updated | Kai | ACTIVE |
| `bin/analysis-gate.py` | script | called by aether.sh publish block | 22:45 MT Mon-Fri | Quality gate: validates Aether analysis meets minimum standard before HQ publish | PASS/FAIL log; FAIL blocks publish | Aether | ACTIVE |

---

## SECTION 3: DEX LEDGER TOOLS

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `agents/dex/dex-repair.py` | script | `consolidate.sh` Phase 0a | 01:00 MT daily | Repairs malformed JSONL entries in all agent ledgers | Repair summary logged; repaired entries marked | Dex | ACTIVE |
| `agents/dex/dex-cluster.py` | script | `consolidate.sh` Phase 0b | 01:00 MT daily | Clusters related issues; deduplicates ticket patterns | Cluster summary logged; duplicate tickets flagged | Dex | ACTIVE |
| `agents/dex/dex-dedup.py` | script | `consolidate.sh` Phase 0c | 01:00 MT daily | Auto-resolves known false positives in all issue ledgers (5 FP patterns) | "Summary: N resolved" in consolidate.sh log; resolved entries marked `resolved_fp` | Dex | ACTIVE |
| `agents/dex/known-fps.json` | config | read by `dex-dedup.py` | On dex-dedup.py run | Contains user-defined false positive patterns (beyond 5 built-ins) | File exists; dex-dedup.py reads without error | Dex | ACTIVE |

---

## SECTION 4: NEL SECURITY TOOLS

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `agents/nel/cipher.sh` | script | `nel.sh` Phase 2 | 21:00 MT daily (within nel runner) | 9-layer security scan: secrets, deps, endpoints, auth, CORS, env, SQLi, XSS, rate limits | cipher-report-DATE.md in nel/logs/ | Nel | ACTIVE |
| `agents/nel/sentinel.sh` | script | `nel.sh` Phase 3 | 21:00 MT daily (within nel runner) | QA checks: API health, schema validation, KV connectivity | sentinel-report-DATE.md in nel/logs/ | Nel | ACTIVE |
| `agents/nel/dep-audit.sh` | script | `cipher.sh` Layer 5 | Every 6h via nel.sh | npm audit + pip-audit dependency vulnerability check | dep-audit-DATE.md in nel/logs/; P1 ticket if vulns found | Nel | ACTIVE |
| `agents/nel/consolidation/consolidate.sh` | script | launchd `com.hyo.consolidate` | 01:00 MT daily | Runs Dex repair/cluster/dedup (Phase 0) + nightly consolidation (Phases 1-N) | Consolidation log; all ledgers updated | Nel | ACTIVE |

---

## SECTION 5: RA PIPELINE TOOLS

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `agents/ra/pipeline/newsletter.sh` | script | `ra.sh` main phase | 03:00 MT daily | Orchestrates gather → synthesize → render → send newsletter pipeline | newsletter-ra-DATE in feed.json; subscriber delivery confirmation | Ra | ACTIVE |
| `agents/ra/pipeline/gather.py` | script | called by `newsletter.sh` | 03:00 MT daily | Fetches from sources.json (6+ sources); returns raw content | gathered-DATE.json in ra/research/ | Ra | ACTIVE |
| `agents/ra/pipeline/synthesize.py` | script | called by `newsletter.sh` | 03:00 MT daily | Synthesizes gathered content into newsletter narrative | synthesized-DATE.md in ra/research/ | Ra | ACTIVE |
| `agents/ra/pipeline/render.py` | script | called by `newsletter.sh` | 03:00 MT daily | Renders newsletter HTML from synthesized content | newsletter-DATE.html in ra/output/ | Ra | ACTIVE |
| `agents/ra/pipeline/send_email.py` | script | called by `newsletter.sh` | 03:00 MT daily | Sends rendered HTML to subscriber list | Delivery confirmation in ra/logs/ | Ra | ACTIVE |

---

## SECTION 6: AETHER ANALYSIS TOOLS

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `agents/aether/analysis/*.py` | scripts | `aether.sh` analysis block | 22:30-22:45 MT Mon-Fri | AetherBot analysis (7-gate decision tree per ANALYSIS_ALGORITHM.md) | Analysis output JSON; gpt_crosscheck_ran=true | Aether | ACTIVE |
| `agents/aether/analysis/gpt_factcheck.py` | script | `aether.sh` crosscheck phase | 22:45 MT Mon-Fri | GPT adversarial crosscheck of Aether's analysis | gpt_crosscheck output in analysis log | Aether | ACTIVE |
| `agents/aether/aggregate-weekly.py` | script | `aether.sh` Step 12b | 22:45 MT Saturday | Aggregates week's Aether analyses into weekly summary | weekly-aether-DATE.json in aether/logs/ | Aether | ACTIVE |

---

## SECTION 7: MEMORY AND CONSOLIDATION TOOLS

| Artifact | Type | Trigger | Schedule | Execute | Verify | Owner | Status |
|---|---|---|---|---|---|---|---|
| `kai/memory/agent_memory/memory_engine.py` | script | session start (Kai) + observe_* calls throughout | Real-time + 01:15 MT consolidation | SQLite-backed memory: observe, recall, promote working→episodic→semantic | DB exists; recall returns results; `memory_engine.py recall "test" --limit 1` | Kai | ACTIVE |
| `kai/memory/agent_memory/init_protocols.py` | script | first session if DB missing | On demand / session start | Initializes memory DB with protocol knowledge | DB initialized; memory_engine.py returns results | Kai | ACTIVE |
| `kai/context-save.sh` | script | manual `kai save` | On demand during long sessions | Snapshots current session context to kai/context/ | context-TIMESTAMP.md in kai/context/ | Kai | ACTIVE |
| `agents/nel/consolidation/consolidate.sh` (nightly pipeline) | script | launchd `com.hyo.consolidate` | 01:00 MT daily | Full nightly consolidation: Dex tools (Phase 0) + knowledge extraction + memory promotion | Consolidation log; KNOWLEDGE.md updated | Nel | ACTIVE |

---

## SECTION 8: PROTOCOLS (kai/protocols/)

These are not scripts but they are artifacts. Every protocol must be referenced by at least one agent PLAYBOOK.md or AGENT_ALGORITHMS.md. Protocols without references are dead.

| Protocol File | Version | Trigger (what reads it) | Verify (referenced from) | Owner | Status |
|---|---|---|---|---|---|
| `EXECUTION_GATE.md` | 1.0 | Kai session start; every pre-action check | CLAUDE.md hydration step 5; AGENT_ALGORITHMS.md | Kai | ACTIVE |
| `VERIFICATION_PROTOCOL.md` | 1.0 | Kai session start; post-action | CLAUDE.md hydration step 6; AGENT_ALGORITHMS.md | Kai | ACTIVE |
| `RESOLUTION_ALGORITHM.md` | 1.0 | Kai on ticket resolution | AGENT_ALGORITHMS.md | Kai | ACTIVE |
| `AGENT_RESEARCH_CYCLE.md` | 1.0 | agent-growth.sh ARIC phase | AGENT_ALGORITHMS.md; all PLAYBOOKs | Kai | ACTIVE |
| `REASONING_FRAMEWORK.md` | 1.0 | Monthly review; Kai + all agents | AGENT_ALGORITHMS.md | Kai + All | ACTIVE |
| `PROTOCOL_MORNING_REPORT.md` | 1.0 | generate-morning-report.sh | AGENT_ALGORITHMS.md; Kai PLAYBOOK | Kai | ACTIVE |
| `PROTOCOL_TICKET_LIFECYCLE.md` | 1.0 | ticket.sh; agent runners; Kai | AGENT_ALGORITHMS.md; all PLAYBOOKs | Kai | ACTIVE |
| `PROTOCOL_HQ_PUBLISH.md` | 1.0 | publish-to-feed.sh; all agent runners' final phase | AGENT_ALGORITHMS.md; all PLAYBOOKs | Kai | ACTIVE |
| `PROTOCOL_AETHER_ISOLATION.md` | 1.0 | Kai delegation checklist GATE 2 (Aether tasks); Nel audit | AGENT_ALGORITHMS.md; PROTOCOL_PREFLIGHT.md | Kai | ACTIVE |
| `PROTOCOL_GOAL_STALENESS.md` | 1.0 | bin/goal-staleness-check.py (PROPOSED); Kai daily audit | AGENT_ALGORITHMS.md | Kai | ACTIVE |
| `PROTOCOL_PROTOCOL_REVIEW.md` | 1.0 | Kai daily session start (after hydration) | AGENT_ALGORITHMS.md; KAI_BRIEF.md | Kai | ACTIVE |
| `PROTOCOL_PREFLIGHT.md` | 1.0 | Kai + all agents before any file create/modify/decision | AGENT_ALGORITHMS.md; all PLAYBOOKs | Kai | ACTIVE |
| `TRIGGER_MATRIX.md` | 1.0 | Kai weekly (PROTOCOL_PROTOCOL_REVIEW.md GATE 4); Nel audit | AGENT_ALGORITHMS.md | Kai | ACTIVE |

---

## SECTION 9: LEDGER AND DATA FILES

| Artifact | Type | Updated By | Read By | Verify | Owner | Status |
|---|---|---|---|---|---|---|
| `kai/tickets/tickets.jsonl` | data | `bin/ticket.sh` | Kai, Nel, all agents | Grep for today's tickets; count open | Kai | ACTIVE |
| `kai/ledger/known-issues.jsonl` | data | Kai + agents post-incident | Kai session start (hydration step 3) | File exists; read at session start | Kai | ACTIVE |
| `kai/ledger/session-errors.jsonl` | data | Kai after every mistake | Kai session start (hydration step 4) | File exists; read at session start | Kai | ACTIVE |
| `kai/ledger/hyo-inbox.jsonl` | data | Hyo, external triggers | Kai session start (hydration step 1.5) | Unread messages surfaced at session start | Kai | ACTIVE |
| `kai/ledger/protocol-review-log.jsonl` | data | Kai daily after protocol review | PROTOCOL_PROTOCOL_REVIEW.md verification | Entry for today exists after audit | Kai | ACTIVE |
| `kai/ledger/simulation-outcomes.jsonl` | data | `dispatch simulate` nightly | Kai session start (hydration step 7) | File exists; today's entry present | Kai | ACTIVE |
| `agents/dex/ledger/known-errors.jsonl` | data | Dex + Kai after root cause analysis | ticket.sh close gate; Kai decision gate | File exists; workarounds have expiry dates | Dex | ACTIVE |
| `agents/dex/ledger/constitution-drift.jsonl` | data | Dex nightly drift check | PROTOCOL_PROTOCOL_REVIEW.md GATE 7 | Today's entry present | Dex | ACTIVE |
| `agents/<agent>/evolution.jsonl` | data | Agent runners (end of each cycle) | Kai daily (staleness check, dead-loop detection) | Entry within 48h (P2 flag if older) | Agent | ACTIVE |
| `agents/<agent>/ledger/ACTIVE.md` | data | Agent runners (every cycle) | Kai healthcheck q2h | Updated within 24h (P2) or 48h (P1) | Agent | ACTIVE |
| `agents/<agent>/GROWTH.md` | data | Agent self-assessment + Kai review | agent-growth.sh; morning report | Has 3 weaknesses, 3 improvements, goals table | Agent | ACTIVE |
| `agents/<agent>/research/findings-YYYY-MM-DD.md` | data | agent-research.sh (ARIC Phase 4) | Morning report; PROTOCOL_PROTOCOL_REVIEW.md GATE 3 | Created daily; has 3+ specific sourced findings | Agent | ACTIVE |
| `website/data/feed.json` | data | `bin/publish-to-feed.sh` | Vercel → hyo.world HQ | Both paths updated; live site shows new entry | Sam | ACTIVE |
| `agents/sam/website/data/feed.json` | data | `bin/publish-to-feed.sh` (dual-path) | Vercel (dual-path sync gate) | Matches website/data/feed.json | Sam | ACTIVE |

---

## SECTION 10: SCHEDULED TASK REGISTRY

This table maps artifacts to their launchd plists or cron entries. Cross-reference with actual launchd list to verify all are loaded.

| launchd Label | Script | Time (MT) | Days | Verify Loaded |
|---|---|---|---|---|
| `com.hyo.nel` | `agents/nel/nel.sh` | 21:00 | Daily | `launchctl list com.hyo.nel` |
| `com.hyo.ra` | `agents/ra/ra.sh` | 03:00 | Daily | `launchctl list com.hyo.ra` |
| `com.hyo.sam` | `agents/sam/sam.sh` | 22:00 | Daily | `launchctl list com.hyo.sam` |
| `com.hyo.aether` | `agents/aether/aether.sh` | 22:30 | Mon-Fri | `launchctl list com.hyo.aether` |
| `com.hyo.consolidate` | `agents/nel/consolidation/consolidate.sh` | 01:00 | Daily | `launchctl list com.hyo.consolidate` |
| `com.hyo.morning` | `bin/generate-morning-report.sh` | 05:00 | Daily | `launchctl list com.hyo.morning` |
| `com.hyo.completeness` | `bin/report-completeness-check.sh` | 07:00 | Daily | `launchctl list com.hyo.completeness` |
| `com.hyo.weekly` | `bin/weekly-report.sh` | 06:00 | Saturday | `launchctl list com.hyo.weekly` |
| `com.hyo.goal-staleness` | `bin/goal-staleness-check.py` | 06:00 | Daily | `launchctl list com.hyo.goal-staleness` (PROPOSED) |

---

## SECTION 11: ITEMS CREATED IN SESSIONS 22-23 (Verification Checklist)

These artifacts were created in today's sessions. Verify each has a working trigger.

| Artifact | Created | Trigger Documented | Trigger Verified | Notes |
|---|---|---|---|---|
| `agents/dex/dex-dedup.py` | 2026-04-21 | ✓ Section 3 | ✓ (ran via queue, 128 FPs resolved) | consolidate.sh Phase 0c |
| `agents/nel/dep-audit.sh` | 2026-04-21 | ✓ Section 4 | ✓ (cipher.sh Layer 5 wired) | q6h via nel runner |
| `agents/aether/aggregate-weekly.py` | 2026-04-21 | ✓ Section 6 | Needs verify on Saturday | aether.sh Step 12b |
| `agents/aether/analysis-quality-gate.sh` | 2026-04-21 | ✓ Section 2 | Needs verify next Aether run | aether.sh publish block |
| `bin/agent-growth.sh` (ARIC fix) | 2026-04-21 | ✓ Section 2 | ✓ (check_aric_day() now calls agent-research.sh) | All runner growth phases |
| `bin/kai.sh` (deploy hook fix) | 2026-04-21 | ✓ Section 2 | ✓ (tested via queue) | `kai deploy` command |
| `kai/protocols/PROTOCOL_TICKET_LIFECYCLE.md` | 2026-04-21 | ✓ Section 8 | Needs AGENT_ALGORITHMS.md reference | ticket.sh + all PLAYBOOKs |
| `kai/protocols/PROTOCOL_HQ_PUBLISH.md` | 2026-04-21 | ✓ Section 8 | Needs AGENT_ALGORITHMS.md reference | publish-to-feed.sh + runners |
| `kai/protocols/PROTOCOL_AETHER_ISOLATION.md` | 2026-04-21 | ✓ Section 8 | Needs AGENT_ALGORITHMS.md reference | Kai delegation checklist |
| `kai/protocols/PROTOCOL_GOAL_STALENESS.md` | 2026-04-21 | ✓ Section 8 | goal-staleness-check.py not yet created (PROPOSED) | bin/goal-staleness-check.py |
| `kai/protocols/PROTOCOL_PROTOCOL_REVIEW.md` | 2026-04-21 | ✓ Section 8 | Needs AGENT_ALGORITHMS.md reference | Kai daily session start |
| `kai/protocols/PROTOCOL_PREFLIGHT.md` | 2026-04-21 | ✓ Section 8 | Needs AGENT_ALGORITHMS.md reference | All agents + Kai pre-action |
| `kai/protocols/TRIGGER_MATRIX.md` | 2026-04-21 | ✓ (self) | Needs AGENT_ALGORITHMS.md reference | PROTOCOL_PROTOCOL_REVIEW.md GATE 4 |
| `bin/goal-staleness-check.py` | PROPOSED | Section 2 | Not yet created | Open task ticket: create this |
| `agents/dex/ledger/known-errors.jsonl` | PROPOSED | Section 9 | Not yet created | Open task ticket: create KEDB |

---

## SECTION 12: TRIGGER VERIFICATION COMMANDS

```bash
# Verify all launchd jobs are loaded
launchctl list | grep com.hyo

# Verify consolidate.sh calls dex-dedup.py (Phase 0c)
grep -n "dex-dedup" agents/nel/consolidation/consolidate.sh

# Verify cipher.sh calls dep-audit.sh (Layer 5)
grep -n "dep-audit" agents/nel/cipher.sh

# Verify aether.sh calls aggregate-weekly.py
grep -n "aggregate-weekly" agents/aether/aether.sh

# Verify aether.sh calls analysis-quality-gate.sh
grep -n "analysis-quality-gate" agents/aether/aether.sh

# Verify agent-growth.sh calls agent-research.sh
grep -n "agent-research.sh" bin/agent-growth.sh

# Verify publish-to-feed.sh does dual-path sync
grep -n "sam/website" bin/publish-to-feed.sh

# Verify all runners source agent-growth.sh
for agent in nel ra sam aether dex; do
  grep -q "agent-growth.sh" agents/$agent/$agent.sh && echo "$agent: WIRED" || echo "$agent: NOT WIRED"
done

# Find any .py or .sh files NOT in this TRIGGER_MATRIX
find agents/ bin/ \( -name "*.py" -o -name "*.sh" \) | while read f; do
  grep -q "$(basename $f)" kai/protocols/TRIGGER_MATRIX.md || echo "UNLISTED: $f"
done
```
