# ORGANIZATION_MAP.md
# Owner: Dex | Last updated: 2026-05-06 | Status: AUTHORITATIVE
#
# This is the canonical file location guide for the Hyo project.
# When you don't know where a file should go, check here first.
# When you move a file, update this map AND update all cross-references.

---

## Quick Reference — "Where does X go?"

| What | Where | Owner |
|------|-------|-------|
| Session memory (current state) | `KAI_BRIEF.md` | Kai |
| CEO task queue | `KAI_TASKS.md` | Kai |
| Permanent knowledge layer | `kai/memory/KNOWLEDGE.md` | Kai |
| Hyo's hard rules and preferences | `kai/memory/TACIT.md` | Kai |
| Pre-session machine-readable handoff | `kai/ledger/session-handoff.json` | Kai |
| Pre-computed system state snapshot | `kai/ledger/verified-state.json` | bin/kai-session-prep.sh |
| Protocols for specific workflows | `kai/protocols/PROTOCOL_*.md` | Kai |
| Agent execution protocols | `agents/<name>/PROTOCOL_*.md` | that agent |
| Agent current tasks | `agents/<name>/ledger/ACTIVE.md` | that agent |
| Agent playbook (how it works) | `agents/<name>/PLAYBOOK.md` | that agent |
| Agent growth plan | `agents/<name>/GROWTH.md` | that agent |
| Agent priorities | `agents/<name>/PRIORITIES.md` | that agent |
| Agent runner script | `agents/<name>/<name>.sh` | that agent |
| Agent daily logs | `agents/<name>/logs/` | that agent |
| Agent archive (old logs/reports) | `agents/<name>/archive/` | Dex |
| Agent research output | `agents/<name>/research/` | that agent |
| Agent manifest (registry spec) | `agents/manifests/<name>.hyo.json` | Dex |
| Hyo Research PDF protocol | `kai/protocols/PROTOCOL_HYO_RESEARCH_PDF.md` | Kai |
| Research PDF base script | `/sessions/gifted-happy-cori/build_marina_pdf.py` | Kai |
| Published research docs (html+md) | `agents/sam/website/docs/research/` | Sam |
| Website frontend | `agents/sam/website/` | Sam |
| Website (symlink) | `website/` → `agents/sam/website/` | Sam |
| Newsletter pipeline | `agents/ra/pipeline/` | Ra |
| Newsletter output | `agents/ra/output/` | Ra |
| NFT registry specs | `NFT/` | Kai |
| Queue pending jobs | `kai/queue/pending/` | Kai |
| Queue completed jobs | `kai/queue/completed/` (auto-archived after 7d) | Kai |
| Queue archive (monthly zips) | `kai/queue/archive/` | Kai |
| Ledger JSONL data | `kai/ledger/*.jsonl` | Kai |
| Ledger text logs | `kai/ledger/*.log` (rotated at 5MB) | Kai |
| Ledger log archive | `kai/ledger/archive/` | Dex |
| Tickets | `kai/tickets/tickets.jsonl` | Kai |
| Security secrets | `agents/nel/security/` | Nel |
| Secrets (backward compat symlink) | `.secrets/` → `agents/nel/security/` | Nel |
| Legacy design docs | `docs/legacy/` | Dex |
| General docs | `docs/` | Kai |
| Competitive intel | `lab/competitive-intel/` | Kai/Ra |

---

## Directory Layout — Canonical Locations

```
Hyo/
├── CLAUDE.md                    ← session bootstrap for ALL Claude instances
├── KAI_BRIEF.md                 ← Kai session memory (current state, shipped today)
├── KAI_TASKS.md                 ← CEO task queue (active items only)
├── KAI_BRIEF-archive-*.md       ← archived older BRIEF sections
├── KAI_TASKS-done-archive-*.md  ← archived completed tasks
├── ORGANIZATION_MAP.md          ← THIS FILE — canonical location guide
│
├── bin/                         ← ALL automation scripts
│   ├── kai.sh                   ← dispatcher (alias: kai)
│   ├── kai-session-prep.sh      ← pre-computes verified-state.json (runs every 15min)
│   ├── kai-autonomous.sh        ← master daemon (runs every 15min via launchd)
│   ├── weekly-maintenance.sh    ← Saturday cleanup (calls log-rotation.sh)
│   ├── log-rotation.sh          ← text log rotation + queue archive + cleanup
│   ├── daily-agent-report.sh    ← publishes agent daily reports to feed
│   ├── generate-morning-report.sh ← 05:00 morning report
│   ├── agent-growth.sh          ← shared growth execution (sourced by all runners)
│   ├── ticket.sh                ← ticket system
│   └── [all other bin scripts]
│
├── agents/
│   ├── manifests/               ← agent registry specs (*.hyo.json)
│   │   ├── dex.hyo.json         ← Dex: system memory + organization
│   │   ├── nel.hyo.json         ← Nel: security + QA
│   │   ├── sam.hyo.json         ← Sam: engineering
│   │   ├── ra.hyo.json          ← Ra: newsletter/content
│   │   ├── aether.hyo.json      ← Aether: financial analysis
│   │   ├── aurora.hyo.json      ← Aurora: newsletter (Ra sub-agent)
│   │   ├── cipher.hyo.json      ← Cipher: security (Nel sub-agent)
│   │   ├── sentinel.hyo.json    ← Sentinel: QA (Nel sub-agent)
│   │   └── hyo.hyo.json         ← Hyo (CEO profile)
│   │
│   ├── aether/                  ← AetherBot (financial analysis)
│   │   ├── PROTOCOL_DAILY_ANALYSIS.md  ← v2.5 analysis protocol (CANONICAL)
│   │   ├── PLAYBOOK.md          ← how Aether works
│   │   ├── GROWTH.md            ← weaknesses and improvements
│   │   ├── PRIORITIES.md        ← current priorities
│   │   ├── aether.sh            ← daily runner
│   │   ├── analysis/            ← running scripts (kai_analysis.py etc.) + latest outputs
│   │   │   ├── kai_analysis.py  ← ACTIVE: main analysis runner (do not move)
│   │   │   ├── gpt_crosscheck.py ← ACTIVE: GPT cross-check runner
│   │   │   ├── gpt_factcheck.py ← ACTIVE: fact-check runner
│   │   │   ├── kai_telegram.py  ← ACTIVE: Telegram bot
│   │   │   ├── Analysis_*.txt   ← daily output (archived >30d to archive/)
│   │   │   ├── GPT_*.txt        ← GPT cross-check output (archived >30d)
│   │   │   └── Simulation_*.txt ← simulation output (archived >30d)
│   │   ├── archive/             ← compressed old analysis + log files
│   │   ├── code-versions/       ← bot version history (AetherBot_MASTER_v*.py)
│   │   ├── docs/                ← documentation and briefing files
│   │   ├── ledger/              ← ACTIVE.md, api-usage.jsonl
│   │   └── logs/                ← self-review logs (archived >60d)
│   │
│   ├── nel/                     ← Nel: security + QA
│   │   ├── nel.sh               ← runner
│   │   ├── cipher.sh            ← security sub-agent
│   │   ├── sentinel.sh          ← QA sub-agent
│   │   ├── PLAYBOOK.md, GROWTH.md, PRIORITIES.md
│   │   ├── consolidation/       ← nightly consolidation scripts
│   │   ├── logs/                ← nel logs (archived >60d)
│   │   ├── archive/             ← compressed old logs
│   │   ├── memory/              ← sentinel + cipher state
│   │   └── security/            ← secrets (.secrets/ symlink points here)
│   │
│   ├── sam/                     ← Sam: engineering + website
│   │   ├── sam.sh               ← runner
│   │   ├── PLAYBOOK.md, GROWTH.md, PRIORITIES.md
│   │   ├── logs/                ← sam logs
│   │   ├── archive/             ← compressed old logs
│   │   ├── mcp-server/          ← MCP server code
│   │   └── website/             ← Vercel-deployed frontend (also at website/ symlink)
│   │       ├── hq.html          ← HQ dashboard (single-page app)
│   │       ├── data/            ← feed.json, research-archive.json, aether-metrics.json
│   │       ├── daily/           ← daily digest pages (YYYY-MM-DD.html)
│   │       ├── docs/research/   ← published research documents (html + md)
│   │       └── api/             ← Vercel serverless functions
│   │
│   ├── ra/                      ← Ra: newsletter product manager
│   │   ├── ra.sh                ← runner
│   │   ├── PLAYBOOK.md, GROWTH.md, PRIORITIES.md
│   │   ├── pipeline/            ← newsletter pipeline (also at newsletter/ symlink)
│   │   ├── output/              ← newsletter output (also at newsletters/ symlink)
│   │   ├── research/            ← Ra's research
│   │   ├── logs/                ← ra logs
│   │   └── archive/             ← compressed old logs
│   │
│   ├── dex/                     ← Dex: system memory + organization
│   │   ├── dex.sh               ← runner
│   │   ├── PLAYBOOK.md, GROWTH.md, PRIORITIES.md
│   │   ├── protocols/
│   │   │   ├── PROTOCOL_ORGANIZATION.md  ← organization mandate + audit protocol
│   │   │   └── PROTOCOL_DEX_SELF_IMPROVEMENT.md
│   │   ├── logs/                ← organization audit reports (YYYY-MM-DD.md)
│   │   ├── archive/             ← compressed old logs
│   │   └── ledger/              ← ACTIVE.md
│   │
│   └── hyo/                     ← Hyo CEO profile (not an autonomous agent)
│       ├── hyo.sh               ← profile runner
│       └── ledger/ACTIVE.md
│
├── kai/                         ← CEO workspace
│   ├── AGENT_ALGORITHMS.md      ← THE CONSTITUTION (read only for arch decisions)
│   ├── protocols/               ← Kai's protocols
│   │   ├── PROTOCOL_HYO_RESEARCH_PDF.md  ← how to create Hyo Research PDFs
│   │   ├── EXECUTION_GATE.md    ← 5-question pre-action gate
│   │   ├── VERIFICATION_PROTOCOL.md ← post-action verification
│   │   ├── SESSION_CONTINUITY_PROTOCOL.md
│   │   └── [other protocols]
│   ├── ledger/                  ← Kai's operational data
│   │   ├── ACTIVE.md            ← Kai's current tasks
│   │   ├── verified-state.json  ← pre-computed truth (15min refresh)
│   │   ├── session-handoff.json ← session-to-session handoff
│   │   ├── known-issues.jsonl   ← issue patterns to watch
│   │   ├── session-errors.jsonl ← Kai's mistake ledger (RECALL SYSTEM)
│   │   ├── hyo-inbox.jsonl      ← Hyo → Kai messages
│   │   ├── guidance.jsonl       ← Kai → agent guidance log
│   │   ├── *.log                ← text logs (rotated at 5MB by log-rotation.sh)
│   │   └── archive/             ← compressed old logs (by log-rotation.sh)
│   ├── memory/                  ← Kai's memory layers
│   │   ├── KNOWLEDGE.md         ← permanent knowledge (Layer 2)
│   │   ├── TACIT.md             ← Hyo's preferences (Layer 3)
│   │   ├── MEMORY_SYSTEM.md     ← memory architecture doc
│   │   ├── daily/               ← daily notes (written during session)
│   │   ├── feedback/            ← Hyo feedback uploads
│   │   ├── patterns/            ← pattern library
│   │   └── agent_memory/        ← SQLite memory engine
│   ├── queue/                   ← command queue system
│   │   ├── pending/             ← jobs waiting to run
│   │   ├── running/             ← job currently executing
│   │   ├── completed/           ← finished jobs (archived after 7d by log-rotation.sh)
│   │   ├── failed/              ← failed jobs (review manually)
│   │   ├── archive/             ← monthly tar.gz of old completed jobs
│   │   ├── exec.sh              ← queue execution wrapper
│   │   ├── worker.sh            ← queue worker daemon
│   │   └── submit.py            ← Python submit helper
│   ├── tickets/                 ← ticket system
│   │   ├── tickets.jsonl        ← active tickets (compacted weekly)
│   │   ├── tickets.db           ← SQLite ticket DB
│   │   └── archive/             ← archived resolved tickets
│   ├── dispatch/                ← Dispatch conversation transcripts (synced daily 16:00)
│   ├── proposals/               ← algorithm evolution proposals
│   ├── research/                ← Kai's research files
│   │   ├── briefs/              ← research briefs
│   │   ├── entities/            ← entity research
│   │   ├── topics/              ← topic research
│   │   └── raw/                 ← raw research (archived >30d)
│   ├── schemas/                 ← JSON schemas
│   ├── templates/               ← report templates
│   ├── signals/                 ← event bus signals
│   ├── tools/                   ← tool definitions
│   └── context/                 ← session context snapshots
│
├── NFT/                         ← registry specs (blockchain integration)
│   ├── HyoRegistry.sol
│   ├── HyoRegistry_Notes.md
│   ├── HyoRegistry_CreditSystem.md
│   ├── HyoRegistry_Marketplace.md
│   └── HyoRegistry_Reviews.md
│
├── docs/                        ← general documentation
│   └── legacy/                  ← old/historical files (pre-v1 design)
│
├── lab/                         ← independent research space
│   ├── LAB_BRIEF.md
│   ├── competitive-intel/
│   └── research/
│
└── [Symlinks — do not break these]
    ├── website/     → agents/sam/website/
    ├── newsletter/  → agents/ra/pipeline/
    ├── newsletters/ → agents/ra/output/
    ├── .secrets/    → agents/nel/security/
    └── PROTOCOL_DAILY_ANALYSIS.md → agents/aether/PROTOCOL_DAILY_ANALYSIS.md
```

---

## Anti-Patterns to Avoid

| Anti-pattern | Correct approach |
|---|---|
| Scripts/plists in `analysis/` dir | Keep runners in `agents/<name>/` root |
| Secrets anywhere outside `agents/nel/security/` | Always use `.secrets/` symlink |
| Text log > 5MB without rotation | log-rotation.sh handles this weekly |
| Completed queue jobs older than 7 days | log-rotation.sh archives to monthly zip |
| Analysis files > 30 days in `analysis/` | log-rotation.sh archives to `archive/` |
| Duplicate names across `website/` and `agents/sam/website/` | Dex dual-path check enforces |
| Research PDFs generated without reading PROTOCOL_HYO_RESEARCH_PDF.md | Always read first |
| Moving a file without updating cross-references | Update ALL refs + this map |

---

## File Classification Legend

Used by Dex in organization audits:

- `NECESSARY` — actively used, no overlap, clear purpose, has a trigger
- `REDUNDANT` — duplicates another file's content or purpose (→ merge)
- `SILOED` — no inbound references, no trigger (→ remove or wire)
- `STALE` — not modified >30d, no active consumers (→ archive)
- `PATCHWORK` — symptom fix, not root-cause fix (→ flag for systemic fix)
- `INTEGRATIVE` — connects multiple subsystems (→ protect carefully)
- `CONSOLIDATE-CANDIDATE` — similar purpose, safe to merge

---

*Maintained by Dex. Kai updates on reorganization. Never let this go stale.*
*Trigger: any file move or restructure → update this map + cross-references*
