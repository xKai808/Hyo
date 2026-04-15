# KAI SYSTEM — SCHEDULED MAINTENANCE & MEMORY SPECIFICATION
Version: 1.0 — April 2026
Based on: OpenClaw cron docs, memsearch, ReMe, agentmemory, DEV Community research

---

## PART 1 — SCHEDULED MAINTENANCE FREQUENCY

### The Optimal 24-Hour Schedule

Research consensus across OpenClaw, Hermes Agent, and Claude Code headless mode:

```
EVERY 15 MINUTES    → Healthcheck + SLA enforcement
EVERY 30 MINUTES    → Business monitoring (AetherBot P&L, ticket queue)
EVERY HOUR          → Blocked ticket escalation review
17:00 MTN DAILY     → AetherBot log analysis (past 24h)
23:50 MTN DAILY     → Nightly consolidation + memory update
02:30 AM MTN DAILY  → Memory compaction + archive noise
03:00 AM MTN DAILY  → Overnight research (Aurora/Ra)
06:30 AM MTN DAILY  → Morning brief prepared for operator
```

### Why These Intervals

**15 minutes** is the industry standard for agent health monitoring.
Anything slower misses cascading failures before they become unrecoverable.
SLA clocks need to be checked this frequently to enforce P1 = 1 hour.

**30 minutes** for business monitoring because AetherBot can lose
meaningful money in 30 minutes if something goes wrong. Not every
15 minutes because it would generate noise. Not every hour because
that's too slow to catch a bad session early.

**Hourly** for BLOCKED ticket review because a ticket that's been
blocked for more than 1 hour needs active escalation, not passive logging.

**17:00 MTN** for AetherBot analysis because this is when you arrive home.
Report is waiting. No manual trigger needed.

**23:50 MTN** for nightly consolidation. Late enough to capture the full day.
Early enough that it's done before midnight rollover confuses timestamps.

**02:30 AM** for memory compaction. Lowest traffic window. No agent activity.
Safe to do expensive operations without interfering with anything live.

---

## PART 2 — CRON IMPLEMENTATION

Install this on the Mac Mini. Add to crontab:

```bash
crontab -e
```

Paste:

```cron
# === KAI SYSTEM CRON SCHEDULE ===

# Healthcheck + SLA enforcement (every 15 min)
*/15 * * * * source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/healthcheck.sh >> /Users/kai/Documents/Projects/Kai/logs/healthcheck.log 2>&1

# Business monitoring (every 30 min)
*/30 * * * * source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/business_monitor.sh >> /Users/kai/Documents/Projects/Kai/logs/monitor.log 2>&1

# Blocked ticket escalation (every hour)
0 * * * * source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/escalate_blocked.sh >> /Users/kai/Documents/Projects/Kai/logs/escalation.log 2>&1

# AetherBot daily analysis (17:00 MTN)
0 17 * * * source /Users/kai/.zprofile && /Users/kai/kai/venv314/bin/python3 "/Users/kai/Documents/Projects/AetherBot/Kai analysis/kai_analysis.py" >> /Users/kai/Documents/Projects/Kai/logs/analysis.log 2>&1

# Nightly consolidation (23:50 MTN)
50 23 * * * source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/nightly_consolidation.sh >> /Users/kai/Documents/Projects/Kai/logs/consolidation.log 2>&1

# Memory compaction (02:30 AM MTN)
30 2 * * * source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/memory_compact.sh >> /Users/kai/Documents/Projects/Kai/logs/memory.log 2>&1

# Overnight research — Aurora/Ra (03:00 AM MTN weekdays)
0 3 * * 1-5 source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/overnight_research.sh >> /Users/kai/Documents/Projects/Kai/logs/research.log 2>&1

# Morning brief prep (06:30 AM MTN)
30 6 * * * source /Users/kai/.zprofile && bash /Users/kai/Documents/Projects/Kai/scripts/morning_brief.sh >> /Users/kai/Documents/Projects/Kai/logs/brief.log 2>&1
```

**Critical:** Always source .zprofile in cron or ANTHROPIC_API_KEY won't exist.
Always redirect to log files or you get no record of what happened.

---

## PART 3 — TICKET RESOLUTION WORKFLOW

### The Lifecycle (from research: GitHub Agentic Workflows + Paperclip patterns)

```
OPEN → ACTIVE → IN REVIEW → CLOSED
         ↓
       BLOCKED → escalates to Kai → operator notified if P1
```

### How a Ticket Gets Cleared

A ticket cannot close by declaration. It closes by evidence.

**Step 1 — Agent runs verify.sh**
```bash
bash agents/[agent]/verify.sh [TICKET-ID]
```
Every check must return PASS. If any fail, ticket stays IN REVIEW.

**Step 2 — Ticket updated with evidence**
```bash
kai ticket update [ID] \
  --status "IN REVIEW" \
  --evidence "verify.sh passed 7/7 checks" \
  --log-path "logs/verify_2026-04-14.txt"
```

**Step 3 — Gate agent reviews (System 2)**
For any output going public, the gate agent (QA, Security, Publishing)
must sign off independently before the ticket closes.

**Step 4 — Ticket marked CLOSED**
```bash
kai ticket close [ID] \
  --resolution "All verify checks passed. QA approved. Deployed." \
  --closed-by "[agent]"
```

**Step 5 — Git commit triggered**
Every ticket close triggers a commit. The ticket ID is in the commit message.
This creates an immutable audit trail.

```bash
git add -A
git commit -m "close([TICKET-ID]): [resolution summary]"
git push
```

### What Happens to BLOCKED Tickets

A ticket is BLOCKED when it cannot proceed without external input.
The blocker must be named explicitly — not just "blocked."

```
BLOCKED: API key not present on Mac Mini
BLOCKED: operator approval required before deploying to Vercel
BLOCKED: waiting for QA gate to complete verify.sh
```

**Escalation rules:**
```
P1 BLOCKED > 1 hour    → Telegram alert to operator, upgrade to P0
P2 BLOCKED > 24 hours  → Telegram alert to operator
P3 BLOCKED > 72 hours  → Include in nightly consolidation report
```

**The escalation script runs every hour:**
```bash
#!/bin/bash
# escalate_blocked.sh
# Checks all BLOCKED tickets against their SLA
# Alerts operator via Telegram if breach detected
```

---

## PART 4 — MEMORY SYSTEM

### Architecture (from: memsearch, ReMe, agentmemory research)

The community has converged on one clear winner for this scale:
**Markdown files as source of truth. SQLite as the search index.**

```
~/Documents/Projects/Kai/memory/
├── Kai_Initialization_v2.md    ← Layer 1: durable facts (never deleted)
├── tacit.md                    ← Layer 3: learned rules (updated nightly)
├── daily/
│   ├── 2026-04-14.md           ← Layer 2: today's events (written live)
│   ├── 2026-04-13.md           ← yesterday (consolidated)
│   └── archive/                ← older than 30 days (compressed)
├── agent_memory/
│   ├── kai.md                  ← Kai's accumulated decisions
│   ├── aether.md               ← AetherBot patterns and lessons
│   ├── aurora.md               ← Newsletter decisions
│   ├── ra.md                   ← Publishing lessons
│   ├── nel.md                  ← Coding patterns
│   └── sam.md                  ← Coding patterns
├── tickets/
│   └── ledger.md               ← Ticket ledger (source of truth)
└── patterns/
    └── pattern_library.md      ← Rules extracted from 3+ occurrences
```

### How Memory Is Saved (Written)

**During the day — live writes:**
Every significant event gets appended to today's daily note immediately.
Agents write to their own agent_memory file after completing any task.

```bash
# Append to today's daily note
echo "\n## [$(date +%H:%M)] AetherBot\n- Balance: \$X\n- Net: +\$Y" \
  >> ~/Documents/Projects/Kai/memory/daily/$(date +%Y-%m-%d).md
```

**After every ticket close:**
```bash
# Append lesson to agent memory file
echo "\n## $(date +%Y-%m-%d) — [TICKET-ID]\n- [what was learned]" \
  >> ~/Documents/Projects/Kai/memory/agent_memory/[agent].md
```

**Nightly at 23:50 — consolidation writes:**
The nightly script asks the System 5 Memory Loop questions and writes
important decisions from Layer 2 (daily) → Layer 1 (initialization)
and Layer 3 (tacit).

---

### How Memory Is Logged

Every write is timestamped and appended. Never overwritten.
The file is the log. Human-readable at all times.

**Log rotation for daily notes:**
```
Current day:     daily/YYYY-MM-DD.md        (live, written constantly)
< 7 days:        daily/YYYY-MM-DD.md        (kept in full)
7-30 days:       daily/YYYY-MM-DD.md        (compressed summary only)
> 30 days:       daily/archive/YYYY-MM.md   (monthly rollup)
```

**Log rotation for system logs:**
```
healthcheck.log     → max 2MB, keep last 2000 lines
analysis.log        → keep last 30 days
consolidation.log   → keep last 90 days
```

---

### How Memory Is Recalled

Three-tier recall system — use the simplest tier that works:

**Tier 1 — Direct file read (instant, free)**
For known facts: Kai reads Kai_Initialization_v2.md and tacit.md
at the start of every session. No search needed.
```
Load: Kai_Initialization_v2.md + tacit.md + today's daily note
Cost: zero tokens, instant
Use: always, every session
```

**Tier 2 — grep/text search (fast, free)**
For recent history: search daily notes by date or keyword.
```bash
grep -r "AetherBot" ~/Documents/Projects/Kai/memory/daily/ \
  --include="*.md" -l | sort | tail -7
```
```
Cost: zero tokens, milliseconds
Use: "what happened last week with X"
```

**Tier 3 — Semantic search via SQLite (slower, still free locally)**
For patterns across all memory files. Use memsearch or sqlite-memory.
```bash
memsearch query "harvest miss" --paths memory/ --top-k 5
```
```
Cost: local compute only if using Ollama embeddings
Use: "have we seen this problem before"
```

**When to use each tier:**
```
Tier 1    → every session startup, known facts
Tier 2    → recent events, date-specific queries
Tier 3    → cross-session patterns, "have we seen this before"
```

---

## PART 5 — NIGHTLY CONSOLIDATION SCRIPT

This is the most important scheduled task. It is the thalamus.

```bash
#!/bin/bash
# nightly_consolidation.sh
# Runs at 23:50 MTN every night
# System 5 Memory Loop — the agent gets smarter after every day

DATE=$(date +%Y-%m-%d)
MEMORY_DIR="$HOME/Documents/Projects/Kai/memory"
DAILY_NOTE="$MEMORY_DIR/daily/$DATE.md"
TACIT="$MEMORY_DIR/tacit.md"
INIT="$MEMORY_DIR/Kai_Initialization_v2.md"
TICKET_LEDGER="$HOME/Documents/Projects/Kai/tickets/ledger.md"

echo "=== NIGHTLY CONSOLIDATION: $DATE ===" >> "$DAILY_NOTE"
echo "Started: $(date +%H:%M)" >> "$DAILY_NOTE"

# 1. Ticket sweep — find any overdue tickets
echo "\n### TICKET STATUS" >> "$DAILY_NOTE"
bash "$HOME/Documents/Projects/Kai/scripts/kai_ticket.sh" report >> "$DAILY_NOTE"

# 2. AetherBot balance update
echo "\n### AETHERBOT" >> "$DAILY_NOTE"
LATEST_LOG=$(ls -t "$HOME/Documents/Projects/AetherBot/Logs/"*.txt | head -1)
echo "Log: $LATEST_LOG" >> "$DAILY_NOTE"

# 3. System 5 Memory Loop questions (written by Kai/Claude)
cat >> "$DAILY_NOTE" << 'EOF'

### MEMORY LOOP — QUESTIONS FOR TONIGHT
Answer these before archiving the day:

1. What was the most important thing that happened today?
2. What decision was made that should become a standing rule?
3. What open issue carries the highest risk going into tomorrow?
4. What should be added to tacit.md based on today?
5. What standing instruction is now outdated?
6. Did any pattern appear for the 3rd time? (becomes a rule)
7. What should the operator know before they wake up?

EOF

# 4. Archive yesterday's note (compress if > 7 days old)
SEVEN_DAYS_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d)
OLD_NOTE="$MEMORY_DIR/daily/$SEVEN_DAYS_AGO.md"
if [ -f "$OLD_NOTE" ]; then
  # Keep first 50 lines (summary) and compress the rest
  head -50 "$OLD_NOTE" > "$OLD_NOTE.compressed"
  echo "\n[Compressed $(wc -l < "$OLD_NOTE") lines → 50 line summary]" \
    >> "$OLD_NOTE.compressed"
  mv "$OLD_NOTE.compressed" "$OLD_NOTE"
fi

# 5. Create tomorrow's daily note from template
TOMORROW=$(date -v+1d +%Y-%m-%d 2>/dev/null || date -d "tomorrow" +%Y-%m-%d)
cp "$MEMORY_DIR/daily_template.md" "$MEMORY_DIR/daily/$TOMORROW.md"
sed -i '' "s/YYYY-MM-DD/$TOMORROW/g" "$MEMORY_DIR/daily/$TOMORROW.md"

# 6. Heartbeat
echo "$(date +%Y-%m-%d\ %H:%M) MTN | NIGHTLY COMPLETE" \
  >> "$MEMORY_DIR/heartbeat.md"

echo "Consolidation complete: $(date +%H:%M)" >> "$DAILY_NOTE"
```

---

## PART 6 — MEMORY COMPACTION (02:30 AM)

Runs once a night during lowest activity window.
Compresses old files, deduplicates patterns, archives noise.

```bash
#!/bin/bash
# memory_compact.sh
# Runs at 02:30 AM MTN

MEMORY_DIR="$HOME/Documents/Projects/Kai/memory"
ARCHIVE_DIR="$MEMORY_DIR/daily/archive"
mkdir -p "$ARCHIVE_DIR"

# Move files older than 30 days to monthly archive
find "$MEMORY_DIR/daily" -maxdepth 1 -name "*.md" -mtime +30 | while read f; do
  MONTH=$(basename "$f" | cut -c1-7)  # YYYY-MM
  cat "$f" >> "$ARCHIVE_DIR/$MONTH.md"
  echo "\n---\n" >> "$ARCHIVE_DIR/$MONTH.md"
  rm "$f"
done

# Deduplicate pattern library (remove identical lines)
sort -u "$MEMORY_DIR/patterns/pattern_library.md" \
  > "$MEMORY_DIR/patterns/pattern_library.md.tmp"
mv "$MEMORY_DIR/patterns/pattern_library.md.tmp" \
  "$MEMORY_DIR/patterns/pattern_library.md"

# Rotate system logs
for log in healthcheck monitor escalation; do
  LOG_FILE="$HOME/Documents/Projects/Kai/logs/$log.log"
  if [ -f "$LOG_FILE" ]; then
    # Keep last 2000 lines
    tail -2000 "$LOG_FILE" > "$LOG_FILE.tmp"
    mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
done

echo "Memory compaction complete: $(date)" \
  >> "$HOME/Documents/Projects/Kai/logs/memory.log"
```

---

## PART 7 — OPTIMIZATION RECOMMENDATIONS

### From GitHub Research

**memsearch** — Markdown-first, BM25 + vector hybrid search.
Best for this scale. Free. Install on Mac Mini:
```bash
pip install memsearch --break-system-packages
```

**ReMe (agentscope-ai/ReMe)** — diary-based memory with nightly
summarization. Matches exactly how Kai's memory is structured.
Plug in directly to the daily note system.

**sqlite-memory** — Zero-config SQLite extension for semantic search.
No external database. Single file. Works offline. Recommended when
memory grows beyond 200 files.

### Performance Rules From Research

<from DEV Community + Databricks>

1. **Start with Tier 1 and Tier 2 only.** Semantic search (Tier 3) is
   only needed above ~500 memory files. Don't add it prematurely.

2. **Markdown is the source of truth. Always.** SQLite is a rebuildable
   index. If it corrupts, you delete it and rebuild from markdown.
   You cannot rebuild markdown from a corrupted database.

3. **60/40 rule for memory file size.** Keep the model footprint
   (context) below 60% of available memory. Leave 40% for KV cache
   and OS. On 16GB Mac Mini: keep loaded context under 9GB.

4. **Content-hash deduplication.** Before writing any memory entry,
   hash the content. Skip if already written. memsearch does this
   automatically. Prevents the memory from filling with duplicates.

5. **Temporal grounding on every entry.** Every memory write includes
   a timestamp. Without timestamps, the agent cannot reason about
   "what happened before X" or "has this changed recently."

6. **One write per event, not one write per thought.** Agents that
   write to memory after every reasoning step create noise faster
   than signal. Write when something actually happened or was decided.

### The Three Questions That Determine Memory Quality

From agentmemory research:

> "Memory quality is not measured by how much is stored.
> It is measured by how accurately the agent recalls what matters
> and how completely it forgets what doesn't."

Before writing to memory, ask:
1. Will this still matter in 7 days?
2. Would the agent need this to make a future decision?
3. Is this a fact (Layer 1), an event (Layer 2), or a rule (Layer 3)?

Write to the correct layer. Never mix layers in one file.

---

## QUICK REFERENCE CARD

```
HEALTHCHECK          every 15 min    healthcheck.sh
BUSINESS MONITOR     every 30 min    business_monitor.sh
ESCALATION CHECK     every hour      escalate_blocked.sh
AETHERBOT ANALYSIS   17:00 MTN       kai_analysis.py
NIGHTLY CONSOLIDATION 23:50 MTN      nightly_consolidation.sh
MEMORY COMPACTION    02:30 AM MTN    memory_compact.sh
OVERNIGHT RESEARCH   03:00 AM MTN    overnight_research.sh
MORNING BRIEF        06:30 AM MTN    morning_brief.sh

TICKET CLOSE REQUIRES:
  verify.sh all checks PASS
  gate agent sign-off
  evidence filed
  git commit with ticket ID

MEMORY LAYERS:
  Layer 1 → Kai_Initialization_v2.md  (durable facts)
  Layer 2 → daily/YYYY-MM-DD.md       (events, written live)
  Layer 3 → tacit.md                  (rules, updated nightly)

RECALL TIERS:
  Tier 1 → direct file read    (every session)
  Tier 2 → grep text search    (recent history)
  Tier 3 → semantic search     (cross-session patterns)
```
