# Kai Execution Gate

**Purpose:** This is not a verification protocol (that runs after). This runs BEFORE every action. It's the difference between "did I verify?" and "should I even be doing this?"

**When:** Before EVERY tool call, file edit, commit, data change, or response to Hyo. No exceptions.

**Why this exists:** Session 10 produced 14 errors. 0 were caught before Hyo found them. The rules existed. The execution didn't. Rules without a gate are just documentation.

---

## The Five Questions (answer before acting)

```
1. WHAT AM I ACTUALLY TRYING TO ACHIEVE?
   Not "what task am I doing" but "what outcome does Hyo need?"
   If I can't state the outcome in one sentence → I don't understand
   the task well enough to start.

2. WHO CONSUMES THE OUTPUT?
   Trace the full path: file → renderer → user-visible surface.
   If I'm changing data: what reads it? How does it render?
   If I'm deploying: what URL shows the result?
   If I can't name the consumer → I'm about to make SE-010-013 again.

3. HAVE I SEEN THIS PATTERN FAIL BEFORE?
   Check session-errors.jsonl for matching patterns.
   Not "read the file" — actually scan for the category of work.
   Deploying? → SE-010-010 (verify after deploy)
   Dual-path file? → SE-010-011 (update both)
   Publishing content? → SE-010-012 (HTML + feed + HQ renderer)
   Changing data? → SE-010-013 (trace consumer first)
   GPT work? → SE-010-014 (intelligence, not arithmetic)

4. WHAT WOULD HYO ASK?
   Before declaring anything done, imagine Hyo looking at the result.
   "Did you verify?"
   "Does the consumer render it?"
   "Is this actually useful or just busy work?"
   "What changed? Show me."
   If any of these questions would catch a problem → fix it now.

5. WHAT'S THE PROOF?
   Every action needs verification evidence.
   Deployed → fetch the URL, confirm content
   Edited a file → read it back, confirm the change
   Updated data → check the consumer renders it
   "It should work" is not proof. "I fetched it and saw X" is proof.

6. WILL THIS TRIGGER AN OS PROMPT HYO HASN'T SEEN BEFORE? (SE-011-007)
   Any tool/binary that touches ~/Documents, ~/Desktop, ~/Downloads,
   Camera, Microphone, Contacts, Calendar, or Location will trigger a
   macOS TCC permission dialog the FIRST time it runs.
   Installing a new binary? → Check if it accesses protected dirs.
   Running a tool for the first time? → Same check.
   If YES → Notify Hyo BEFORE execution. Tell them:
     (a) what app/tool will request access
     (b) what it will access and why
     (c) what the dialog will look like
     (d) that they should click "Allow"
   If NO advance notice was given → DO NOT EXECUTE.
   This is blocking. No exceptions. Hyo denied cipher's access because
   we didn't warn them. That's our fault, not theirs.

7. AM I ABOUT TO ESCALATE TO HYO? (SE-011-018)
   Before telling Hyo ANYTHING requires their physical presence:
     (a) Did I attempt it via the queue first?
     (b) Did it actually fail? What was the error?
     (c) Is the failure something only Hyo can fix?
         Valid reasons for Hyo: biometric prompt, GUI password entry,
         physical hardware, queue worker down AND launchctl unreachable.
         NOT valid: "I assumed it needs the Mini." Assumptions are not errors.
   If the answer to (a) is NO → attempt via queue. Do not escalate.
   If the answer to (b) is "I didn't check" → investigate. Do not escalate.
   If the answer to (c) is NO → fix it yourself. Do not escalate.
   Hyo's time is the scarcest resource. Every false escalation wastes it
   and erodes trust. This gate exists because Kai escalated 3 items to
   Hyo that all worked fine via queue. Zero of them needed Hyo.

8. AM I FIXING THE ROOT CAUSE OR ADDING A WORKAROUND? (SE-011-016)
   If a tool/system is broken, the fix is making it work — not bypassing it.
   Workarounds accumulate. Each one adds cost, complexity, and another
   thing that can break. Ask:
     (a) What is the root cause of the failure?
     (b) Is there an agent who owns this? (Sam = infra, Nel = security)
     (c) Did I delegate to that agent?
   If the answer to (a) is "I don't know" → investigate before doing anything.
   If the answer to (c) is NO → delegate. Do not do their job.
   Workarounds are acceptable ONLY as temporary bridges while the root fix
   is in progress — and only if a ticket tracks the root fix with a deadline.
```

---

## When Hyo Asks a Question

Hyo's questions are not surveys. They are prompts to change behavior.

```
WRONG RESPONSE:
  Hyo: "Why didn't you verify?"
  Kai: "You're right. I should have verified. I'll add a rule."
  [Nothing changes. Same error next time.]

RIGHT RESPONSE:
  Hyo: "Why didn't you verify?"
  Kai: "Because I didn't run the execution gate. Here's the specific
        failure: I skipped question 5. Here's what I'm changing in
        the execution path: [specific code/process change]. Here's
        the test that proves it works: [run the new process now]."
  [Behavioral change demonstrated, not described.]
```

The pattern:
1. Acknowledge the specific failure (not generally)
2. Identify which gate question would have caught it
3. Make a STRUCTURAL change (code, process, algorithm — not a rule)
4. DEMONSTRATE the change working right now
5. Move on. Don't apologize. Don't promise. Show.

---

---

## Completion Gate (run after EVERY unit of work)

The 5 questions above run BEFORE action. This flowchart runs AFTER. It loops until the work is actually done — not "I think it's done" done, but provably on origin and verified done.

```
START → Did I make changes to files?
  │
  ├─ NO → Am I sure? (git status)
  │         └─ YES → Done.
  │
  └─ YES ↓
         Did I commit?
           │
           ├─ NO → Commit now. Return to top.
           │
           └─ YES ↓
                  Did I push? (not "will push later" — did the push succeed?)
                    │
                    ├─ NO → kai exec "git push origin main" NOW.
                    │         Did push succeed?
                    │           ├─ NO → Log P1. Fix the blocker. Do not start next task.
                    │           └─ YES → Continue ↓
                    │
                    └─ YES ↓
                           Did I verify the result?
                             │
                             ├─ NO → Verify now. What does the consumer see?
                             │         Fetch the URL / read the file / run the function.
                             │         Is the output correct?
                             │           ├─ NO → Fix it. Return to top.
                             │           └─ YES → Continue ↓
                             │
                             └─ YES ↓
                                    Did I run dispatch simulate?
                                      │
                                      ├─ NO → Run it now: bash bin/dispatch.sh simulate
                                      │        Are there NEW failures (not pre-existing)?
                                      │          ├─ YES → Fix them. Return to top.
                                      │          └─ NO → Continue ↓
                                      │
                                      └─ YES ↓
                                             Did I run bin/verify-live.sh?
                                               │  (S19-003: mandatory after every push that
                                               │   changes website files or data. Run via queue:
                                               │   kai exec "bash ~/Documents/Projects/Hyo/bin/verify-live.sh --quick"
                                               │   Review output — any FAIL = not done)
                                               │
                                               ├─ NO → Run it now. Return to verify step.
                                               │
                                               ├─ FAIL → Fix the failing check, push,
                                               │          re-run verify-live.sh. Loop.
                                               │
                                               └─ YES ↓
                                                      Did I update memory?
                                      │
                                      ├─ NO → Update KAI_BRIEF, KAI_TASKS, relevant
                                      │        ACTIVE.md, tickets. Return to top.
                                      │
                                      └─ YES ↓
                                             Can a fresh Kai pick this up tomorrow
                                             with zero context and know exactly what
                                             happened and what's next?
                                               │
                                               ├─ NO → What's missing? Write it. Return to top.
                                               │
                                               └─ YES → DONE. Next task.
```

**The rule:** You do not exit this flowchart until you reach DONE. Every "NO" loops back. There is no "I'll do it later." There is no "next task" until this task is closed.

**Why this exists (SE-010-015):** 8 commits sat local for 18 hours. Kai answered "Did I commit?" with YES and skipped to next task. The flowchart makes skipping structurally impossible — commit without push loops back, push without verify loops back, verify without memory update loops back.

---

## Integration

This gate is wired into:
- Kai's hydration protocol (item 5: read EXECUTION_GATE.md — runs both pre-action questions AND completion gate)
- The daily analysis algorithm (ANALYSIS_ALGORITHM.md references these as pre-publish checks)
- Every scheduled task prompt should reference "run execution gate before each step"
- **Every agent runner** should run the completion gate before exiting

The 5 questions are the PRE-action check.
The completion gate is the POST-action check.
The verification protocol defines HOW to verify by action type.
All three run. None is optional.

---

## Discrepancy Audit Gate (S18-021 — added 2026-04-18)

**Mandatory after every unit of work. Kai gates himself on these 5 questions before moving to the next task.**

These are YES/NO gates. A NO on any question means: stop, fix, verify, then re-run.

```
1. Did this change create a link that might 404?
   YES → curl the target URL right now. Confirm HTTP 200.
   NO  → proceed.

2. Did this produce content Hyo would see without understanding?
   YES → add context, labels, or self-explanatory summaries. No bare headings.
   NO  → proceed.

3. Did this change a data source without updating every consumer of that data?
   YES → trace the full consumer chain (data → renderer → user-visible output).
         Update all consumers.
   NO  → proceed.

4. Did this add a cost or resource use without tracking it in api-usage.jsonl?
   YES → add cost logging now.
   NO  → proceed.

5. Did this claim a task is "done" before the live surface was verified?
   YES → verify live. Not in the local file — verify the deployed/live version.
   NO  → DONE. Proceed to next task.
```

**Gate question for each action type:**
- Deployed a page? → Did I check the live URL returns 200?
- Published a feed entry? → Did I check the readLink resolves?
- Updated data? → Did I update both paths (agents/sam/website/ AND website/)?
- Added any API call? → Did I log the cost?
- Wrote a summary for Hyo? → Is it self-contained without requiring prior context?

---

## On-the-Spot Ticket Gate (S19-004 — added 2026-04-18)

**Fires the moment Kai finds anything unexpected. Before all other action.**

Hyo's directive: every discrepancy gets a ticket immediately when discovered — not in a batch at end of session, not after fixing it, not "noted for later."

```
DISCREPANCY DISCOVERED:
  │
  └─ Open kai/tickets/tickets.jsonl entry NOW. Fields required:
       id:          next S##-### in sequence
       ts:          current MT timestamp
       title:       one sentence, specific (not "bug found")
       description: what I found, where, what the impact is
       prevention:  the gate question that would have caught this earlier
       caught_by:   "kai" (self-found) or "hyo" (Hyo found it)
       severity:    P0 / P1 / P2
       status:      open
  │
  └─ THEN continue with the task.
```

**No ticket = the discrepancy didn't happen.** Hyo's trust is built on the ticket log, not on Kai's memory.

**Audit (weekly, every Sunday report):**
- Count: how many discrepancies did Hyo report this week?
- Count: how many had a ticket already open when Hyo reported it?
- Gap = Kai's ticket discipline score. Target: 0 gap.

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->

---
## IMPLEMENTATION VERIFICATION GATE (added 2026-04-23 — third occurrence of describe-not-build)

This gate runs AFTER claiming any implementation is complete.
Three occurrences (SE-010-008, SE-010-009, SE-S30-describe-001) prove that
a rule in a document is insufficient. This gate requires a verifiable artifact.

**Before saying "X is built/done/implemented":**

1. **Does the code file exist?**
   - Gate: `ls <file_path>` — if not found, it is NOT built
   - A .md doc describing the feature ≠ the feature

2. **Does the code actually run?**
   - Gate: `python3 -c "import ast; ast.parse(open('<file>').read())"` for Python
   - Gate: run the script with `--help` or a test flag
   - "It should work" ≠ verified

3. **Does the output exist?**
   - Gate: check for the produced artifact (DB file, API response, log entry)
   - For prompt caching: grep for `cache_control` in the actual .py file
   - For SQLite: `ls kai/tickets/tickets.db` AND `python3 bin/tickets-db.py stats`
   - For Compaction API: grep for `compact-2026-01-12` in the .py file

4. **Is the trigger wired?**
   - Gate: confirm the script is called from its scheduler (kai-autonomous.sh, launchd, runner)
   - A script that exists but is never called = not implemented

VERDICT: If any gate returns NO → it is not done. Do not report it as done.
