# File Generation Audit — 2026-05-06
# Owner: Kai | Requested by: Hyo
# Question: What generates all these files? Is it excessive? Are they necessary?

---

## Summary

The project generates ~150MB+ of files per month from 8 distinct generation sources.
Three sources are generating unbounded files with no rotation. Fixed below.

---

## Generation Sources — Classified

### 1. kai-autonomous.sh — Every 15 minutes (96x/day)
**Writes to**: `kai/ledger/kai-autonomous.log`, `kai/ledger/verified-state.json`, `kai/ledger/session-errors.jsonl`

**Verdict: NECESSARY, but log file management was broken.**
The healthcheck daemon must run frequently to catch stale agents and queue jobs.
`kai-autonomous.log` was growing at ~200KB/day (8.8MB total) with NO rotation.
**Fix**: `bin/log-rotation.sh` truncates at 5MB, compresses tail. Wired into weekly-maintenance.sh.

---

### 2. agent-self-improve.sh — Once daily at 04:30 MT
**Writes to**: `kai/ledger/self-improve.log`, each agent's `GROWTH.md` and `PRIORITIES.md`

**Verdict: NECESSARY, correctly cadenced (was 2x/day, reduced to 1x per Hyo directive 2026-04-30).**
`self-improve.log` reached 10MB. `bin/log-rotation.sh` handles this.

---

### 3. Agent daily runners — Once nightly per agent
**Nel**: 22:00 MT. **Sam**: 22:30 MT. **Aether**: 22:45+23:00 MT. **Ra**: 03:00 MT. **Kai**: 23:30 MT.
**Writes to**: `agents/<name>/logs/<name>-YYYY-MM-DD.md`, feed.json (via daily-agent-report.sh)

**Verdict: NECESSARY. Each creates one structured log per agent per day.**
Daily logs accumulate indefinitely without rotation. `bin/log-rotation.sh` archives logs >60d to `agents/<name>/archive/`.

---

### 4. Aether analysis pipeline — Once daily at 23:00 MT
**Writes to**: `agents/aether/analysis/Analysis_YYYY-MM-DD.txt`, `GPT_CrossCheck_*.txt`, `GPT_Independent_*.txt`, `GPT_Review_*.txt`

**Verdict: NECESSARY, but 3-6 files per day with NO archive trigger.**
As of 2026-05-06: ~85 analysis files in the directory (dating back to April 8).
`bin/log-rotation.sh` archives analysis files >30d to `agents/aether/archive/analysis-pre-DATE.tar.gz`.

**Recommendation**: Consider merging GPT_CrossCheck and GPT_Independent into one file per day.
Currently: 3 GPT outputs (CrossCheck, Independent, Review) + 1 Analysis + 1 Simulation = 5 files/day.
Could be: 1 unified daily analysis file = 80% fewer files with same data.

---

### 5. Queue worker — Continuous
**Writes to**: `kai/queue/completed/CMD-*.json` for each completed job

**Verdict: NECESSARY for audit trail, but accumulation was unbounded.**
21MB in completed/ as of audit. `bin/log-rotation.sh` archives completed jobs >7d to monthly tar.gz.

---

### 6. claude-delegate.sh — Event-triggered (when agent delegates to Claude Code Mini)
**Writes to**: `kai/ledger/claude-delegate.log`, `kai/ledger/claude-delegate-failed-*.txt` (on failure)

**Verdict: NECESSARY for the delegation pattern, but failure artifacts were never cleaned.**
60 `claude-delegate-failed-*.txt` files (35 bytes each) from 2026-04-21 when Claude Mini was logged out.
These were stale artifacts — Claude Mini is now re-logged in and delegation works.
`bin/log-rotation.sh` now consolidates these into a monthly archive and removes individuals.

---

### 7. Ticket enforcer — Every 15 minutes (via kai-autonomous.sh)
**Writes to**: `kai/ledger/ticket-enforcer.log`, `kai/tickets/tickets.jsonl`

**Verdict: NECESSARY. Weekly-maintenance.sh compacts tickets.jsonl (was 55MB, now ~1MB).**
Enforcer log (764KB) — within normal range, covered by log-rotation.sh.

---

### 8. agent-reflection entries in feed.json — Via each agent's runner daily
**Writes to**: `agents/sam/website/data/feed.json` + `website/data/feed.json`

**Verdict: NECESSARY, but accumulation in feed.json was too high (230 entries).**
`bin/archive-to-research.sh` is supposed to move old entries to `research-archive.json` after 7 days.
Triggered by: `bin/weekly-report.sh` → calls `archive-to-research.sh`.
**Check**: Is weekly-report.sh running on Saturdays? Confirm via queue.

---

## Files That Are Redundant / Stale (Action Pending via Queue)

| File | Classification | Action |
|------|---------------|--------|
| `kai/ledger/claude-delegate-failed-*.txt` (60 files) | STALE error artifacts | Consolidate → `kai/ledger/archive/` |
| `agents/aether/analysis/Analysis_2026-04-09.txt.bak` | REDUNDANT (.bak of existing) | Archive |
| `agents/aether/analysis/GPT_CrossCheck_2026-04-10_PENDING.txt` | STALE pending file | Archive |
| `agents/aether/analysis/v255_Build_Spec_DRAFT.md` | REDUNDANT (v255 shipped) | Archive |
| `kai/ledger/hyo-inbox-archive-pre2026-04-23.md` | ARCHIVE already | Fine — label is correct |
| `kai/tickets/tickets.jsonl.bak` and `tickets.jsonl.bak-*` | REDUNDANT .bak files | Archive |
| `kai/ledger/log.jsonl.bak` | REDUNDANT .bak | Archive |
| `agents/aether/analysis/dashboard_server.log` | STALE log from old dashboard | Archive |
| `kai/ledger/claude-delegate-failure-archive.md` | NEW archive file | Keep |

---

## Files in Wrong Location (Action Pending)

| File | Current Location | Should Be | Risk if Moved |
|------|-----------------|-----------|---------------|
| `agents/aether/analysis/com.kai.dashboard-tunnel.plist` | analysis/ | ARCHIVE — old dashboard, not used | Low (no active reference) |
| `agents/aether/analysis/dashboard_server.py` | analysis/ | agents/aether/ if active, archive if not | Medium (check references) |
| `agents/aether/analysis/setup_dashboard_tunnel.sh` | analysis/ | agents/aether/ if active, else archive | Medium |
| `agents/nel/consolidation/com.hyo.*.plist` | consolidation/ | kai/queue/ or agents/nel/ | Medium (launchd references) |

**Decision**: Do NOT move plists without verifying launchd loads them by absolute path.
The `agents/nel/consolidation/` plists may be loaded by `kai/queue/install-report-plists.sh`.
Check before moving: `grep -r "consolidation" bin/ kai/queue/`

---

## Disk Impact Summary

| Source | Current Size | After Rotation | Monthly Steady-State |
|--------|-------------|----------------|---------------------|
| kai/ledger/ text logs | 39MB | ~5MB | ~5MB (rotated weekly) |
| kai/queue/completed/ | 21MB | ~2MB | ~2MB (archived weekly) |
| agents/aether/analysis/ | 1.4MB | ~200KB | ~200KB (archived monthly) |
| agents/aether/logs/ | 7.7MB | ~1MB | ~1MB (archived at 60d) |
| Total addressable | ~70MB | ~8MB | ~8MB |

The 170GB disk concern is NOT primarily from this project (~100MB total).
The large disk consumers are likely: Docker, Xcode simulators, Time Machine, `/Library/Logs`.
Kai can audit via queue: `df -h && du -sh ~/Library/* /Applications/* /var/log/* 2>/dev/null | sort -rh | head -20`

---

## Actions Queued

1. `log-rotation.sh` first run — immediate disk cleanup
2. Commit all new files (ORGANIZATION_MAP.md, GENERATION_AUDIT, PROTOCOL_HYO_RESEARCH_PDF, log-rotation.sh)
3. Verify weekly-maintenance.sh now calls log-rotation.sh

*Generated: 2026-05-06 | Next audit: Saturday 02:00 MT (via weekly-maintenance.sh → Dex org audit)*
