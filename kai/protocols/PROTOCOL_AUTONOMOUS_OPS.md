# PROTOCOL_AUTONOMOUS_OPS.md
# Version: 1.0 — 2026-04-21
# Owner: Kai (CEO)
# Triggered by: kai-autonomous.sh (master orchestrator daemon, every 15 min)
# Purpose: The complete specification for self-driving daily operations.
#          Replaces manual prompting, manual checks, and manual pushes.
#
# PRINCIPLE: Kai is always running. Hyo's only job is to make strategic decisions.
#            Everything else — agent execution, health checks, failure recovery,
#            reporting, ticket resolution, memory — runs autonomously on this protocol.

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: DAILY SCHEDULE (Mountain Time)
# ═══════════════════════════════════════════════════════════════════════════════

## Primary Schedule

| Time (MT) | What runs | Owner | Self-heals if missed? |
|-----------|-----------|-------|----------------------|
| 00:00 | Dex integrity scan | dex.sh | YES — retry at 00:30 |
| 00:15 | Nel sentinel+cipher | nel.sh Phase 1+2 only | YES — retry at 00:45 |
| 01:00 | Memory consolidation | consolidate.sh | YES — retry at 01:30 |
| 03:00 | Ra newsletter pipeline | newsletter.sh | YES — retry at 04:00 |
| 04:30 | Ra research briefs | ra.sh Phase 6 | YES — retry at 05:00 |
| 05:00 | Nel full run | nel.sh (all phases) | YES — retry at 05:30 |
| 05:30 | Morning report generate | generate-morning-report.sh | YES — retry at 06:30 |
| 07:00 | Completeness check | report-completeness-check.sh | YES — opens P0 ticket |
| 08:00 | Sam deploy check + tests | sam.sh test | YES — retry at 08:30 |
| 09:00 | Aurora retention email | aurora-retention.js (via curl) | YES — retry at 10:00 |
| 09:30 | Queue hygiene | queue-hygiene.sh | YES — retry at 10:00 |
| 10:00 | Hyo UI/UX surface audit | hyo.sh | YES — retry at 10:30 |
| 12:00 | Ticket SLA enforcer | ticket-sla-enforcer.sh | YES — runs every 30 min |
| 15:00 | Root-cause enforcer | root-cause-enforcer.sh | YES — retry at 16:00 |
| 15:00 | Aether analysis (Mon-Fri) | aether.sh + kai_analysis.py | YES — retry at 16:00 |
| 16:00 | Dispatch sync transcript | dispatch-sync.sh | YES — retry at 17:00 |
| 22:00 | Nel daily report publish | nel → publish-to-feed.sh | YES — opens P1 ticket |
| 22:30 | Sam daily report publish | sam → publish-to-feed.sh | YES — opens P1 ticket |
| 22:45 | Aether daily report | aether → publish-to-feed.sh | YES — opens P1 ticket |
| 23:00 | Aether analysis publish (Mon-Fri) | aether-analysis-publish.sh | YES — opens P1 ticket |
| 23:30 | Kai daily CEO report | kai → publish-to-feed.sh | YES — opens P1 ticket |

## Aether Continuous
| Interval | What runs | Notes |
|----------|-----------|-------|
| Every 15 min | aether.sh (metrics) | Monday reset at 00:00 |

## SLA Enforcement
| Interval | What runs | Notes |
|----------|-----------|-------|
| Every 30 min | ticket-sla-enforcer.sh | P0:30m P1:1h P2:4h P3:24h |

## Weekly (Saturday)
| Time | What runs |
|------|-----------|
| 06:00 | weekly-report.sh (all agents) |
| 07:00 | archive-to-research.sh |

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: SELF-HEALING RULES
# ═══════════════════════════════════════════════════════════════════════════════

## Agent Missed-Run Detection

Each agent has a "freshness threshold" — max hours since last successful run before
kai-autonomous.sh triggers a retry and opens a ticket.

| Agent | Freshness Threshold | Action if Stale |
|-------|--------------------|-|
| Nel | 26h | Retry run → if fails 3x → P1 ticket + Hyo inbox |
| Ra | 26h | Retry newsletter → if blocked → P0 ticket |
| Sam | 26h | Retry test suite → P1 if fails |
| Aether | 20 min | Restart metrics collector → P0 if fails 3x |
| Dex | 26h | Retry integrity scan |
| Hyo | 26h | Retry surface audit |
| Morning report | 2h after 07:00 | P0 ticket + regenerate |
| Newsletter | 4h after 06:00 | P0 ticket + retry |

## Retry Policy
- First failure: immediate retry (same job, same parameters)
- Second failure: log + retry at next scheduled window
- Third failure: open P1 ticket (P0 if critical path), nudge to owning agent
- Fifth consecutive failure: page Hyo inbox with full context

## Blocker Resolution (vs Deferral)
- BLOCKED ticket with no progress in 24h → kai-autonomous.sh demotes to DEFERRED
- DEFERRED tickets reviewed weekly by Kai → either re-activate or close with decision documented
- Infinite escalation loops are blocked: if same ticket escalated 10+ times → auto-close with analysis note

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: QUALITY METRICS (what "healthy" looks like)
# ═══════════════════════════════════════════════════════════════════════════════

## System Health Score (0-100)
Computed by kai-autonomous.sh on every run. Published to HQ feed daily.

| Metric | Weight | Healthy Value |
|--------|--------|---------------|
| Agent freshness (all 6 agents ran in last 26h) | 20 | 6/6 = 20 pts |
| Newsletter published today | 15 | yes = 15 pts |
| HQ reports complete (all required types) | 15 | 5/5 = 15 pts |
| Ticket SLA compliance (% tickets within SLA) | 15 | ≥90% = 15 pts |
| Open P0 tickets | 10 | 0 = 10 pts |
| Broken link count (Nel Phase 4) | 10 | 0 = 10 pts |
| Nel false positive rate | 5 | <10% = 5 pts |
| Queue hygiene (completed/ < 50 items) | 5 | <50 = 5 pts |
| Recurring pattern count (Dex Phase 4) | 5 | <20 = 5 pts |

Score >85 = GREEN. Score 70-85 = YELLOW. Score <70 = RED (Hyo inbox notification).

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: AUTONOMOUS DECISION AUTHORITY
# ═══════════════════════════════════════════════════════════════════════════════

## Kai can decide autonomously (no Hyo approval needed):
- Create, escalate, close tickets
- Retry failed agent runs
- Archive stale data and queue items
- Change agent priorities (within same priority tier)
- Fix broken links in documentation
- Update ACTIVE.md and memory files
- Self-delegate tasks to agents
- Open and close P2/P3 tickets
- Update protocols and playbooks (non-constitutional)
- Deploy code changes (Sam deploy)
- Generate and publish reports

## Requires Hyo approval (page inbox and wait):
- Opening P0 tickets (page immediately)
- Spending money / API keys provisioning
- Constitutional changes (CLAUDE.md, AGENT_ALGORITHMS.md)
- Architecture decisions (new agents, retiring agents)
- Stripe/payment actions
- Cross-platform integrations

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: ROOT-CAUSE ENFORCEMENT PROTOCOL
# ═══════════════════════════════════════════════════════════════════════════════

## Recurring Issue Definition
A "recurring issue" is any pattern in known-issues.jsonl that has appeared
in 3+ consecutive daily runs without a RESOLVED entry in the same cycle.

## Enforcement Loop
1. root-cause-enforcer.sh runs daily at 15:00 MT
2. Reads known-issues.jsonl — extracts issues with streak ≥ 3
3. For each recurring issue:
   a. Opens an improvement ticket (if not already open with same title)
   b. Assigns to the owning agent
   c. Writes a "root-cause analysis required" nudge to agent's ACTIVE.md
   d. Sets SLA: P2 (4h) if streak 3-6, P1 (1h) if streak 7-14, P0 (30min) if streak ≥15
4. At daily cycle end, each agent's runner must call resolve_recurring_patterns()
   which checks if known issues dropped from prior day → marks improvement ticket RESOLVED

## Zero-Tolerance Patterns (auto-escalate to Hyo inbox after 3 occurrences):
- Any P0 cipher leak in production
- Newsletter missing for 2+ consecutive days
- HQ health check returning non-200
- Aether metrics more than 30 min stale

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: AGENT SELF-IMPROVEMENT CYCLE (runs every agent, every cycle)
# ═══════════════════════════════════════════════════════════════════════════════

## Mandatory per-agent cycle structure:
1. Source ticket-agent-hooks.sh → ticket_cycle_start()
2. Run growth phase (agent-growth.sh)
3. Run ARIC cycle (7 phases, 38 questions — see AGENT_RESEARCH_CYCLE.md)
4. Execute main agent work
5. Root-cause check: did any recurring issue get fixed this cycle?
6. Update ACTIVE.md, evolution.jsonl
7. Publish report to HQ via publish-to-feed.sh
8. ticket_cycle_complete() for any resolved tickets
9. Memory write: daily note + memory engine

## Self-Evolution Gate (before publishing):
- Did improvement score increase vs yesterday? (GROWTH.md W1/W2/W3 progress)
- Did recurring pattern count decrease? (Dex Phase 4)
- Did false positive rate decrease? (Nel)
- Did broken link count decrease?
If 0/4: agent must document WHY in evolution.jsonl before publishing.

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: MEMORY CONSOLIDATION PROTOCOL
# ═══════════════════════════════════════════════════════════════════════════════

## Real-time writes (every session, immediately):
- Hyo feedback → memory_engine.observe_correction()
- Hyo file upload → memory_engine.observe_upload()
- Hyo decision → memory_engine.observe_hyo()
- Daily note → kai/memory/daily/YYYY-MM-DD.md

## Nightly consolidation (01:00 MT via consolidate.sh):
- Extract durable facts from daily notes → KNOWLEDGE.md
- Promote working memory → episodic → semantic (SQLite)
- Sync semantic facts → KNOWLEDGE.md
- Prune guidance.jsonl (keep last 30 days, archive older)
- Archive completed tickets (>30 days old) to kai/tickets/archive/

## Anti-redundancy rules:
- guidance.jsonl max size: 50 entries (oldest evicted when exceeded)
- known-issues.jsonl max age: 90 days active, then archive
- session-errors.jsonl max: 100 entries
- Daily notes kept 30 days rolling, then archived to kai/memory/archive/YYYY/

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: WHAT KAI NEVER DOES (hard blocks)
# ═══════════════════════════════════════════════════════════════════════════════

1. Never skips hydration at session start
2. Never asks Hyo to copy/paste a command
3. Never patches without a gate
4. Never publishes without verification
5. Never closes a ticket without evidence
6. Never lets a recurring issue go 7+ days without escalating to P0
7. Never lets queue backup exceed 100 completed items
8. Never publishes a research-drop without URL citations
9. Never lets morning report be missing after 09:00 MT (auto-regenerates)
10. Never treats local commit as "done" — push must follow immediately
