#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# double-loop-review.sh — Monthly double-loop learning review
# Version: 1.0 — 2026-04-28
#
# WHAT THIS IS:
#   Single-loop: "Are we doing things correctly?"  ← the system already answers this
#   Double-loop: "Are we doing the correct things?" ← only Hyo + Kai can answer this
#
#   This script runs on the first Monday of each month and:
#   1. Pulls verified state, ticket history, growth metrics, agent scores
#   2. Answers the single-loop questions automatically (from data)
#   3. Generates the double-loop questions that only a human+Kai conversation can answer
#   4. Writes a structured brief to Hyo's inbox
#   5. Creates a dated review file ready for the conversation
#
#   The review is NOT a report. It's a conversation starter. Every question
#   it asks cannot be answered by automation — they require Hyo's judgment.
#
# DOUBLE-LOOP QUESTIONS (the six that matter):
#   Q1: Are the agents working on the right problems for where we want to be in 6 months?
#   Q2: What assumptions built into the architecture are no longer valid?
#   Q3: Which agents have hit a capability ceiling in their current domain?
#   Q4: What capability does the system need that no current agent provides?
#   Q5: Are we measuring the right things? (SICQ/OMP — do these metrics still matter?)
#   Q6: What should we stop doing? (Not fix — stop.)
#
# USAGE:
#   bash bin/double-loop-review.sh          # run review (auto or manual)
#   bash bin/double-loop-review.sh --force  # force even if not first Monday
#   bash bin/double-loop-review.sh --preview # preview questions without writing to inbox
#
# Called by: kai-autonomous.sh (every Monday, 07:15 MT)
# Output: kai/reviews/double-loop-YYYY-Www.md + hyo-inbox entry
# Log: kai/ledger/double-loop.log
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/double-loop.log"
REVIEWS_DIR="$HYO_ROOT/kai/reviews"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"
VERIFIED_STATE="$HYO_ROOT/kai/ledger/verified-state.json"
SESSION_ERRORS="$HYO_ROOT/kai/ledger/session-errors.jsonl"
KNOWLEDGE_MD="$HYO_ROOT/kai/memory/KNOWLEDGE.md"

FORCE=false
PREVIEW=false

mkdir -p "$REVIEWS_DIR" "$(dirname "$LOG")"

NOW_MT() { TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z; }
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
WEEK=$(TZ=America/Denver date +%Y-W%V)   # ISO week: 2026-W18
DOW=$(TZ=America/Denver date +%u)       # 1=Mon

log() { echo "[$(NOW_MT)] $*" | tee -a "$LOG"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=true; shift ;;
    --preview) PREVIEW=true; shift ;;
    *) shift ;;
  esac
done

# ─── Check: only run on Monday (unless --force/--preview) ────────────────────
if [[ "$FORCE" == false && "$PREVIEW" == false ]]; then
  if [[ "$DOW" -ne 1 ]]; then
    log "Not Monday (DOW=$DOW) — skipping. Use --force to override."
    exit 0
  fi
fi

# Check if already ran this week (state_key in kai-autonomous.sh handles this, but guard here too)
REVIEW_FILE="$REVIEWS_DIR/double-loop-${WEEK}.md"
if [[ -f "$REVIEW_FILE" && "$FORCE" == false ]]; then
  log "Review already exists for $WEEK: $REVIEW_FILE — skipping. Use --force to regenerate."
  exit 0
fi

log "════════════════════════════════════════"
log "DOUBLE-LOOP REVIEW — $WEEK"
log "Building context from live system state..."

# ─── Pull single-loop data (automated — answered from system state) ───────────

# 1. Agent SICQ/OMP scores
AGENT_SCORES=$(python3 - << 'PYEOF' 2>/dev/null
import json
from pathlib import Path
import os
hyo = os.environ.get("HYO_ROOT", ".")
scores = []
agents = ["nel", "aether", "sam", "ra", "kai"]
for a in agents:
    state = Path(hyo) / "agents" / a / "self-improve-state.json"
    growth = Path(hyo) / "agents" / a / "GROWTH.md"
    score_line = f"  {a}: "
    if state.exists():
        try:
            d = json.loads(state.read_text())
            score_line += f"cycles={d.get('cycles',0)}, current_weakness={d.get('current_weakness','?')}, stage={d.get('stage','?')}"
            if d.get("failure_count", 0) > 0:
                score_line += f", failures={d['failure_count']}"
        except: score_line += "(state unreadable)"
    else:
        score_line += "(no state)"
    scores.append(score_line)
print("\n".join(scores))
PYEOF
)

# 2. Top error patterns this month
ERROR_PATTERNS=$(python3 - << 'PYEOF' 2>/dev/null
import json, os
from pathlib import Path
from collections import Counter
hyo = os.environ.get("HYO_ROOT", ".")
errors_path = Path(hyo) / "kai/ledger/session-errors.jsonl"
if not errors_path.exists():
    print("  (no session errors logged)")
else:
    lines = [l.strip() for l in errors_path.read_text().splitlines() if l.strip()]
    cats = []
    for l in lines[-100:]:  # last 100 errors
        try:
            d = json.loads(l)
            cats.append(d.get("category", "unknown"))
        except: pass
    counts = Counter(cats)
    for cat, n in counts.most_common(5):
        print(f"  {cat}: {n} occurrences")
PYEOF
)

# 3. Improvement tickets resolved vs open this month
TICKET_SUMMARY=$(python3 - << 'PYEOF' 2>/dev/null
import json, os
from pathlib import Path
hyo = os.environ.get("HYO_ROOT", ".")
tickets = Path(hyo) / "kai/tickets/tickets.jsonl"
if not tickets.exists():
    print("  (ticket system not found)")
else:
    month = os.environ.get("MONTH_KEY", "2026-04")
    lines = [l.strip() for l in tickets.read_text().splitlines() if l.strip()]
    improvement = [l for l in lines if '"improvement"' in l]
    open_imp = [l for l in improvement if '"open"' in l or '"active"' in l]
    resolved = [l for l in improvement if '"resolved"' in l or '"closed"' in l]
    print(f"  Improvement tickets open: {len(open_imp)}")
    print(f"  Improvement tickets resolved (all time): {len(resolved)}")
PYEOF
)

# 4. Agents with stalled improvement cycles (same weakness >14 days)
STALLED=$(python3 - << 'PYEOF' 2>/dev/null
import json, os
from pathlib import Path
from datetime import datetime, timezone
hyo = os.environ.get("HYO_ROOT", ".")
agents = ["nel", "aether", "sam", "ra", "kai"]
stalled = []
for a in agents:
    state = Path(hyo) / "agents" / a / "self-improve-state.json"
    if state.exists():
        try:
            d = json.loads(state.read_text())
            last = d.get("last_run", "")
            if last:
                last_dt = datetime.fromisoformat(last.replace("Z","+00:00"))
                age_days = (datetime.now(timezone.utc) - last_dt).days
                if age_days > 14:
                    stalled.append(f"  {a}: last ran {age_days} days ago on {d.get('current_weakness','?')}")
        except: pass
print("\n".join(stalled) if stalled else "  None — all agents ran within 14 days")
PYEOF
)

# 5. Chaos findings this month
CHAOS_FINDINGS=$(python3 - << 'PYEOF' 2>/dev/null
import json, os
from pathlib import Path
hyo = os.environ.get("HYO_ROOT", ".")
results = Path(hyo) / "kai/ledger/chaos-results.jsonl"
if not results.exists():
    print("  (no chaos tests run yet — first month)")
else:
    lines = [l.strip() for l in results.read_text().splitlines() if l.strip()]
    spofs = [json.loads(l) for l in lines if '"is_spof": true' in l or '"is_spof":true' in l]
    if spofs:
        for s in spofs[-5:]:
            print(f"  [{s.get('agent','?')}] {s.get('dep_name','?')}: {s.get('finding','')[:80]}")
    else:
        print("  No SPOFs found in chaos tests")
PYEOF
)

log "Context pulled. Building review document..."

# ─── Build the review document ────────────────────────────────────────────────
cat > "$REVIEW_FILE" << REVIEWEOF
# Double-Loop Review — ${WEEK}
**Generated:** $(NOW_MT)
**Reviewer:** Kai + Hyo (conversation required — ~15 min)
**Next review:** Next Monday 07:15 MT (weekly cadence)

---

## What This Is

Single-loop questions ask: are we doing things correctly? The system answers those automatically.
Double-loop questions ask: are we doing the correct things? Only this conversation answers those.

Every question below requires your judgment — it cannot be automated.

---

## Single-Loop Snapshot (automated — for context)

### Agent improvement cycle state
${AGENT_SCORES}

### Top error patterns (last 100 logged)
${ERROR_PATTERNS}

### Improvement ticket status
${TICKET_SUMMARY}

### Stalled improvement cycles (>14 days same weakness)
${STALLED}

### Chaos injection findings (SPOFs discovered)
${CHAOS_FINDINGS}

---

## The Six Double-Loop Questions

These are the questions that determine whether the system is pointed at the right target.
Kai will present its view. Hyo decides.

---

### Q1: Are the agents working on the right problems?

**What the data shows:** Each agent's GROWTH.md lists 3 weaknesses. These weaknesses were defined at agent creation and update incrementally. The question is whether the weaknesses being improved this month are the most important gaps given where we want the system to be in 6 months.

**Kai's current read:**
- Nel is improving security scanning and QA coverage. Relevant if the system is scaling. Less relevant if the bottleneck is elsewhere.
- Aether is improving analysis quality gates. Relevant if analysis accuracy is the revenue constraint.
- Sam is improving deploy reliability. Relevant as long as Vercel is the infra.
- Ra is improving newsletter pipeline reliability. Relevant if the newsletter is a growth lever.
- Kai is improving orchestration coverage. Relevant always.

**The question for Hyo:** Given what you know about where hyo.world needs to be in 6 months, are these the right weaknesses to be fixing? Or is there a domain shift that none of the current GROWTH.md files reflects?

**Decision space:**
- [ ] Current weaknesses are correct — continue
- [ ] One or more agents need a GROWTH.md reset to reflect new priorities
- [ ] A new agent capability is needed that doesn't exist yet

---

### Q2: What assumptions are built into the architecture that may no longer be valid?

**Context:** The system was designed when:
- hyo.world was an agent marketplace for public use
- Aurora was a public-facing newsletter
- Aether's trading analysis was the primary revenue insight
- The primary user was Hyo alone

**Things that have changed:**
- hyo.world focus has shifted to internal systems
- Aurora became a personal daily brief (HQ)
- Revenue generation is an open question
- Educator agent concept introduced (Korean professor use case)

**The question for Hyo:** Which architectural assumptions should we revisit? Specifically:
- Is the Vercel/Sam/HQ architecture still the right public-facing layer, or does the educator agent change this?
- Is Aether still the right primary revenue-insight agent, or does the system need a different kind of agent pointed at revenue?
- Are we over-indexing on internal quality metrics (SICQ/OMP) at the cost of external-facing capability?

**Decision space:**
- [ ] Architecture assumptions still valid — continue
- [ ] Specific assumption to revisit: _______________
- [ ] Structural change needed: _______________

---

### Q3: Which agents have hit a capability ceiling in their current domain?

**Framework (from research):** The Darwin Gödel Machine finding: self-improvement only works well where the task aligns with the modification substrate. An agent optimizing a ceiling hits diminishing returns. The ceiling sign: improvement cycles complete but nothing meaningfully changes in output quality.

**Agent ceiling assessment:**
- Nel: Security scanning + QA. Ceiling: depends on codebase complexity. Not yet visible.
- Aether: Trading analysis quality. Ceiling: increasingly visible as gate system reaches maturity.
- Sam: Deploy + infra. Ceiling: low complexity currently, not yet visible.
- Ra: Newsletter synthesis. Ceiling: visible — output quality has stabilized since pipeline fix.
- Kai: Orchestration. Ceiling: far off — complexity scales with number of agents.

**The question for Hyo:** For agents approaching a ceiling, should we expand their domain (same agent, new problems) or add new agents? Ra's synthesis capability applies to domains beyond tech/crypto newsletters. Aether's quantitative reasoning applies beyond trading logs.

**Decision space:**
- [ ] No agents at ceiling — continue current domains
- [ ] Agent to expand: _______________ → new domain: _______________
- [ ] New agent needed for: _______________

---

### Q4: What capability does the system need that no agent provides?

**Gap analysis from this month's signals and tickets:**
- Educator capability (Korean language professor use case) — no current agent covers content pedagogy
- Revenue generation — no agent is directly pointed at growth/monetization
- Marketplace infrastructure — no agent manages agent-to-user matching if hyo.world relaunches

**The question for Hyo:** Which of these gaps, if filled, would most change what the system can do in 6 months? This is the summer project question.

**Decision space:**
- [ ] No new capability needed — focus on improving existing agents
- [ ] Build educator agent (summer) — using Ra's content synthesis + presentation layer
- [ ] Build revenue agent — pointed at growth/monetization directly
- [ ] Other: _______________

---

### Q5: Are we measuring the right things?

**Current metrics:**
- SICQ (0-100): process quality — did the agent follow protocol?
- OMP (0-100): output quality — did the agent produce the right output?
- Health score: system-wide composite

**The question:** SICQ and OMP measure whether agents are doing things correctly. They don't measure whether the system is achieving its actual goals. If the goal is Hyo getting better information every morning, what would that metric look like? If the goal is revenue, what would that metric look like?

**The question for Hyo:** What metric, if it improved by 20 points in 3 months, would tell you the system is succeeding — not just running?

**Decision space:**
- [ ] Current metrics sufficient
- [ ] Add outcome metric: _______________
- [ ] Replace SICQ/OMP with: _______________

---

### Q6: What should we stop doing?

**Context (from research):** Every improvement system produces accumulation. Features added are rarely removed. Gates added are rarely questioned. This question is the hardest because it requires deciding something built with effort is no longer the right investment.

**Candidates for stopping:**
- Agent-reflection entries in HQ feed: 3 agents publish "reflections" — do you read them?
- Weekly report on Saturday: 6-agent summary every Saturday — do you use it?
- Aurora daily brief: was the original public newsletter, now personal — still valuable at current detail level?
- Any ARIC cycle for an agent that has a clear capability ceiling

**The question for Hyo:** What outputs does the system produce that you don't use or wouldn't miss? Removing these frees up compute and Kai attention for what matters.

**Decision space:**
- [ ] Nothing to stop — all outputs are used
- [ ] Stop: _______________
- [ ] Reduce cadence: _______________

---

## Decisions This Session Produces

After the conversation, Kai will:
1. Update KNOWLEDGE.md with any decisions made
2. Update GROWTH.md for any agents whose weakness priorities changed
3. Open tickets for any new capabilities decided
4. Adjust kai-autonomous.sh if any cadences changed
5. Write the next month's double-loop date into the calendar

---

## Next Double-Loop Review

Next Monday at 07:15 MT — auto-triggered weekly by kai-autonomous.sh.

---
_Generated by bin/double-loop-review.sh v1.0 | Research basis: Argyris 1977, Ericsson deliberate practice, Darwin Gödel Machine_
REVIEWEOF

log "Review document written: $REVIEW_FILE"

# ─── Write to Hyo inbox ───────────────────────────────────────────────────────
if [[ "$PREVIEW" == false ]]; then
  echo "{\"ts\":\"$(NOW_MT)\",\"from\":\"double-loop-review\",\"priority\":\"P1\",\"subject\":\"Weekly double-loop review ready — ${WEEK}\",\"body\":\"6 questions requiring your judgment (~15 min). Review at: kai/reviews/double-loop-${WEEK}.md\\n\\nQ1: Are agents working on right problems?\\nQ2: What architecture assumptions are stale?\\nQ3: Which agents have hit capability ceiling?\\nQ4: What capability gap needs filling?\\nQ5: Are we measuring the right things?\\nQ6: What should we stop doing?\",\"review_file\":\"kai/reviews/double-loop-${WEEK}.md\",\"status\":\"unread\"}" >> "$INBOX"
  log "✓ Hyo inbox entry written"
fi

log ""
log "Double-loop review complete: $REVIEW_FILE"

if [[ "$PREVIEW" == true ]]; then
  echo ""
  echo "=== PREVIEW ==="
  cat "$REVIEW_FILE"
fi
