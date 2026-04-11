# sentinel.algorithm.md

**Who:** sentinel.hyo (QA agent)
**What:** The ongoing algorithm, checklist, and operating rules that sentinel follows on every run.
**Updated by:** Kai. Freely editable — sentinel reads this before every run.
**Read by:** `kai/sentinel.sh` and Kai (Claude) when reviewing sentinel's work.

---

## Mission

Detect quality regressions across the Hyo agent fleet before they become visible to Hyo. Silence is success. Only escalate when escalation is warranted.

## Run algorithm (executed every invocation)

1. **Load state** from `kai/memory/sentinel.state.json`. Initialize counters to 0 if first run.
2. **Load false-positive list** from state. Any issue ID matching will be skipped.
3. **Run check battery** (see checklist below). For each check that fails, compute a stable issue ID: `{check_id}:{detail_hash}`.
4. **For each failing check:**
   - If issue_id in false_positives → skip silently
   - If issue_id in known_issues → increment `daysFailing`, update `lastSeen`
   - If new → add to known_issues with `firstSeen=now, daysFailing=1`
5. **For each issue no longer failing:** mark `status=resolved`, keep in state for 7 days then purge.
6. **Evaluate escalation thresholds** (see below).
7. **Append run summary** to `runHistory` (keep last 30 entries).
8. **Write state** back to `sentinel.state.json`.
9. **Emit report** only if new issues OR escalations are present. Silence otherwise.

## Check battery (in order)

### P0 — Must pass every run

- **aurora-ran-today**: `~/Documents/Projects/Hyo/newsletters/$(date +%Y-%m-%d).md` exists and is > 500 bytes
- **api-health-green**: `curl /api/health` returns `ok:true` and `founderTokenConfigured:true`
- **founder-token-integrity**: `.secrets/founder.token` exists and is mode 600

### P1 — Fleet health

- **scheduled-tasks-fired**: most recent aurora log is < 25 hours old (proxy for cron firing)
- **manifest-valid-json**: every `NFT/agents/*.hyo.json` parses and has required fields (`name, version, identity, credit, pricing`)
- **secrets-dir-permissions**: `.secrets/` is mode 700, contents are mode 600
- **repo-is-git**: `.git/` directory exists at repo root (uncommitted work = catastrophic loss risk)
- **kai-dispatcher-present**: `bin/kai.sh` exists and is executable

### P2 — Drift detection

- **cross-model-validation**: latest aurora brief is coherent (non-empty headers, has at least 3 sections) — cheap structural check only for now; semantic validation pending claude-code integration
- **disk-space**: Mini has > 5GB free in `~/Documents`
- **task-queue-size**: `KAI_TASKS.md` P0 section has ≤ 5 items (more than that = overload signal)

## Escalation thresholds

| Severity | Condition | Action |
|---|---|---|
| P0 | failing 1 run | file task to KAI_TASKS, no notification |
| P0 | failing 2 runs in a row | file task + desktop notification to Hyo |
| P0 | failing 3 runs in a row | file as "urgent" + notification + update KAI_BRIEF "Known blockers" |
| P1 | failing 3 runs in a row | file task, no notification |
| P1 | failing 5 runs in a row | elevate to P0 priority in KAI_TASKS |
| P2 | failing 5 runs in a row | file task, no notification |
| P2 | failing 10 runs in a row | elevate to P1 priority |

Rule: **never spam.** If the same issue is already filed in KAI_TASKS (grep for the issue ID), don't file again. Only update.

## False positive learning

When Kai reviews a sentinel finding and determines it's not a real issue:
- Add the issue_id to `state.falsePositives` array
- Add a note in this algorithm.md explaining why (so future Kais don't re-enable it)
- If it's a test that produces too many false positives, remove the test from the battery

**Current false positives:** _(none yet)_

## Operator notes

- Sentinel runs at 04:00 MT daily (one hour after aurora) — this is intentional so aurora's output can be validated on the same run
- Sentinel is also callable on demand via `kai sentinel`
- Hyo should almost never see output from sentinel. When they do, it matters.
