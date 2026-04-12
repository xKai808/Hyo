# OVERNIGHT_QUEUE.md

**Purpose:** Prioritized checklist of everything that must happen between now (Friday 2026-04-10 ~22:14 MT) and when Hyo wakes Saturday morning. Kai executes what Kai can, flags anything truly needing Hyo's touch.

**Rules:**
- Items marked **[KAI-NOW]** are done before Hyo sleeps
- Items marked **[AUTO]** are handled by scheduled tasks or agents overnight
- Items marked **[HYO-BEFORE-SLEEP]** need a 1-line action from Hyo before bed
- Items marked **[HYO-AM]** wait until Hyo wakes

**Cadence:** Rebuilt every night at consolidation time. Last rebuild: 2026-04-10 22:14 MT.

---

## P0 — Cannot ship without these

### 1. [KAI-NOW] Ensure cipher.sh + sentinel.sh can actually run
- Status: both scripts written with persistent memory
- Verification: bash -n syntax check passes for both
- Risk if broken: sentinel 04:00 run produces no output, cipher every-hour runs produce no output
- Mechanism: `kai sentinel` and `kai cipher` via dispatcher
- **Owner: Kai — done in this session**

### 2. [KAI-NOW] Initialize git in the Hyo project
- Status: **CRITICAL** — `.git/` does not exist. All work uncommitted. Catastrophic loss risk if Mini crashes or file is accidentally deleted.
- Mechanism: `git init && git add -A && git commit -m "Initial commit: Hyo registry + agents + dispatcher"`
- Also: ensure `.gitignore` covers `.secrets/`, `node_modules/`, `kai/logs/`, `kai/memory/*.state.json`, `newsletters/*.html`
- **Owner: Kai — done in this session**

### 3. [KAI-NOW] Pre-stage aurora Claude Code migration
- Why: aurora runs at 03:00 MT (~5 hours from now) and will fail the same way it failed last night without an LLM backend. Hyo is asleep. Must be ready before next fire.
- Mechanism: Write `newsletter/synthesize_claude.py` that wraps `claude -p` subprocess per `docs/aurora-economics.md`. Point `newsletter.sh` at it via env var.
- Risk: `claude` CLI may not be on the PATH used by the scheduler. If so, the run will still fail but at least logs will tell us why.
- Mitigation: ensure `newsletter.sh` logs every stage start/end with timestamps so tomorrow's sentinel run can diagnose
- **Owner: Kai — done in this session (best effort)**

### 4. [HYO-BEFORE-SLEEP] Confirm `kai` alias works in zsh
- Status: last session Hyo ran `kai sentinel` successfully, so the alias is confirmed working
- **Owner: Hyo — already done ✓**

## P1 — Overnight automation (hands-off)

### 5. [AUTO] cipher-hyo-hourly at every :01 past
- Fires: every hour, 23:01 → 22:01 next day
- What: scans repo, auto-fixes permissions, files any findings to KAI_TASKS.md
- Memory: `kai/memory/cipher.state.json` accumulates knownIssues and trend counters
- Failure mode to watch: `cipher: P0 VERIFIED LEAK(S).` — this would mean a live credential leaked and the script exits with code 2. Log would show it.
- **Owner: cron**

### 6. [AUTO] aurora-hyo-daily at 03:00 MT
- Fires: Saturday 03:00 MT (09:00 UTC)
- What: gather → synthesize → render; outputs `newsletters/2026-04-11.{md,html}`
- Risk: synthesize stage will fail without LLM backend → item 3 above
- Failure will be caught by sentinel at 04:00 MT
- **Owner: cron**

### 7. [AUTO] sentinel-hyo-daily at 04:00 MT
- Fires: Saturday 04:04 MT (10:04 UTC)
- What: runs P0/P1/P2 check battery, files findings to KAI_TASKS.md with stable issue IDs
- Memory: `kai/memory/sentinel.state.json` tracks `runsFailing` counts — if aurora-ran-today is now on day 2 it will escalate
- Failure mode: sentinel script itself crashes → no report written → next day Kai reviews state.json for gaps
- **Owner: cron**

### 8. [AUTO] nightly-consolidation + nightly-simulation (updated to daily)
- Current schedule: cron `50 23 * * 0-4` (Sun-Thu only) and `0 23 * * 0-4`
- **Change required:** update both to `* * *` so they run every night
- **Owner: Kai — done in this session**

## P2 — Can wait until morning

### 9. [HYO-AM] Review sentinel + cipher reports
- Location: `kai/logs/sentinel-2026-04-11.md` (one file) and `kai/logs/cipher-*.log` (24 files)
- Most should be empty/silent. If sentinel wrote a report, something escalated.
- **Owner: Hyo (1 min review) or Kai (delegate via "read overnight reports" prompt)**

### 10. [HYO-AM] Decide on aurora migration result
- If `newsletters/2026-04-11.md` exists → migration worked, ship it
- If it's missing → migration failed, Kai reads the log and iterates
- **Owner: Hyo + Kai**

### 11. [HYO-AM] Confirm HYO_ANTHROPIC_API_KEY or Claude Code CLI path
- For aurora migration to actually work, the scheduler must be able to invoke `claude -p`. If Hyo has Claude Code installed with a Max subscription, this should Just Work. Otherwise we fall back to an `ANTHROPIC_API_KEY` env var on the Mini.
- **Owner: Hyo (5 min check)**

## P3 — Nice-to-have

- [HYO-AM] Consider whether to cancel X Premium ($8/mo) since it doesn't grant API access per `docs/x-api-access.md`
- [KAI-NEXT] Add `kai overnight` subcommand that prints OVERNIGHT_QUEUE.md status
- [KAI-NEXT] Add `kai postmortem` subcommand that compiles sentinel + cipher reports from the last 24h

---

## Simulation output

See `kai/logs/nightly-simulation-2026-04-10.md` for the walk-through of what will happen between now and sunrise.
