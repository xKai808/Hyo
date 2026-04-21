#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# root-cause-enforcer.sh — Forces recurring patterns to get root-cause fixes
#
# Problems it fixes:
#   - 209 recurring patterns re-detected every cycle (confirmed in audit)
#   - Issues flagged → escalated → re-flagged → infinite loop
#   - No ownership → no resolution → no learning
#
# For each issue in known-issues.jsonl with 3+ occurrences and no RESOLVED entry:
#   1. Opens/escalates an improvement ticket with strict SLA
#   2. Writes a root-cause analysis prompt to owning agent's ACTIVE.md
#   3. Flags infinite escalation loops (10+ same-title escalations → auto-close)
#
# Runs daily at 15:00 MT via kai-autonomous.sh
# Log: kai/ledger/root-cause-enforcer.log
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/root-cause-enforcer.log"
KNOWN_ISSUES="$HYO_ROOT/kai/ledger/known-issues.jsonl"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_section() { echo "" >> "$LOG"; echo "═══ $* ═══" | tee -a "$LOG"; }

log_section "ROOT-CAUSE ENFORCER — $TODAY"

[[ ! -f "$KNOWN_ISSUES" ]] && log "No known-issues.jsonl found — nothing to enforce" && exit 0

# ─── Extract recurring issues (3+ occurrences, ACTIVE status) ─────────────────
RECURRING=$(python3 - "$KNOWN_ISSUES" << 'PYEOF'
import json, sys
from collections import defaultdict

ledger = sys.argv[1]
issues = []

# Load all issues
with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
            if e.get('status', 'ACTIVE') == 'ACTIVE':
                issues.append(e)
        except:
            continue

# Group by pattern/description to detect recurrence
pattern_counts = defaultdict(list)
for e in issues:
    key = e.get('pattern', e.get('description', e.get('title', ''))[:80])
    pattern_counts[key].append(e)

# Find patterns with 3+ occurrences
recurring = []
for pattern, entries in pattern_counts.items():
    count = len(entries)
    if count >= 3:
        # Determine agent from pattern content
        pattern_lower = pattern.lower()
        if 'nel' in pattern_lower or 'sentinel' in pattern_lower or 'cipher' in pattern_lower:
            agent = 'nel'
        elif 'ra' in pattern_lower or 'newsletter' in pattern_lower:
            agent = 'ra'
        elif 'sam' in pattern_lower or 'deploy' in pattern_lower or 'vercel' in pattern_lower:
            agent = 'sam'
        elif 'aether' in pattern_lower or 'metrics' in pattern_lower or 'hq' in pattern_lower:
            agent = 'sam'  # HQ rendering owned by Sam
        elif 'dex' in pattern_lower:
            agent = 'dex'
        elif 'queue' in pattern_lower:
            agent = 'kai'
        else:
            agent = 'nel'  # Default: Nel owns system health

        priority = 'P0' if count >= 15 else ('P1' if count >= 7 else 'P2')
        recurring.append({
            'pattern': pattern,
            'count': count,
            'agent': agent,
            'priority': priority
        })

# Sort by count descending
recurring.sort(key=lambda x: -x['count'])
print(json.dumps(recurring[:50]))  # Top 50 worst patterns
PYEOF
)

PATTERN_COUNT=$(echo "$RECURRING" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
log "Found $PATTERN_COUNT recurring patterns (≥3 occurrences)"

# ─── Infinite escalation loop detection ───────────────────────────────────────
log_section "Infinite escalation loop detection"
LOOPS_BROKEN=0

python3 - "$HYO_ROOT/kai/tickets/tickets.jsonl" "$TICKET_SH" "$HYO_ROOT" "$NOW_MT" << 'PYEOF'
import json, sys, subprocess

ledger_path = sys.argv[1]
ticket_sh = sys.argv[2]
hyo_root = sys.argv[3]
timestamp = sys.argv[4]

try:
    with open(ledger_path) as f:
        tickets = [json.loads(l.strip()) for l in f if l.strip()]
except:
    tickets = []

# Find tickets with 10+ escalation notes (infinite loop)
loop_tickets = []
for t in tickets:
    if t.get('status') in ('CLOSED', 'ARCHIVED', 'RESOLVED'): continue
    escalation_notes = [n for n in t.get('notes', []) if 'ESCALATED' in n.get('text', '')]
    if len(escalation_notes) >= 10:
        loop_tickets.append(t)

if loop_tickets:
    print(f"Found {len(loop_tickets)} infinite escalation loops:")
    for t in loop_tickets:
        print(f"  {t['id']} [{t['priority']}] {t['title'][:60]} ({len([n for n in t['notes'] if 'ESCALATED' in n.get('text','')])} escalations)")
        # Auto-close the loop with analysis
        subprocess.run([
            'bash', ticket_sh, 'update', t['id'],
            '--status', 'BLOCKED',
            '--note', f'LOOP_DETECTED: {len([n for n in t["notes"] if "ESCALATED" in n.get("text","")])} escalations with no resolution. Root cause likely infrastructure/credentials. Blocked pending human decision. SLA enforcement suspended until unblocked.'
        ], capture_output=True, env={**__import__('os').environ, 'HYO_ROOT': hyo_root})
else:
    print("No infinite escalation loops detected")
PYEOF

# ─── Open improvement tickets for each recurring pattern ──────────────────────
log_section "Opening improvement tickets"
NEW_TICKETS=0
SKIPPED=0

while IFS= read -r pattern_json; do
  pattern=$(echo "$pattern_json" | python3 -c "import json,sys; e=json.load(sys.stdin); print(e['pattern'][:60])")
  count=$(echo "$pattern_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
  agent=$(echo "$pattern_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['agent'])")
  priority=$(echo "$pattern_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['priority'])")
  title="ROOT-CAUSE REQUIRED [${count}x recurring]: $pattern"

  # Check if improvement ticket already exists
  exists=$(python3 -c "
import json
try:
    with open('$HYO_ROOT/kai/tickets/tickets.jsonl') as f:
        for line in f:
            e = json.loads(line.strip())
            if 'ROOT-CAUSE REQUIRED' in e.get('title','') and '$(echo "$pattern" | head -c 30)' in e.get('title','') and e.get('status') not in ('CLOSED','ARCHIVED','RESOLVED'):
                print('yes')
                break
except:
    pass
" 2>/dev/null || echo "")

  if [[ "$exists" == "yes" ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Create the ticket
  HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
    --agent "$agent" \
    --title "$title" \
    --priority "$priority" \
    --type "improvement" \
    --created-by "root-cause-enforcer" 2>/dev/null || true

  # Write root-cause prompt to agent's ACTIVE.md
  ACTIVE_MD="$HYO_ROOT/agents/$agent/ledger/ACTIVE.md"
  if [[ -f "$ACTIVE_MD" ]]; then
    cat >> "$ACTIVE_MD" << ACTIVEEOF

### 🔁 ROOT-CAUSE REQUIRED — $NOW_MT
**Pattern (${count}x recurring):** $pattern
**Assigned to:** $agent [$priority]
**Required action this cycle:**
1. Identify WHY this pattern keeps recurring (not just what it is)
2. Implement a fix that prevents it structurally, not just suppresses it
3. Verify the fix by checking if pattern count drops next cycle
4. Update evolution.jsonl with what changed and why
ACTIVEEOF
  fi

  NEW_TICKETS=$((NEW_TICKETS + 1))
  log "Opened [$priority] $agent: $title"

  # P0 patterns → page Hyo immediately
  if [[ "$priority" == "P0" ]]; then
    python3 -c "
import json
print(json.dumps({'ts': '$NOW_MT', 'from': 'root-cause-enforcer', 'priority': 'URGENT', 'status': 'unread', 'message': 'P0 RECURRING: $pattern has appeared ${count}x with no root-cause fix. Assigned to $agent.'}))
" >> "$INBOX"
  fi

done < <(echo "$RECURRING" | python3 -c "
import json, sys
for e in json.load(sys.stdin):
    print(json.dumps(e))
")

log_section "SUMMARY"
log "Patterns found: $PATTERN_COUNT | New tickets: $NEW_TICKETS | Skipped (already open): $SKIPPED"
log "Run complete: $NOW_MT"
exit 0
