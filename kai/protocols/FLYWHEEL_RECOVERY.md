# FLYWHEEL_RECOVERY.md — Self-Healing Protocol for the Self-Improvement System
**Version:** 1.0  
**Date:** 2026-04-21  
**Owner:** Kai  
**Enforcer:** bin/flywheel-doctor.sh (runs daily 09:00 MT + 14:00 MT via kai-autonomous.sh)

---

## Core Principle

**Every detected issue has a recovery path. Nothing is left hanging.**

When a problem is found in the self-improvement flywheel, this protocol defines what happens next — in order of severity. The flywheel-doctor.sh script implements these recovery steps automatically. Human escalation is the last resort, not the default.

Recovery hierarchy:
1. **Automated fix** — script can repair it without human input
2. **State reset** — return agent to safe known-good state (W1/research)
3. **P0/P1 ticket + Kai signal** — Kai is aware and will address next session
4. **Hyo inbox entry** — only for issues Kai itself cannot resolve

---

## Issue → Recovery Map

### Issue 1: `self-improve-state.json` corrupt or missing required fields
**Detection:** `check_state_integrity()` — JSON parse fails or missing keys  
**Auto-fix:** Reset to `{"current_weakness":"W1","stage":"research","cycles":0,"failure_count":0}`  
**Ticket:** P1 — "Doctor: reset corrupt self-improve state for `<agent>`"  
**Acceptable:** Yes — safe state, no data loss, next cycle picks up from W1

### Issue 2: `GROWTH.md` missing
**Detection:** `check_growth_md()` — file not found  
**Auto-fix:** Create minimal bootstrap with one W1 placeholder item  
**Ticket:** P1 — "Doctor: auto-bootstrapped GROWTH.md — needs real weakness assessment"  
**Follow-up required:** A Kai session must review the agent's logs/tickets and write real W1/W2/W3 entries. The bootstrap is not a real assessment.

### Issue 3: `GROWTH.md` has no parseable W/E items (possibly corrupt)
**Detection:** `check_growth_md()` — regex finds 0 `### W\d+:` or `### E\d+:` headers  
**Auto-fix:** None (risk of data loss)  
**Ticket:** P1 — "Doctor: GROWTH.md has no parseable weakness items — review needed"  
**Escalation:** Kai reviews manually next session

### Issue 4: Agent stuck on same weakness for ≥2 days with `failure_count ≥ 3`
**Detection:** `check_stuck_weakness()` — failure_count ≥ MAX_RETRIES AND days_since_last_run ≥ 2  
**Auto-fix:** Force-advance to next unresolved weakness in GROWTH.md, reset failure_count to 0  
**Ticket:** P1 — "Doctor: force-advanced `<agent>` from stuck `<wid>` to `<next_wid>`"  
**Logic:** A weakness that fails 3 times AND doesn't advance for 2 days is permanently stuck under current conditions. Moving forward is better than spinning indefinitely.

### Issue 5: Agent in `implement` stage but no research file for today
**Detection:** `check_research_implement_mismatch()` — stage=implement but research file missing  
**Auto-fix:** Reset stage to `research` (safe rollback)  
**No ticket:** Low severity, normal on midnight boundary  
**Logic:** Research file was from yesterday (midnight boundary bug). Resetting to research causes it to regenerate today.

### Issue 6: `KNOWLEDGE.md` not updated in >7 days
**Detection:** `check_knowledge_stagnation()` — mtime > 7 days  
**Auto-fix:** None  
**Ticket:** P2 — "Doctor: KNOWLEDGE.md stale — flywheel not persisting knowledge"  
**Escalation:** Written to Kai signal bus — investigate `persist_knowledge()` failures in self-improve.log

### Issue 7: `self-improve.log` not updated in >48 hours
**Detection:** `check_flywheel_running()` — mtime > 48h  
**Auto-fix:** None (cannot trigger the daemon from within the daemon)  
**Ticket:** P1 — "Doctor: flywheel not running — check kai-autonomous.sh 08:00 dispatch"  
**Escalation:** Written to Kai signal bus — check whether kai-autonomous.sh is running via `launchctl list | grep hyo`

### Issue 8: WAI — Weakness aging past threshold by severity
**Detection:** `check_weakness_ages()` — creation date parsed from Status line, age > threshold (P0:7d, P1:14d, P2:30d)  
**Auto-fix:** None  
**Ticket:** P1 or P2 based on weakness severity  
**Logic:** Old weaknesses that aren't advancing indicate either: the research is failing, the implementation is too complex, or the weakness was poorly specified. Ticket prompts Kai to investigate.

### Issue 9: SICQ score < 40 for an agent
**Detection:** `check_sicq_scores()` — component score below critical threshold  
**Auto-fix:** None  
**Ticket:** P1 — "Doctor: SICQ critically low for `<agent>` — self-improve cycle degraded"  
**Follow-up:** Kai reads `kai/ledger/sicq-latest.json` to understand which components are failing

### Issue 10: No weaknesses resolved in >14 days
**Detection:** `check_resolution_stagnation()` — evolution.jsonl has no `weakness_resolved` entries in window  
**Auto-fix:** None  
**Ticket:** P1 — "Doctor: flywheel has not resolved any weakness in 14d — check verify and implement stages"  
**Escalation:** Written to Kai escalations (Hyo inbox if Kai also can't resolve)

---

## Escalation to Hyo — When and How

Hyo is notified **only** when:
- Kai cannot resolve the issue autonomously (requires physical access, architectural decision, or spending)
- Multiple P0 issues detected in same doctor run
- SICQ average < 40 for 3 consecutive days (system failure mode)
- The flywheel log is >96h stale (longer than 2 missed doctor runs)

Notification method: `kai/ledger/hyo-inbox.jsonl` — surfaced at top of next Kai session during hydration.

Format: Subject line + body with specific actions required. Never vague — always states exactly what Kai needs from Hyo.

---

## Manual Recovery Commands

```bash
# Run doctor manually (check + fix + report)
kai doctor

# Run for specific checks only
HYO_ROOT=~/Documents/Projects/Hyo bash ~/Documents/Projects/Hyo/bin/flywheel-doctor.sh

# Force-reset an agent's state (emergency — only if doctor hasn't fixed it)
echo '{"current_weakness":"W1","stage":"research","cycles":0,"failure_count":0,"improvements":[],"last_run":""}' \
  > ~/Documents/Projects/Hyo/agents/<agent>/self-improve-state.json

# Inject Hyo feedback directly into an agent's GROWTH.md
kai inject-feedback <agent> "description of the issue" P1

# Run one agent's self-improve cycle manually
kai self-improve nel

# Run all agents' cycles
kai self-improve all

# Check SICQ scores
cat ~/Documents/Projects/Hyo/kai/ledger/sicq-latest.json | python3 -m json.tool

# Check doctor's last run
cat ~/Documents/Projects/Hyo/kai/ledger/flywheel-doctor-latest.json | python3 -m json.tool
```

---

## Schedule

| Time (MT) | Script | Purpose |
|-----------|--------|---------|
| 08:00 | `agent-self-improve.sh all` | Run flywheel for all agents |
| 09:00 | `flywheel-doctor.sh` | Check health, auto-fix, compute SICQ |
| 14:00 | `flywheel-doctor.sh` | Midday check — catch afternoon drift |

---

## What Doctor Does NOT Fix (Requires Kai)

- Weaknesses that are poorly specified (vague, untestable) — Kai rewrites them
- GROWTH.md bootstrap items (placeholder W1) — Kai replaces with real assessment
- Research files where Claude Code returns consistently poor output — Kai improves the research prompt
- Protocol changes needed to improve the flywheel itself — Kai files a proposal in `kai/proposals/`

---

*When this protocol is updated, bump the version and log to evolution.jsonl.*
