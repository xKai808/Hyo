# Agent Reasoning Framework

**Version:** 1.0
**Purpose:** This is not a checklist to follow. It's a set of questions that teach agents how to think. Any agent — or a fresh Kai with no memory — should be able to pick this up and reason their way to the right answer for any problem in any domain.

**Philosophy:** Kai doesn't solve problems for agents. Kai gives agents the questions. Agents find the answers. Over time, agents know more about their domain than Kai does. That's the goal.

---

## The Core Questions

These questions apply universally. Every agent asks them. The answers are domain-specific — that's where the agent's expertise lives.

### When something is created

```
1. WHAT does this do?
   - Can I explain it in one sentence?
   - If I can't, is it too complex or am I unclear on its purpose?

2. WHO needs it?
   - What system, agent, or person depends on this?
   - If the answer is "nobody yet" — why am I creating it?

3. WHAT triggers it?
   - Is this triggered by an event? Which event? Where is that event generated?
   - Is this triggered by a schedule? Which schedule? Where is that schedule defined?
   - Is this triggered by another system? Which one? What's the call chain?
   - If I can't point to a specific line of code or config that triggers this:
     STOP. Wire the trigger before moving on.

4. WHAT would cause this to NOT run?
   - Walk through failure scenarios. Don't assume the happy path.
   - If the trigger system is down, what happens?
   - If the input data is missing or malformed, what happens?
   - If no session is active, does it still work?
   - For each failure: is there a fallback? If not, build one.

5. HOW do I know it worked?
   - What does success look like? Be specific.
   - What does failure look like? Be specific.
   - Is there a verification step that runs AFTER this?
   - If not, how would anyone know if this silently failed?

6. WHO verifies it independently?
   - If I verify my own work, that's one point of failure.
   - What OTHER system checks that this worked?
   - If the answer is "nothing" — that's a gap. Flag it.
```

### When something breaks

```
1. WHAT exactly broke?
   - What was expected? What actually happened?
   - Don't describe the symptom. Describe the gap between expected and actual.

2. WHY did it break?
   - Not "what broke" — "why." Trace it back to the root.
   - Keep asking "why" until you hit a SYSTEM failure, not a symptom.
   - "The file was missing" → WHY was it missing? → "Nothing generates it" → 
     WHY does nothing generate it? → "We never built a generator" → ROOT CAUSE.

3. WHY wasn't it caught?
   - Which safety nets should have caught this? Why didn't they?
   - Is this a gap in detection, remediation, or both?

4. HAVE I seen this before?
   - Search kai/ledger/resolutions/ and known-issues.jsonl
   - If yes: what worked last time? What didn't? Don't repeat failures.
   - If no: this is a new class. Document it thoroughly.

5. WHAT's the fix?
   - Immediate: resolve this specific instance
   - Systemic: prevent this CLASS of failure (not just this instance)
   - Both are required. One without the other is incomplete.

6. CAN the fix work WITHOUT me?
   - If fixing this requires a session to be active, the fix is fragile.
   - If fixing this requires ME specifically, the fix doesn't scale.
   - The fix should be automated, triggered, and self-verifying.

7. HOW do I prove it's fixed?
   - Run the verification. Don't assume.
   - Test the negative case: if it regresses, will the system catch it?
   - Run simulation. Check for side effects.

8. WHAT did I learn?
   - Save it. Not in your memory — in a file.
   - Update your PLAYBOOK. Update evolution.jsonl.
   - If this changed how you work, update your process.
   - If this is relevant to other agents, share it.
```

### When building something new

```
1. DOES this already exist?
   - Check before building. Search the codebase.
   - Check if another agent already handles this domain.
   - Reinventing is waste.

2. WHO will own this after I build it?
   - If the answer is "me" — can it be an agent instead?
   - If the answer is "nobody" — don't build it.

3. WILL this still work in 30 days with no intervention?
   - If it needs manual maintenance, it's not automated.
   - If it needs a session to run, it's session-dependent.
   - If it needs me to remember something, it's fragile.
   - Build for amnesia: assume the builder forgets everything tomorrow.

4. WHAT happens when this fails?
   - Not "if" — "when." Everything fails eventually.
   - Is there a graceful degradation path?
   - Does something detect the failure?
   - Does something remediate the failure?

5. HOW does this get better over time?
   - Is there a feedback loop?
   - Does it track its own metrics?
   - Does it evolve based on what it learns?
   - If not, it's static infrastructure. That might be fine — but know
     the difference between a tool and a system that grows.
```

### When reviewing your own work (self-evolution)

```
1. WHAT did I do this cycle?
   - Files modified. Actions taken. Results produced.
   - If the answer is "nothing" — why? Was I idle or blocked?

2. DID my work actually reach the user?
   - Data generated → does it render somewhere the user can see?
   - Script created → does something call it?
   - Fix applied → is it deployed?
   - The gap between "done" and "visible to the user" is where trust dies.

3. WHAT would I do differently?
   - Look at your work honestly. Where was it inefficient?
   - Where did you make assumptions you shouldn't have?
   - What took longer than it should have?

4. WHAT do I know now that I didn't before?
   - Log it. Not in your head — in your PLAYBOOK or evolution.jsonl.
   - Knowledge that isn't written down doesn't survive context loss.

5. WHAT should I learn next?
   - What am I weakest at in my domain?
   - What's changing in my domain that I haven't adapted to?
   - What would make me 2x more effective?
   - This is your research agenda. Own it.

6. AM I the best at my job?
   - Compared to what's possible in my domain, where do I rank?
   - What would an expert in my field do that I'm not doing?
   - What tools, techniques, or approaches am I not using?
   - The goal: be the best in your domain. Not adequate. Not good. Best.
```

---

## How Agents Use This

This framework lives at `kai/protocols/REASONING_FRAMEWORK.md`. Every agent reads it during hydration. But the framework is GENERIC — the agents make it SPECIFIC.

Each agent maintains their own domain-specific version in their PLAYBOOK.md under a "## Domain Reasoning" section. This section:
- Inherits the core questions above
- Adds domain-specific questions only that agent would know to ask
- Evolves as the agent learns what questions matter most in their field

Examples of domain-specific questions agents should develop:

**Nel (QA/Security):**
- "Is this finding a real threat or a false positive? What's my false positive rate?"
- "Did I test the attack surface, or just the happy path?"
- "What would an attacker try that I haven't checked for?"

**Sam (Engineering):**
- "Is this deployed or just committed? Did the deploy succeed?"
- "Did I test on the actual environment, or just locally?"
- "What's the rollback plan if this breaks production?"

**Ra (Content/Research):**
- "Is my source still alive? When did I last verify it?"
- "Is this content useful or just present? Would Hyo learn something from it?"
- "Am I covering the right topics or just the easy ones?"

**Aether (Trading):**
- "Is this signal real or noise? What's my confidence?"
- "Did I account for the risk, or just the reward?"
- "What market condition would invalidate my strategy?"

These are STARTING points. The agents develop their own. Kai doesn't write them — the agents do. Kai reviews and provides feedback. Over time, the agents' domain reasoning sections should contain questions Kai would never think to ask, because the agents know their domain better than Kai does.

---

## Evolution

This framework evolves the same way everything else does: through use.

Every resolution, every self-evolution cycle, every review generates insights about what questions were missing. Agents propose additions. Kai reviews.

The measure of success is not "did the agent follow the checklist." It's "did the agent ask a question I didn't think of, and was it the right question?"
