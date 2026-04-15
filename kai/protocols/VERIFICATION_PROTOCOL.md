# Kai Verification Protocol v1.0

**Created:** 2026-04-14 21:30 MT  
**Trigger:** Hyo feedback — "Did you verify? Why did you just assume?"  
**Root cause:** 0% of 11 critical errors in session 10 were caught before Hyo found them.

---

## THE RULE

**Nothing is done until it's verified. Verified means proof — not "it should work."**

---

## PRE-ACTION CHECKLIST (run before EVERY action)

Before taking any action, Kai must:

1. **CHECK RECALL** — Read `kai/ledger/session-errors.jsonl` for matching patterns.
   - Am I about to update a file? → Check SE-010-011 (wrong path). Verify which path the consumer reads from.
   - Am I about to deploy? → Check SE-010-010 (deploy not verified). Plan the verification fetch.
   - Am I about to implement instructions? → Check SE-010-008, SE-010-009 (reinterpret). Re-read the instruction verbatim.
   - Am I about to ship a feature? → Check SE-010-005 (shipped broken). Plan the smoke test.

2. **STATE THE VERIFICATION** — Before executing, state HOW you will verify the action worked.
   - "I will fetch https://www.hyo.world/data/X and confirm field Y has value Z."
   - "I will run the function and check the output contains [expected]."
   - "I will load the page and confirm it renders [expected content]."
   - If you can't state the verification step, you don't understand the action well enough.

3. **EXECUTE AND VERIFY** — Do the thing, then immediately verify.
   - Don't batch. Don't defer. Don't "come back to it."
   - Verification happens in the same breath as execution.

4. **LOG THE PROOF** — Record what the verification showed.
   - Success: note it and move on.
   - Failure: diagnose, fix, re-verify. Don't assume the fix worked either.

---

## VERIFICATION BY ACTION TYPE

### Deployment (git push → Vercel)
1. `git push` succeeds (exit code 0)
2. Wait 15s for Vercel build
3. Fetch the LIVE PRODUCTION URL (not preview, not local)
4. Confirm the specific data/content that was supposed to change
5. Check response headers for `x-vercel-cache` (MISS on first request after deploy = good)

### File Updates
1. Confirm the file was written (`cat` or `Read` the file)
2. If the file has multiple paths (symlink, duplication), verify ALL paths
3. If the file is consumed by a web service, verify the served version
4. `git diff` to confirm the correct content is staged

### API/Pipeline Changes
1. Run the pipeline end-to-end
2. Check the OUTPUT, not just exit code 0
3. If it produces a file, read the file
4. If it calls an external API, confirm the response is valid (not placeholder/error)

### Feature Shipping
1. Load the actual page/UI that uses the feature
2. Trigger the feature as a user would
3. Confirm the output renders correctly
4. Test at least one edge case

### Instruction Implementation
1. Re-read Hyo's instruction verbatim BEFORE starting
2. After implementing, re-read the instruction AGAIN
3. Checklist every specific requirement mentioned
4. If ANY requirement was interpreted differently than stated, flag it and ask

---

## ERROR PATTERN RECALL

Before every action, scan for these known failure modes:

| Pattern | Check | Reference |
|---|---|---|
| Wrong file path | Which path does the consumer read? | SE-010-011 |
| Deploy assumed | Fetch live URL after every push | SE-010-010 |
| Instruction shortcut | Re-read instruction verbatim | SE-010-008, SE-010-009 |
| Feature untested | Smoke test before "shipped" | SE-010-004, SE-010-005 |
| Credential placeholder | Verify key is real, not example | SE-010-007 |
| Pipeline unwired | Verify trigger exists and fires | SE-010-007 |
| Shell syntax assumed | Test in target shell, use shellcheck | SE-010-001, SE-010-003 |
| API format assumed | Check docs or test payload first | SE-010-002 |

---

## WHEN TO UPDATE THIS PROTOCOL

- After every session where a new error pattern is found
- Add the pattern to the recall table above
- Add the verification step to the relevant action type section
- This file is part of Kai's hydration — read it every session

---

## ENFORCEMENT

This protocol is wired into:
1. **Hydration** — read this file at session start (added to CLAUDE.md hydration list)
2. **Pre-commit** — `verify-gpt-gate.sh` for analysis files
3. **Session errors ledger** — `kai/ledger/session-errors.jsonl` for pattern matching
4. **Post-action** — every action gets a verification step; no "fire and forget"

The test: if Hyo asks "did you verify?" the answer must always be YES with proof.
