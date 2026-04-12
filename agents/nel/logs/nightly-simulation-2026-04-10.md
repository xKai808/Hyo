# Nightly simulation — 2026-04-10 (for overnight → 2026-04-11 morning)

**Generated:** 2026-04-10 22:14 MT
**Horizon:** next ~10 hours (until Hyo wakes around 08:00 MT)
**Method:** walk chronologically through every scheduled event and every cron-adjacent system, identify failure modes, flag anything Kai cannot fix on its own.

---

## Timeline

### T+0 — now (22:14 MT) — Kai end-of-day work
- Rewriting cipher.sh with persistent memory ✓
- Building OVERNIGHT_QUEUE.md ✓
- Consolidating KAI_BRIEF and KAI_TASKS ✓
- Updating nightly-consolidation/simulation to daily cron ✓
- Pre-staging aurora migration (synthesize_claude.py)
- Initializing git + first commit

### T+48m — 23:01 MT — cipher-hyo-hourly first overnight fire
- Runs `kai/cipher.sh` via the scheduled task
- Expected: clean run, 0 findings (repo is .git-less currently so .env gitignore check is skipped; .secrets/ is already mode 700; founder token is contained)
- **Failure mode:** if git is initialized by then, cipher will check for `.env` files against `git check-ignore`. No `.env` files exist in the repo, so still clean.
- **Failure mode:** if gitleaks/trufflehog are not on PATH, cipher will file a P2 "not installed" task. Last terminal session shows Hyo already installed them via brew.
- **Outcome:** clean or single P2 if tools are missing

### T+1h46m — 23:50 MT — nightly-consolidation fires (first under new daily cron)
- This task exists as a scheduled task but it's essentially a prompt to Kai to re-run consolidation. Since Hyo is asleep, it will auto-run in a fresh session.
- The task will read KAI_BRIEF, KAI_TASKS, OVERNIGHT_QUEUE and update them.
- **Failure mode:** if Cowork isn't running when the cron fires, the task queues until the app is next opened. Non-fatal.
- **Outcome:** either runs or queues

### T+1h — 23:01 MT — nightly-simulation fires
- Wait — this is scheduled for 23:01 which is before consolidation's 23:50. That's the existing order (simulation first, then consolidation). Reverse of what my OVERNIGHT_QUEUE said but fine.
- Walks through the same exercise this file is doing for the next night
- **Outcome:** produces a new simulation log for 2026-04-11

### T+2h to T+5h — every hour on the :01 — cipher repeats
- 23:01, 00:01, 01:01, 02:01, 03:01, 04:01, 05:01, 06:01, 07:01
- Each run will reconcile findings against state.json; if the same P2 "gitleaks not installed" keeps firing it will increment runsFailing but not spam KAI_TASKS (idempotent marker)
- **Failure mode:** if the token-leak grep picks up a false positive (e.g., the token value happens to be in a log file), it will escalate to P0. Mitigation: the grep excludes `.git`, `.secrets`, `node_modules`, `logs`, `memory`, `kai`.
- **Outcome:** silence

### T+4h46m — 03:00 MT — aurora-hyo-daily fires
- Runs `newsletter/newsletter.sh`
- Stage 1 (gather): hits ~15 free sources, probably succeeds
- Stage 2 (synthesize): **THIS IS WHERE IT FAILS TODAY**. No LLM backend configured.
- Pre-stage tonight: `newsletter/synthesize_claude.py` wraps `claude -p` subprocess. `newsletter.sh` will be updated to call it when `HYO_SYNTH_BACKEND=claude-code` is set.
- **Failure mode 1:** `claude` CLI not on PATH used by the scheduler. Result: subprocess fails, synthesize.py exits non-zero, newsletter.sh logs the error, no newsletter produced.
- **Failure mode 2:** Claude Code subprocess takes too long or hits subscription limits. Mitigation: set a 10-minute timeout.
- **Failure mode 3:** the render step assumes synthesize output format — if the Claude subprocess returns a different format, render breaks. Mitigation: the wrapper parses the Claude output into the same JSON schema the old synthesize produced.
- **Outcome range:** clean newsletter ✓ OR detailed log entry showing exactly why it failed (better than silent fail)

### T+5h50m — 04:04 MT — sentinel-hyo-daily fires
- Runs `kai/sentinel.sh` via scheduled task
- Check battery:
  - P0 aurora-ran-today → PASS if migration worked, FAIL otherwise
  - P0 api-health-green → PASS (prod hasn't changed)
  - P0 founder-token-integrity → PASS (mode 600)
  - P1 scheduled-tasks-fired → depends on whether newsletter.sh wrote a log
  - P1 manifest-valid-json → PASS (we haven't touched manifests tonight)
  - P1 secrets-dir-permissions → PASS (700)
  - P1 repo-is-git → PASS if git was initialized tonight
  - P2 kai-dispatcher-present → PASS (bin/kai.sh exists and is executable)
  - P2 task-queue-size → PASS (P0 count is 3)
- **Failure mode:** sentinel's state.json was initialized but hasn't seen a real run yet. First run will bootstrap cleanly since the script handles empty state.
- If aurora failed: sentinel files a P0 task (first occurrence) — no notification yet because `runsFailing=1`. Second day in a row = notification.
- **Outcome:** report written to `kai/logs/sentinel-2026-04-11.md` only if there are findings.

### T+8h to T+10h — 07:00-08:00 MT — Hyo wakes
- Reads OVERNIGHT_QUEUE.md + any sentinel/cipher reports
- Opens Cowork, asks Kai for morning status
- Kai (fresh session) reads KAI_BRIEF → sees "Shipped overnight" section → provides status in 3 lines

---

## Pre-emptive issues flagged for Hyo before sleep

### Issue A — Aurora migration correctness
**Risk level:** HIGH
**What:** synthesize_claude.py must produce output in the exact format the render stage expects. I can write a wrapper that reads the same input contract and produces the same output contract, but I cannot verify without running it end-to-end against real gather output, which requires either (1) triggering newsletter.sh manually or (2) waiting for 03:00.
**Mitigation:** I will write the wrapper with defensive parsing and robust logging. If the 03:00 run fails, the log will tell us exactly why.
**Action Hyo must take:** NONE tonight. Tomorrow morning, if newsletter is missing, run `kai news logs` to see what happened.

### Issue B — Claude CLI path in scheduled context
**Risk level:** MEDIUM
**What:** macOS launchd cron jobs often run with a minimal PATH that does not include `/usr/local/bin` or wherever `claude` lives.
**Mitigation:** In synthesize_claude.py, probe multiple likely locations for the `claude` binary and fall back with a clear error.
**Action Hyo must take:** If tomorrow's newsletter is missing and the log says "claude: command not found", either (a) add the full path to the scheduled task env, or (b) install Claude CLI via `npm i -g @anthropic-ai/claude-code` if not already.

### Issue C — Cipher .gitleaksignore path
**Risk level:** LOW
**What:** cipher.sh references `.gitleaksignore` but the file doesn't exist. gitleaks will warn but not fail.
**Mitigation:** create an empty `.gitleaksignore` so the warning stops.
**Action Hyo must take:** none.

### Issue D — Git init side effects
**Risk level:** LOW
**What:** Initializing git in a folder that was never a repo means the first commit is going to be huge (everything at once). That's fine, but it may cause `gitleaks detect` to find old test tokens in files it had never scanned before (the current token is in `.secrets/` which is gitignored, so safe).
**Mitigation:** write `.gitignore` FIRST, then `git init`, then `git add -A`, then commit. This ensures nothing in `.secrets/` ever enters git history.
**Action Hyo must take:** none.

---

## Nothing else Hyo needs to do tonight

Kai handles:
- Cipher runs: automatic
- Sentinel run: automatic
- Aurora run: automatic (will either work or log the failure)
- Overnight consolidation: automatic
- Overnight simulation: automatic
- Morning status: ready when Hyo opens Cowork

Hyo sleeps. Kai takes it from here.
