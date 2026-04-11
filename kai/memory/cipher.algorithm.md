# cipher.algorithm.md

**Who:** cipher.hyo (security agent)
**What:** The ongoing algorithm, checklist, and operating rules that cipher follows on every hourly scan.
**Updated by:** Kai. Freely editable — cipher reads this before every run.
**Read by:** `kai/cipher.sh` and Kai (Claude) when reviewing incidents.

---

## Mission

Prevent secret leaks before they reach GitHub, the public internet, or any unintended audience. Anticipatory, not reactionary. Verified > unverified.

## Philosophy

1. **Verification > volume.** A trufflehog verified leak (credential actually works) is a P0 stop-the-world event. A gitleaks pattern match (might be a secret) is informational. Do not conflate them.
2. **Auto-fix what's fixable.** Permission drift, missing `.gitignore` entries, stale `.env` files — just fix them and log. Don't wake Hyo.
3. **Learn from false positives.** Track them in state, suppress in future runs, document why in this algorithm.md.
4. **Block, don't just report.** When installed as a pre-commit hook, cipher blocks commits that would leak verified credentials. Reporting-only mode is defeat.

## Run algorithm

1. **Load state** from `kai/memory/cipher.state.json`. Initialize on first run.
2. **Load false-positive list.** Skip any issue_id matching.
3. **Run scan battery** (see below).
4. **Classify findings:**
   - Verified leak (trufflehog --only-verified) → P0
   - Pattern match (gitleaks only) → P1
   - Permission drift → auto-fix, log as P3
   - Missing gitignore → auto-fix if safe, log as P2
5. **De-duplicate:** grep KAI_TASKS.md and existing cipher-incident files for the issue hash before filing new tasks.
6. **Write state** with run result, known issues, trend counters.
7. **Emit incident report** only if P0 or P1 findings exist. Silence otherwise.
8. **Exit code:** 0 clean, 1 pattern matches, 2 verified leaks (blocks pre-commit).

## Scan battery

### Layer 1 — Pattern scanning (gitleaks)
- Covers: OpenAI keys, Anthropic keys, xAI keys, AWS keys, GitHub tokens, generic high-entropy strings
- Scope: working tree only (git history scan is separate, on-demand)
- Speed: < 5 seconds typical

### Layer 2 — Verification scanning (trufflehog)
- Covers: same as gitleaks PLUS actively tests credentials against their source API
- Scope: entire filesystem under `$HYO_ROOT`
- Speed: 5-30 seconds depending on repo size
- **This is the one that matters.** False positive rate near zero.

### Layer 3 — Filesystem hygiene
- `.secrets/` directory: must be mode 700
- `.secrets/*` files: must be mode 600
- `.env*` files: must be gitignored (except `.env.example`)
- Auto-fix if drift detected, log the correction

### Layer 4 — Token-specific checks
- `founder.token` value must NEVER appear outside `.secrets/founder.token`
- `grok-*` / `sk-*` / `xai-*` / `ghp_*` / `AKIA*` patterns in `.md`, `.txt`, or any doc file → instant P0

## Escalation

| Finding | Severity | Action |
|---|---|---|
| trufflehog verified live credential | P0 | desktop notify + block commit + file P0 in KAI_TASKS + update KAI_BRIEF blockers |
| founder token outside .secrets/ | P0 | same as above |
| gitleaks pattern match | P1 | file in KAI_TASKS, no notification |
| .env file not gitignored | P1 | auto-fix gitignore + file info |
| Permission drift on .secrets/ | P3 | auto-fix, log only |
| Tool not installed (gitleaks/trufflehog) | P2 | file task with install instructions, idempotent (once per day max) |

## Tools installation state

_(cipher tracks this in state.json under `trendCounters`)_

- **gitleaks**: checked for at every run. If missing, files task once/day with `brew install gitleaks`.
- **trufflehog**: same pattern. Install: `brew install trufflesecurity/trufflehog/trufflehog`.

## False positive learning

When Kai reviews a cipher finding and determines it's not a real leak:
- Add to `state.falsePositives` with pattern and reason
- Add to `.gitleaksignore` with a comment if it's a gitleaks false positive
- Document in this file under "Known false positives" below

**Known false positives:** _(none yet)_

## Auto-fix history

Cipher logs every auto-fix to state.json so Hyo can audit. If cipher auto-fixes the same thing 3+ times in a week, that's a signal something is actively re-breaking it — elevate to task.

## Notes for Kai (Claude) reviewing cipher output

- If you see a verified leak: stop everything, rotate the credential, update `.secrets/`, redeploy anywhere it was set as an env var, commit the rotation. This is a P0 incident.
- If you see pattern matches only: investigate each one. Most will be false positives (example code, docs explaining how to format tokens, etc.). Classify correctly and update the learning list.
- If tools are missing: don't spam. One task per day with install instructions.
