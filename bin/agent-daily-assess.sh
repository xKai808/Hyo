#!/usr/bin/env bash
# bin/agent-daily-assess.sh — Daily weakness identification & assessment
#
# PURPOSE:
#   Runs BEFORE agent-self-improve.sh (4:00 AM vs 4:30 AM).
#   Produces a structured JSON assessment per agent that answers 8 mandatory questions.
#   Self-improve Phase 3 reads this assessment — NOT a static prompt — so research
#   is always grounded in today's actual data, not stale GROWTH.md state.
#
# OUTPUT: agents/<name>/ledger/daily-assess-YYYY-MM-DD.json
#   {
#     "agent": "kai",
#     "date": "2026-04-28",
#     "Q1_outputs": "...",        # What did this agent produce in last 7 days?
#     "Q2_failures": "...",       # What failed, errored, or was flagged?
#     "Q3_consumers": "...",      # Which outputs actually reached a consumer?
#     "Q4_top_weakness": "W1",    # Which active weakness is most urgent right now?
#     "Q4_urgency_reason": "...", # Why this one, not another?
#     "Q5_goal_status": "...",    # Which goals are overdue? Which are on track?
#     "Q6_external_signal": "...",# What does external research say about this weakness?
#     "Q7_hypothesis": "...",     # Specific testable hypothesis for today's fix attempt
#     "Q8_success_measure": "...",# How will we know it worked? Exact measurable outcome
#     "weakness_priority": ["W1","W2"],  # ordered by urgency
#     "skip_reasons": {},         # {weakness_id: reason} for any that are skipped
#     "assessment_quality": "HIGH|MEDIUM|LOW",
#     "generated_by": "claude_code|python_fallback"
#   }
#
# WIRE: kai-autonomous.sh 04:00 MT → agent-daily-assess.sh all
#       kai-autonomous.sh 04:30 MT → agent-self-improve.sh all (reads today's assess)
#
# If assess file is missing at 4:30 AM, self-improve generates a minimal one inline.
# If assess file is >30h old, it is regenerated regardless.
#
# VERSION: 1.0 — 2026-04-28
# REQUIRED BY: AGENT_RESEARCH_CYCLE.md Phase 1-2 (OBSERVE + ORIENT)

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TARGET="${1:-all}"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
NOW_EPOCH=$(date +%s)
LOG="$HYO_ROOT/kai/ledger/daily-assess.log"
ISSUES_LOG="$HYO_ROOT/kai/ledger/daily-issues.jsonl"
MEMORY_ENGINE="$HYO_ROOT/kai/memory/agent_memory/memory_engine.py"
MAX_AGE_SECONDS=108000  # 30 hours

AGENTS="nel sam aether ra dex kai"
[[ "$TARGET" != "all" ]] && AGENTS="$TARGET"

mkdir -p "$(dirname "$LOG")"
log() { echo "[$NOW_MT] assess: $*" | tee -a "$LOG"; }

_find_claude_bin() {
  for candidate in \
    "$HOME/.claude/local/claude" \
    "/usr/local/bin/claude" \
    "/opt/homebrew/bin/claude" \
    "$(which claude 2>/dev/null)"; do
    [[ -x "$candidate" ]] && echo "$candidate" && return 0
  done
  return 1
}

# ─── Check if today's assessment is fresh ────────────────────────────────────
needs_assessment() {
  local agent="$1"
  local assess_file="$HYO_ROOT/agents/$agent/ledger/daily-assess-${TODAY}.json"
  [[ ! -f "$assess_file" ]] && return 0  # missing → need
  local mtime
  mtime=$(stat -f %m "$assess_file" 2>/dev/null || stat -c %Y "$assess_file" 2>/dev/null || echo 0)
  [[ $(( NOW_EPOCH - mtime )) -gt $MAX_AGE_SECONDS ]] && return 0  # stale → need
  return 1  # fresh → skip
}

# ─── Core: gather evidence for an agent ─────────────────────────────────────
gather_agent_evidence() {
  local agent="$1"
  python3 - "$HYO_ROOT" "$agent" "$TODAY" << 'PYEOF'
import json, os, re, sys
from pathlib import Path
from datetime import datetime, timezone, timedelta

hyo_root = Path(sys.argv[1])
agent = sys.argv[2]
today = sys.argv[3]
agent_dir = hyo_root / "agents" / agent
seven_days_ago = (datetime.now() - timedelta(days=7)).strftime('%Y-%m-%d')

def read_tail(path, n=100):
    try:
        lines = Path(path).read_text().splitlines()
        return '\n'.join(lines[-n:])
    except: return ""

def read_jsonl(path, n=30, since_date=None):
    try:
        entries = []
        for line in Path(path).read_text().splitlines():
            try:
                e = json.loads(line)
                if since_date and e.get('date','') < since_date and e.get('ts','') < since_date:
                    continue
                entries.append(e)
            except: pass
        return entries[-n:]
    except: return []

# Q1: Outputs in last 7 days
log_dir = agent_dir / "logs"
outputs = []
if log_dir.exists():
    for f in sorted(log_dir.glob("*.md"), key=os.path.getmtime)[-7:]:
        if f.stem >= seven_days_ago[:10]:
            size = f.stat().st_size
            outputs.append(f"{f.name} ({size}B)")
q1 = f"{len(outputs)} log files in 7d: {', '.join(outputs[-3:]) or 'none'}"

# Q2: Failures/flags in last 7 days
issues = read_jsonl(hyo_root / "kai/ledger/daily-issues.jsonl", n=50, since_date=seven_days_ago)
agent_issues = [i for i in issues if i.get('agent') == agent]
tickets_path = hyo_root / "kai/tickets/tickets.jsonl"
active_tickets = []
if tickets_path.exists():
    for line in tickets_path.read_text().splitlines()[-200:]:
        try:
            t = json.loads(line)
            if t.get('agent') == agent and t.get('status') == 'ACTIVE':
                active_tickets.append(t.get('title','?')[:60])
        except: pass
q2 = f"{len(agent_issues)} issues last 7d | {len(active_tickets)} active tickets"
if agent_issues:
    q2 += f" | Recent: {agent_issues[-1].get('description','?')[:100]}"
if active_tickets:
    q2 += f" | Top ticket: {active_tickets[0]}"

# Q3: Which outputs reached a consumer (feed entries)
feed_file = hyo_root / "agents/sam/website/data/feed.json"
feed_entries = []
if feed_file.exists():
    try:
        feed = json.loads(feed_file.read_text())
        for r in feed.get('reports', []):
            rid = r.get('id','')
            if agent in rid and rid >= f"{agent}-daily-{seven_days_ago}":
                feed_entries.append(rid)
    except: pass
q3 = f"{len(feed_entries)} HQ feed entries in 7d: {', '.join(feed_entries[-3:]) or 'none published'}"

# Q4: Which weakness is most urgent?
growth_file = agent_dir / "GROWTH.md"
weaknesses = []
overdue_goals = []
if growth_file.exists():
    content = growth_file.read_text()
    # Parse weaknesses
    for m in re.finditer(r'###\s+([WE]\d+):\s*(.+?)\n.*?\*\*Severity:\*\*\s*(\w+).*?\*\*Status:\*\*\s*(\w+)', content, re.DOTALL):
        wid, title, sev, status = m.group(1), m.group(2).strip(), m.group(3), m.group(4)
        if status.lower() != 'resolved':
            weaknesses.append({'id': wid, 'title': title, 'severity': sev})
    # Parse overdue goals
    today_str = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    for m in re.finditer(r'\|\s*(G\d+)\s*\|[^|]+\|\s*(\d{4}-\d{2}-\d{2})\s*\|[^|]+\|\s*([WE]\d+)\s*\|', content):
        gid, deadline, wid = m.group(1), m.group(2), m.group(3)
        if deadline < today_str:
            overdue_goals.append({'goal': gid, 'deadline': deadline, 'weakness': wid})

# Sort by severity then overdue
severity_order = {'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3}
overdue_ids = {g['weakness'] for g in overdue_goals}
weaknesses.sort(key=lambda w: (0 if w['id'] in overdue_ids else 1, severity_order.get(w.get('severity','P2'), 2)))

# Q4 output
top_weakness = weaknesses[0]['id'] if weaknesses else 'W1'
urgency_reason = ""
if top_weakness in overdue_ids:
    g = next(g for g in overdue_goals if g['weakness'] == top_weakness)
    urgency_reason = f"Goal {g['goal']} deadline {g['deadline']} OVERDUE — highest urgency"
elif weaknesses:
    urgency_reason = f"Severity {weaknesses[0].get('severity','?')} active weakness — no overdue goals"
else:
    urgency_reason = "No weaknesses found in GROWTH.md — needs refresh"

q4_weakness = top_weakness
q4_reason = urgency_reason

# Q5: Goal status
q5 = f"{len(overdue_goals)} overdue goals | {len(weaknesses)} active weaknesses"
if overdue_goals:
    q5 += f" | OVERDUE: {', '.join([g['goal']+' ('+g['weakness']+')' for g in overdue_goals])}"

# Q6: External signal (from today's findings if available)
findings_file = agent_dir / "research" / f"findings-{today}.md"
q6 = ""
if findings_file.exists():
    content = findings_file.read_text()
    # Extract first 300 chars of findings
    q6 = content[:300].replace('\n', ' ')
else:
    q6 = "No external findings today — agent-research.sh not yet run for today"

# Q7: Hypothesis (derived from weakness + evidence)
w_title = weaknesses[0]['title'] if weaknesses else "unknown"
if growth_file.exists():
    content = growth_file.read_text()
    m = re.search(rf'###\s+{re.escape(top_weakness)}[:\s].+?Fix approach[:\*]+\s*\n(.+?)(?=\n\*\*|\n###|\Z)', content, re.DOTALL)
    fix_approach = m.group(1).strip()[:200] if m else "See GROWTH.md"
else:
    fix_approach = "GROWTH.md missing"
q7 = f"Hypothesis: Implementing {fix_approach[:150]} will resolve {top_weakness} ({w_title}). Test: verify specific file changes match FILES_TO_CHANGE."

# Q8: Success measure
q8 = f"SUCCESS when: (1) FILES_TO_CHANGE from research plan are modified, (2) verify_improvement() passes for {top_weakness}, (3) evolution.jsonl entry shows outcome=success, (4) GROWTH.md status updated to in_progress or resolved."

# Assessment quality
quality = "HIGH" if (len(outputs) > 0 and len(weaknesses) > 0 and q6 != "") else \
          "MEDIUM" if (len(weaknesses) > 0) else "LOW"

weakness_priority = [w['id'] for w in weaknesses[:5]]
skip_reasons = {}
if not weaknesses:
    skip_reasons['all'] = "GROWTH.md has no active weaknesses — needs agent self-assessment"

result = {
    "agent": agent,
    "date": today,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "Q1_outputs_7d": q1,
    "Q2_failures_7d": q2,
    "Q3_consumer_reach": q3,
    "Q4_top_weakness": q4_weakness,
    "Q4_urgency_reason": q4_reason,
    "Q5_goal_status": q5,
    "Q6_external_signal": q6,
    "Q7_hypothesis": q7,
    "Q8_success_measure": q8,
    "weakness_priority": weakness_priority,
    "overdue_goals": overdue_goals,
    "skip_reasons": skip_reasons,
    "assessment_quality": quality,
    "generated_by": "python_evidence_gather"
}
print(json.dumps(result, indent=2))
PYEOF
}

# ─── Claude Code enhanced assessment (when auth available) ────────────────────
enhance_with_claude() {
  local agent="$1" evidence_json="$2"
  local claude_bin
  claude_bin=$(_find_claude_bin 2>/dev/null) || return 1

  local top_weakness q2_failures q6_external
  top_weakness=$(echo "$evidence_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Q4_top_weakness','W1'))")
  q2_failures=$(echo "$evidence_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Q2_failures_7d',''))")
  q6_external=$(echo "$evidence_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Q6_external_signal',''))")

  local enhance_prompt
  enhance_prompt=$(cat << PROMPT
You are performing a daily self-assessment for agent: $agent
Date: $TODAY

Evidence gathered automatically:
- Failures/flags last 7d: $q2_failures
- Top weakness to address: $top_weakness
- External research signal: $q6_external

You must answer these 3 questions with specificity. No generic answers. Use the evidence.

Q7_HYPOTHESIS: Write one specific, testable hypothesis for what today's fix attempt will prove.
Format: "If we [specific action], then [specific measurable outcome] because [root cause]."

Q8_SUCCESS_MEASURE: Define exactly what "fixed" looks like for $top_weakness.
Format: List 3 measurable conditions that must ALL be true for this weakness to be resolved.

Q4_URGENCY_REFINEMENT: Based on the external signal and internal evidence,
is $top_weakness still the right priority? Or does the external signal point to something more urgent?
Answer: CONFIRM [weakness] | REDIRECT to [other weakness] because [specific reason from evidence]

Output exactly these 3 keys, nothing else.
PROMPT
)

  local claude_output
  claude_output=$(echo "$enhance_prompt" | "$claude_bin" \
    -p --output-format text --dangerously-skip-permissions 2>/dev/null || echo "")

  if echo "$claude_output" | grep -q "Not logged in\|Please run /login\|Authentication required"; then
    return 1
  fi

  [[ -n "$claude_output" ]] && echo "$claude_output" && return 0
  return 1
}

# ─── Write assessment file ─────────────────────────────────────────────────────
write_assessment() {
  local agent="$1" evidence_json="$2" claude_enhancement="$3"
  local assess_file="$HYO_ROOT/agents/$agent/ledger/daily-assess-${TODAY}.json"

  if [[ -n "$claude_enhancement" ]]; then
    # Merge Claude's enhanced answers into the base evidence JSON
    python3 - "$assess_file" "$claude_enhancement" << PYEOF
import json, sys, re
from pathlib import Path

assess_file = sys.argv[1]
enhancement = sys.argv[2]

base = ${evidence_json}

# Extract Claude's enhanced answers
q7_m = re.search(r'Q7_HYPOTHESIS:\s*(.+?)(?=Q8_|Q4_|\Z)', enhancement, re.DOTALL)
q8_m = re.search(r'Q8_SUCCESS_MEASURE:\s*(.+?)(?=Q7_|Q4_|\Z)', enhancement, re.DOTALL)
q4_m = re.search(r'Q4_URGENCY_REFINEMENT:\s*(.+?)(?=Q7_|Q8_|\Z)', enhancement, re.DOTALL)

if q7_m: base['Q7_hypothesis'] = q7_m.group(1).strip()[:500]
if q8_m: base['Q8_success_measure'] = q8_m.group(1).strip()[:500]
if q4_m:
    refinement = q4_m.group(1).strip()
    if refinement.startswith('REDIRECT'):
        m = re.search(r'REDIRECT\s+to\s+([WE]\d+)', refinement)
        if m:
            base['Q4_top_weakness'] = m.group(1)
            base['Q4_urgency_reason'] += f' | Claude refinement: {refinement[:200]}'
base['generated_by'] = 'claude_enhanced'
base['assessment_quality'] = 'HIGH'

Path(assess_file).write_text(json.dumps(base, indent=2))
print(f"Assessment written (claude-enhanced): {assess_file}")
PYEOF
  else
    echo "$evidence_json" > "$assess_file"
    log "  Assessment written (python evidence): $assess_file"
  fi
}

# ─── Main loop ─────────────────────────────────────────────────────────────────
log "=== Daily assessment: $TODAY (agents: $AGENTS) ==="
ASSESSED=0
SKIPPED=0
FAILED=0

for agent in $AGENTS; do
  agent_dir="$HYO_ROOT/agents/$agent"
  [[ ! -d "$agent_dir" ]] && log "SKIP: $agent — no agent dir" && SKIPPED=$((SKIPPED+1)) && continue

  if ! needs_assessment "$agent"; then
    log "SKIP: $agent — assessment fresh (< 30h)"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  log "Assessing: $agent"
  mkdir -p "$agent_dir/ledger"

  # Step 1: Gather evidence (always works, no auth needed)
  local_evidence=$(gather_agent_evidence "$agent" 2>/dev/null || echo "")
  if [[ -z "$local_evidence" ]]; then
    log "  FAIL: evidence gather returned empty for $agent"
    FAILED=$((FAILED+1))
    continue
  fi

  # Step 2: Try Claude enhancement (requires auth)
  claude_plus=""
  if claude_bin=$(_find_claude_bin 2>/dev/null); then
    auth_test=$("$claude_bin" -p "echo ok" --output-format text 2>&1 | head -1 || true)
    if ! echo "$auth_test" | grep -q "Not logged in\|Please run /login"; then
      log "  Enhancing with Claude Code..."
      claude_plus=$(enhance_with_claude "$agent" "$local_evidence" 2>/dev/null || echo "")
      [[ -n "$claude_plus" ]] && log "  ✓ Claude enhancement applied"
    fi
  fi

  # Step 3: Write assessment
  assess_file="$HYO_ROOT/agents/$agent/ledger/daily-assess-${TODAY}.json"
  if [[ -n "$claude_plus" ]]; then
    # Merge into JSON
    python3 -c "
import json, re, sys
from pathlib import Path
base = json.loads('''$(echo "$local_evidence" | sed "s/'/'\\\\''/g")''')
enhancement = '''$claude_plus'''
q7 = re.search(r'Q7_HYPOTHESIS:\s*(.+?)(?=Q8_|Q4_|\Z)', enhancement, re.DOTALL)
q8 = re.search(r'Q8_SUCCESS_MEASURE:\s*(.+?)(?=Q7_|Q4_|\Z)', enhancement, re.DOTALL)
q4 = re.search(r'Q4_URGENCY_REFINEMENT:\s*(.+?)(?=Q7_|Q8_|\Z)', enhancement, re.DOTALL)
if q7: base['Q7_hypothesis'] = q7.group(1).strip()[:500]
if q8: base['Q8_success_measure'] = q8.group(1).strip()[:500]
if q4:
    ref = q4.group(1).strip()
    m = re.search(r'REDIRECT\s+to\s+([WE]\d+)', ref)
    if m: base['Q4_top_weakness'] = m.group(1)
base['generated_by'] = 'claude_enhanced'
base['assessment_quality'] = 'HIGH'
Path('$assess_file').write_text(json.dumps(base, indent=2))
print('written')
" 2>/dev/null && log "  ✓ Assessment saved (claude-enhanced): $assess_file" || {
      echo "$local_evidence" > "$assess_file"
      log "  Assessment saved (python only — merge failed): $assess_file"
    }
  else
    echo "$local_evidence" > "$assess_file"
    log "  Assessment saved (python evidence): $assess_file"
  fi

  # Step 4: Check assessment quality — open P0 if LOW
  quality=$(python3 -c "import json; d=json.load(open('$assess_file')); print(d.get('assessment_quality','?'))" 2>/dev/null || echo "?")
  log "  Quality: $quality | Top weakness: $(python3 -c "import json; d=json.load(open('$assess_file')); print(d.get('Q4_top_weakness','?'))" 2>/dev/null || echo '?')"

  if [[ "$quality" == "LOW" ]]; then
    issue_key="assess-low-${agent}-${TODAY}"
    grep -q "\"key\":\"${issue_key}\"" "$ISSUES_LOG" 2>/dev/null || \
      echo "{\"ts\":\"$NOW_MT\",\"key\":\"$issue_key\",\"agent\":\"$agent\",\"question\":\"ASSESS\",\"severity\":\"P1\",\"description\":\"Daily assessment LOW quality for $agent — GROWTH.md may have no active weaknesses or agent has no recent output. Self-improve cycle will have degraded research.\",\"remediated\":false,\"date\":\"$TODAY\"}" >> "$ISSUES_LOG"
  fi

  ASSESSED=$((ASSESSED+1))
done

log "=== Assessment complete: assessed=$ASSESSED skipped=$SKIPPED failed=$FAILED ==="

# Write summary for morning report
SUMMARY_FILE="$HYO_ROOT/kai/ledger/daily-assess-summary-${TODAY}.json"
python3 -c "
import json, os
from pathlib import Path
hyo_root = Path('$HYO_ROOT')
today = '$TODAY'
agents = '$AGENTS'.split()
results = []
for agent in agents:
    f = hyo_root / 'agents' / agent / 'ledger' / f'daily-assess-{today}.json'
    if f.exists():
        try:
            d = json.loads(f.read_text())
            results.append({'agent': agent, 'quality': d.get('assessment_quality','?'),
                          'top_weakness': d.get('Q4_top_weakness','?'),
                          'overdue_goals': len(d.get('overdue_goals',[])),
                          'failures_7d': d.get('Q2_failures_7d','?')[:80]})
        except: results.append({'agent': agent, 'quality': 'ERROR'})
    else:
        results.append({'agent': agent, 'quality': 'MISSING'})
summary = {'date': today, 'generated_at': '$NOW_MT', 'agents': results,
           'total_assessed': $ASSESSED, 'total_skipped': $SKIPPED, 'total_failed': $FAILED}
Path('$SUMMARY_FILE').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
" 2>/dev/null

exit 0
