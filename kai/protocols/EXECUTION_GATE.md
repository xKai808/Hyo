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

## Integration

This gate is wired into:
- Kai's hydration protocol (item 5: read VERIFICATION_PROTOCOL.md → this replaces it as the PRE-action check)
- The daily analysis algorithm (ANALYSIS_ALGORITHM.md references these as pre-publish checks)
- Every scheduled task prompt should reference "run execution gate before each step"

The execution gate is the PRE-action check.
The verification protocol is the POST-action check.
Both must run. Neither is optional.
