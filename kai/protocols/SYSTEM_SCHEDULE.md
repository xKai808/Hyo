# SYSTEM_SCHEDULE.md — Master Daily Schedule
**Version:** 1.1
**Updated:** 2026-04-21
**Owner:** Kai (CEO)
**Read by:** All agents during hydration. Referenced in CLAUDE.md, AGENT_ALGORITHMS.md.

This is the single source of truth for WHEN everything runs and WHY that order matters.
Agents and Kai must read this to understand the system's dependency chain.
kai-autonomous.sh implements this schedule. If there's a conflict, this doc wins — update kai-autonomous.sh.

---

## Dependency Chain (Critical Path for Morning Report)

```
22:00 Nel runner
22:30 Sam runner          } Agent daily reports → feed.json → HQ
22:45 Aether daily        }
23:00 Aether full analysis (Mon-Fri only)
23:30 Kai CEO daily report
23:45 System health report (health score → HQ)
       ↓
01:00 Memory consolidation (daily notes → KNOWLEDGE.md)
01:15 Nightly consolidation (SQLite memory engine promotion)
       ↓
03:00 Ra newsletter pipeline → newsletter + ra-daily → HQ
       ↓
04:30 Self-improve cycle (all agents — flywheel)
      → writes aric-latest.json, self-improve-state.json per agent
       ↓
05:30 Flywheel doctor MORNING RUN → SICQ fresh
      → writes sicq-latest.json (Kai exec compliance + all agents)
       ↓
06:00 OMP measurement → DQI/OSS/KRI/AAS/BIS fresh
      → writes omp-summary.json, kai/agents/ledger/omp-latest.json
      → publishes omp-daily to HQ feed
       ↓
06:15 Memory snapshot → pushes SICQ+OMP to SQLite engine
       ↓
06:00 Sat: Weekly report
06:45 Sat: Cross-agent adversarial review
       ↓
07:00 ★ MORNING REPORT ★ — has ALL fresh data
      → reads: aric-latest, GROWTH.md, sicq-latest, omp-summary, feed
      → writes: morning-report.json → HQ dashboard
      → publishes: morning-report-DATE to HQ feed
       ↓
07:15 Completeness check — auto-remediates any missing entries
       ↓
09:00 Queue hygiene
09:30 Flywheel doctor MIDDAY → second SICQ write (available intra-day)
15:00 Root-cause enforcer
17:00 Flywheel doctor EVENING → third SICQ write before night agents run
       ↓
22:00 Cycle repeats
```

---

## Full Schedule Table

| Time (MT) | Job | Script | Produces | Depends on |
|-----------|-----|--------|----------|-----------|
| 22:00 | Nel runner | `agents/nel/nel.sh` | `nel-daily-DATE` on HQ | — |
| 22:30 | Sam runner | `agents/sam/sam.sh` | `sam-daily-DATE` on HQ | — |
| 22:45 | Aether daily | `agents/aether/aether.sh` | `aether-daily-DATE` on HQ | — |
| 23:00 (Mon-Fri) | Aether analysis | `run_analysis.sh` | `aether-analysis-DATE` on HQ | Aether daily |
| 23:30 | Kai CEO report | `bin/kai-daily.sh` | `kai-daily-DATE` on HQ | All agents ran |
| 23:45 | Health report | kai-autonomous.sh | health entry on HQ | All agents |
| 01:00 | Memory consolidation | `nel/consolidation/consolidate.sh` | KNOWLEDGE.md updated | Daily notes |
| 01:15 | Nightly consolidation | `nightly_consolidation.sh` | SQLite memory updated | consolidate.sh |
| 03:00 | Ra newsletter | `agents/ra/pipeline/newsletter.sh` | `newsletter-ra-DATE`, `ra-daily-DATE` on HQ | External APIs |
| 04:30 | Self-improve (flywheel) | `bin/agent-self-improve.sh all` | `aric-latest.json` per agent | — |
| 05:30 | Flywheel doctor (morning) | `bin/flywheel-doctor.sh` | `sicq-latest.json` (fresh) | Flywheel at 04:30 |
| 06:00 | OMP measurement | `bin/omp-measure.sh` | `omp-summary.json` + `omp-daily` on HQ | SICQ at 05:30 |
| 06:15 | Memory snapshot | `memory_engine.py observe` | SICQ+OMP in SQLite | OMP at 06:00 |
| 06:00 (Sat) | Weekly report | `bin/weekly-report.sh` | `weekly-report-DATE` on HQ | All weekly data |
| 06:45 (Sat) | Cross-agent review | `bin/cross-agent-review.sh` | Peer review entries on HQ Research | OMP at 06:00 |
| **07:00** | **★ Morning report** | **`bin/generate-morning-report.sh`** | **`morning-report.json` → HQ dashboard** | All above ✓ |
| 07:15 | Completeness check | `bin/report-completeness-check.sh` | Auto-remediation of gaps | Morning report |
| 09:00 | Queue hygiene | `bin/queue-hygiene.sh` | Cleaned queue | — |
| 09:30 | Flywheel doctor (midday) | `bin/flywheel-doctor.sh` | `sicq-latest.json` updated | — |
| 15:00 | Root-cause enforcer | `bin/root-cause-enforcer.sh` | Tickets for repeated patterns | — |
| 17:00 | Flywheel doctor (evening) | `bin/flywheel-doctor.sh` | `sicq-latest.json` updated | — |

---

## Algorithm Reference (all agents must know these exist)

Every agent and Kai should know these algorithms exist. Read the protocol before working on that domain.

| Algorithm | What it measures | Protocol file | Runs at |
|-----------|-----------------|---------------|---------|
| **SICQ** | Process compliance (is the right process being followed?) | `kai/protocols/PROTOCOL_KAI_METRICS.md` | 05:30, 09:30, 17:00 MT daily |
| **OMP** | Outcome quality (is it actually working?) | `kai/protocols/PROTOCOL_OMP.md` | 06:00 MT daily |
| **Kai SICQ** | Kai executive protocol compliance (5 checks × 20 pts) | `kai/protocols/PROTOCOL_KAI_METRICS.md` | Same as SICQ |
| **Kai OMP** | 5-dimensional: DQI, OSS, KRI, AAS, BIS | `kai/protocols/PROTOCOL_KAI_METRICS.md` | 06:00 MT daily |
| **ARIC** | 7-phase self-improvement research cycle | `kai/protocols/AGENT_RESEARCH_CYCLE.md` | Inside flywheel at 04:30 |
| **Flywheel** | Self-improve state machine (research→implement→verify) | `kai/protocols/FLYWHEEL_RECOVERY.md` | 04:30 MT daily |
| **WAI** | Weakness Aging Index — weakness decay detection | `kai/AGENT_ALGORITHMS.md` (WAI section) | Inside doctor |
| **Cross-agent review** | Adversarial peer review, echo chamber prevention | `bin/cross-agent-review.sh` comments | Saturday 06:45 MT |
| **CLEAR** | Enterprise agentic AI eval (Cost/Latency/Efficacy/Assurance/Reliability) | `kai/protocols/PROTOCOL_KAI_METRICS.md` (research section) | Reference only |

**Agent-specific OMP metrics (what each agent is scored on):**
- Nel: **APS** (Alert Precision Score) — true alerts / (true + false positive alerts)
- Sam: **DSS** (Deploy Stability Score) — 1 − (regressions / deploys)
- Ra: **EQS** (Engagement Quality Score) — CTOR × diversity × retention
- Aether: **ASR** (Adversarial Survival Rate) — Phase 1 recommendation unchanged by Phase 2
- Dex: **PAR** (Pattern Actionability Rate) — acted clusters / total clusters
- Kai: **DQI + OSS + KRI + AAS + BIS** (5-dimensional composite)

---

## What Memory Writes Happen After Each Event

Every agent runner and scheduled script must write to memory after completing. This is constitutional (AGENT_ALGORITHMS.md §MEMORY UPDATE).

| Event | Memory write |
|-------|-------------|
| Nel/Sam/Aether run | ACTIVE.md updated (freshness marker) |
| Flywheel cycle | `self-improve-state.json` + `evolution.jsonl` + `aric-latest.json` |
| Flywheel doctor | `sicq-latest.json` + `flywheel-doctor-latest.json` |
| OMP measurement | `omp-latest.json` + `omp-history.jsonl` + `omp-summary.json` |
| Memory snapshot (06:15) | SQLite memory engine: today's SICQ + OMP scores |
| Morning report | `morning-report.json` + HQ feed entry |
| Kai session end | `KAI_BRIEF.md` + `KAI_TASKS.md` + KNOWLEDGE.md |
| Nightly consolidation | SQLite promotions + KNOWLEDGE.md update |

---

## Simulation Status (as of 2026-04-21)

Simulation runs nightly at **06:30 MT** via `dispatch simulate`.
Last result: **8 failures** (persistent since 2026-04-14).

**Active failures requiring action:**
| Failure | Status | Severity |
|---------|--------|----------|
| `FAIL:runner:ra:exit-2` | Persistent since Apr 13, 8 days | **P0** — Ra runner broken |
| `FAIL:render:morning-report*` (3 variants) | Persistent since Apr 14 | P1 — rendering not verified |
| `FAIL:render:hq-state.json-unbound` | Persistent | P1 — HQ state missing |
| `FAIL:render:remote-access.json-unbound` | Persistent | P1 |
| `FAIL:render:aether-default-balance` | Persistent | P2 |
| `FAIL:regression:1-issues` | Persistent | P2 |

Tickets must be opened for all of these. Ra runner P0 is the most urgent.

---

## Agent Creation

When creating a new agent, use: `docs/AGENT_CREATION_PROTOCOL.md` (v3.0).
The protocol is complete and battle-tested across 8 agents. Read it fully before building.
Key requirements: PLAYBOOK.md, GROWTH.md, evolution.jsonl, self-improve hook, ARIC cycle integration, launchd plist, ACTIVE.md freshness marker.
