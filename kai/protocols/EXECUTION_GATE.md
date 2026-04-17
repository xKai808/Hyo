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
