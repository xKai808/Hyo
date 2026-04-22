# PROTOCOL_PREFLIGHT.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Status: HARD RULE — NO EXCEPTIONS (Hyo directive 2026-04-21)

---

## PURPOSE

Before any decision, file creation, code change, or protocol update, Kai and every agent must
verify what already exists. This prevents:
- Creating duplicate files that shadow existing ones
- Writing protocols that contradict existing ones
- Building tools that already exist elsewhere
- Making assumptions about system state that are 3 sessions out of date

"You need to read what currently pre-exists in all of the files. This is standard and also should
be based on a protocol. Otherwise, we will continue to make new files and renditions of something
that may already exist." — Hyo, 2026-04-21

---

## ALGORITHM-FIRST: THE PRE-ACTION FAMILIARITY GATE

This gate runs BEFORE any of the following actions:
- Creating a new file
- Creating a new protocol
- Modifying an existing protocol
- Building a new tool/script
- Making architectural decisions
- Delegating work that requires domain knowledge

### The Familiarity Gate

```
GATE 1: Have I read the directly relevant files for this task today?
  → "Relevant" = any file the task will modify, reference, or supersede
  → NO → READ before proceeding. Do not proceed until read.

GATE 2: Do I know what ALL files in the target directory contain?
  → NO → run a directory listing and read any unfamiliar files
  → Acceptable shortcut: read file headers/first 20 lines to determine relevance

GATE 3: Does a file already exist that achieves what I'm about to create?
  → Search: grep -r "<key concept>" <relevant directories>
  → If match found → read the match before deciding to create new
  → YES (existing file covers it) → extend/update the existing file, do NOT create new

GATE 4: Does a protocol already exist that covers this territory?
  → Check kai/protocols/ directory listing
  → Check AGENT_ALGORITHMS.md for the relevant section
  → YES → reference existing protocol, do NOT duplicate

GATE 5: Am I about to patch or work around rather than fix root cause?
  → "Is my proposed change fixing the underlying system (YES) or bypassing it (NO)?"
  → NO (it's a workaround) → STOP. Find and fix the root cause instead.
  → This is the NO-PATCH gate. It is non-negotiable.

GATE 6: Will this change require updates to other files?
  → Protocol changes → AGENT_ALGORITHMS.md must reference them
  → Runner changes → PLAYBOOK.md must document them
  → New tools → TRIGGER_MATRIX.md must add them
  → Constitution changes → all PLAYBOOKs must be verified for consistency
  → YES → identify ALL downstream files before starting, update them in same commit
```

---

## SECTION 1: SESSION START FAMILIARITY PROTOCOL

At the start of every Kai session, the following files MUST be read before any work begins.
This is not the hydration protocol (KAI_BRIEF.md etc.) — it is supplementary to it.

### Mandatory Pre-Session Reads (all of them, every session)

```
1. KAI_BRIEF.md — current system state (what's running, what's broken)
2. kai/ledger/hyo-inbox.jsonl — urgent messages from Hyo (check for unread)
3. kai/dispatch/*.md — today's and yesterday's Dispatch transcripts
4. kai/memory/KNOWLEDGE.md — permanent facts, standards, balance ledger
5. kai/memory/TACIT.md — Hyo's preferences, hard rules, communication patterns
6. KAI_TASKS.md — priority queue
7. kai/ledger/known-issues.jsonl — patterns to watch for
8. kai/ledger/session-errors.jsonl — Kai's own past mistakes (RECALL)
9. kai/protocols/EXECUTION_GATE.md — pre-action and post-action gates
10. kai/protocols/VERIFICATION_PROTOCOL.md — verification requirements
```

### Domain-Specific Pre-Read (when working on that domain)

```
Working on agents/nel/ → read agents/nel/PLAYBOOK.md + agents/nel/GROWTH.md
Working on agents/ra/ → read agents/ra/PLAYBOOK.md + agents/ra/GROWTH.md
Working on agents/sam/ → read agents/sam/PLAYBOOK.md + agents/sam/GROWTH.md
Working on agents/aether/ → read agents/aether/PROTOCOL_DAILY_ANALYSIS.md (v2.5)
                              + agents/aether/PLAYBOOK.md
                              + kai/protocols/PROTOCOL_AETHER_ISOLATION.md (THIS IS MANDATORY)
Working on agents/dex/ → read agents/dex/PLAYBOOK.md + agents/dex/GROWTH.md
Working on tickets → read kai/protocols/PROTOCOL_TICKET_LIFECYCLE.md (this session)
Working on HQ publish → read kai/protocols/PROTOCOL_HQ_PUBLISH.md
Working on protocols → read ALL files in kai/protocols/ directory listing first
Working on AGENT_ALGORITHMS.md → read full file (not first 200 lines — full)
```

---

## SECTION 2: THE NO-PATCH GATE

Every fix must answer: "Am I fixing the root cause or adding a patch?"

```
NO-PATCH GATE (mandatory for ALL changes):

Question: "Is this change fixing the underlying system condition that caused the failure,
          or is it bypassing/working around the failure?"

YES (root cause fix) → proceed
NO (patch/workaround) → STOP

A patch is defined as:
  - Catching an error rather than preventing it
  - Adding a special case that handles one instance without preventing recurrence
  - Commenting out failing code rather than understanding why it fails
  - Hardcoding a value rather than deriving it from the correct source
  - Catching an exception and silently continuing rather than fixing the exception source
  - Adding a try/except block around broken code without fixing the broken code

If the root cause cannot be fixed immediately:
  → Document it as a KNOWN ERROR in agents/dex/ledger/known-errors.jsonl
  → Open a Problem ticket for the permanent fix
  → The workaround may be applied TEMPORARILY with explicit documentation
  → Set reminder: workaround expires in 7 days; permanent fix must be in by then
```

---

## SECTION 3: NEW FILE CREATION GATE

Before creating ANY new file:

```
CREATION GATE (run before every new file):

Q1: Does a file with this purpose already exist?
  → Search: find <directory> -name "*.md" | xargs grep -l "<key terms>" 2>/dev/null
  → YES → extend existing file instead

Q2: Will this file be read by something? When? How?
  → Identify the consumer (agent runner, Kai session start, dispatch, cron)
  → NO clear consumer → do NOT create the file (dead files add noise, not signal)

Q3: Will this file be updated by something? How often?
  → Identify the update mechanism (nightly runner, agent reflection, Kai post-task)
  → NO update mechanism → the file will go stale; consider a different approach

Q4: Does this file need a trigger (if it's a script/protocol)?
  → Scripts: added to runner, launchd, or queue
  → Protocols: referenced from AGENT_ALGORITHMS.md and relevant PLAYBOOK
  → NO trigger → defer creation until trigger is wired

Q5: Is this file naming consistent with the existing convention?
  → PROTOCOL_<NAME>.md for protocols
  → <agent>-<function>.py for agent scripts
  → <agent>.sh for agent runners
  → NO → use the existing convention
```

---

## SECTION 4: DECISION FAMILIARITY GATE

Before making any architectural or strategic decision:

```
DECISION GATE:

Q1: Is there prior context on this decision in:
    - kai/ledger/session-errors.jsonl (did we try this before and fail?)
    - kai/ledger/known-issues.jsonl (is this a known pattern?)
    - kai/ledger/resolutions/ (was this resolved before? what was the fix?)
    - kai/memory/KNOWLEDGE.md (is there a standing decision on this?)
    - KAI_TASKS.md (is this already planned/in progress?)
  → YES → read the prior context before deciding

Q2: Is there a protocol that already governs this decision?
  → Check kai/protocols/ listing
  → YES → follow the protocol; don't re-derive

Q3: Have I seen this exact problem in a prior session?
  → Check session-errors.jsonl for matching descriptions
  → YES → do not repeat the same approach that failed; use what worked

Q4: Would Hyo have already provided guidance on this type of decision?
  → Check kai/memory/TACIT.md for relevant preferences
  → Check kai/dispatch/ for recent transcripts
  → YES → follow Hyo's guidance; don't ask again
```

---

## SECTION 5: PROTOCOL FOR READING LARGE FILES

Many files in the Hyo system are >1000 lines. Reading strategy:

```
For files < 200 lines: read full
For files 200-500 lines: read full, note sections for follow-up
For files 500-1000 lines: read first 200 lines + grep for relevant sections
For files > 1000 lines (AGENT_ALGORITHMS.md, PLAYBOOK.md, PROTOCOL_DAILY_ANALYSIS.md):
  1. Read section headings/table of contents first
  2. Read sections directly relevant to current task
  3. Note what you have NOT read — do not assume unread sections have no bearing
  4. If making changes that touch the full document, read the full document

NEVER assume a file is the same as it was last session. Files change between sessions.
Always read from disk — never from memory of a previous session.
```

---

## SECTION 6: TRIGGER AND ENFORCEMENT

**How is this protocol triggered?**
- Kai session start: steps 1-5 of CLAUDE.md hydration protocol already mandate reads
- Before any tool call: EXECUTION_GATE.md pre-action gate asks "have I checked prior context?"
- This protocol is the implementation spec for that gate

**How is compliance verified?**
- Dex checks: if a new file is created without a corresponding TRIGGER_MATRIX.md entry → P2 flag
- Nel checks: if a new protocol is created without reference in AGENT_ALGORITHMS.md → P2 flag
- Kai self-checks: post-task reflection question 5 ("Did I update ALL governing docs?")

**Who owns this protocol?**
- Kai owns updates to this protocol
- All agents are required to follow it
- Violations are logged to kai/ledger/session-errors.jsonl immediately

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
