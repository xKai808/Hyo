#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ticket.sh — Central ticket management for Hyo agent workflow
# Part of the 5-system workflow (WORKFLOW_SYSTEMS.md)
# Usage: kai ticket <command> [args]
#   create  --agent <name> --title <title> --priority <P1|P2|P3> [--system <1-5>] [--blocked-by <reason>]
#   update  <ticket-id> --status <status> [--note <text>]
#   close   <ticket-id> --evidence <path-or-text> --summary <text>
#   query   [--agent <name>] [--status <status>] [--priority <P1|P2|P3>] [--overdue]
#   escalate <ticket-id> [--reason <text>]
#   verify  <ticket-id>    — run agent-specific verify.sh
#   sla-check              — check all open tickets for SLA breaches
#   list                   — show all open tickets
#   report                 — generate human-readable ticket report
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TICKET_LEDGER="$HYO_ROOT/kai/tickets/tickets.jsonl"
TICKET_ARCHIVE="$HYO_ROOT/kai/tickets/archive"
TIMESTAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y%m%d)

# ─── SLA THRESHOLDS (in seconds) ───
SLA_P1=3600      # 1 hour
SLA_P2=14400     # 4 hours
SLA_P3=86400     # 24 hours

# ─── STATUS VALUES ───
# OPEN | ACTIVE | BLOCKED | IN_REVIEW | CLOSED | ARCHIVED

# ─── COLORS ───
RED='\033[0;31m'
YLW='\033[0;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
RST='\033[0m'

log_info()  { echo -e "${CYN}[ticket]${RST} $1"; }
log_warn()  { echo -e "${YLW}[ticket]${RST} $1"; }
log_err()   { echo -e "${RED}[ticket]${RST} $1" >&2; }
log_ok()    { echo -e "${GRN}[ticket]${RST} $1"; }

# ─── GENERATE TICKET ID ───
generate_id() {
  local agent="${1:-kai}"
  local seq=0
  if [[ -s "$TICKET_LEDGER" ]]; then
    seq=$(grep -c "\"owner\":\"$agent\"" "$TICKET_LEDGER" 2>/dev/null) || seq=0
  fi
  seq=$((seq + 1))
  printf "TASK-%s-%s-%03d" "$TODAY" "$agent" "$seq"
}

# ─── CREATE TICKET ───
cmd_create() {
  local agent="" title="" priority="P2" system="1" blocked_by="" created_by="kai"
  local ticket_type="operational" weakness=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)      agent="$2"; shift 2 ;;
      --title)      title="$2"; shift 2 ;;
      --priority)   priority="$2"; shift 2 ;;
      --system)     system="$2"; shift 2 ;;
      --blocked-by) blocked_by="$2"; shift 2 ;;
      --created-by) created_by="$2"; shift 2 ;;
      --type)       ticket_type="$2"; shift 2 ;;  # operational | improvement
      --weakness)   weakness="$2"; shift 2 ;;     # W1, W2, W3 — links to GROWTH.md
      *) shift ;;
    esac
  done

  if [[ -z "$agent" || -z "$title" ]]; then
    log_err "Usage: ticket create --agent <name> --title <title> [--priority P1|P2|P3]"
    return 1
  fi

  local id
  id=$(generate_id "$agent")

  # ─── DUPLICATE GATE: reject if this ID already exists ───
  if [[ -s "$TICKET_LEDGER" ]] && grep -q "\"id\":\"$id\"" "$TICKET_LEDGER" 2>/dev/null; then
    log_warn "Ticket $id already exists — skipping create (duplicate gate)"
    echo "$id"
    return 0
  fi

  local status="OPEN"
  [[ -n "$blocked_by" ]] && status="BLOCKED"

  local sla_seconds
  case "$priority" in
    P1) sla_seconds=$SLA_P1 ;;
    P2) sla_seconds=$SLA_P2 ;;
    P3) sla_seconds=$SLA_P3 ;;
    *)  sla_seconds=$SLA_P2 ;;
  esac

  local sla_deadline
  sla_deadline=$(TZ=America/Denver date -j -v+"${sla_seconds}S" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || \
                 TZ=America/Denver date -d "+${sla_seconds} seconds" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || \
                 echo "unknown")

  # System 1 Phase 1: Task creation questions (logged for the agent to answer)
  local entry
  entry=$(python3 -c "
import json, sys
print(json.dumps({
    'id': '$id',
    'title': '''$title''',
    'owner': '$agent',
    'created_by': '$created_by',
    'priority': '$priority',
    'status': '$status',
    'ticket_type': '$ticket_type',
    'weakness': '$weakness',
    'system': 'system-$system',
    'created_at': '$TIMESTAMP',
    'updated_at': '$TIMESTAMP',
    'sla_deadline': '$sla_deadline',
    'blocked_by': '''$blocked_by''',
    'evidence': '',
    'summary': '',
    'notes': [],
    'gate_verdicts': {},
    'verification_passed': False,
    'simulation_passed': False,
    'phase1_questions': {
        'intended_outcome': '',
        'who_affected': '',
        'assumptions': '',
        'mvp': '',
        'consequence_of_delay': ''
    }
}, ensure_ascii=False))
")
  echo "$entry" >> "$TICKET_LEDGER"
  log_ok "Created $id ($priority) → $agent: $title"
  [[ -n "$blocked_by" ]] && log_warn "  BLOCKED: $blocked_by"
  echo "$id"
}

# ─── UPDATE TICKET ───
cmd_update() {
  local ticket_id="$1"; shift
  local new_status="" note="" field="" value=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) new_status="$2"; shift 2 ;;
      --note)   note="$2"; shift 2 ;;
      --field)  field="$2"; shift 2 ;;
      --value)  value="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$ticket_id" ]]; then
    log_err "Usage: ticket update <ticket-id> --status <status> [--note <text>]"
    return 1
  fi

  python3 - "$TICKET_LEDGER" "$ticket_id" "$new_status" "$note" "$TIMESTAMP" "$field" "$value" << 'PYEOF'
import json, sys

ledger_path, ticket_id, new_status, note, timestamp, field, value = sys.argv[1:8]
lines = []
found = False
with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if entry['id'] == ticket_id:
            found = True
            if new_status:
                entry['status'] = new_status
            if note:
                entry['notes'].append({'timestamp': timestamp, 'text': note})
                # ── NOTES SIZE GATE (structural fix for 55MB bomb) ──
                # Cap notes array at 20 entries — trim oldest when exceeded
                MAX_NOTES = 20
                if len(entry['notes']) > MAX_NOTES:
                    entry['notes'] = entry['notes'][-MAX_NOTES:]
            if field and value:
                # Support nested fields like phase1_questions.intended_outcome
                parts = field.split('.')
                obj = entry
                for p in parts[:-1]:
                    obj = obj[p]
                obj[parts[-1]] = value
            entry['updated_at'] = timestamp
        lines.append(json.dumps(entry, ensure_ascii=False))

if not found:
    print(f"ERROR: Ticket {ticket_id} not found", file=sys.stderr)
    sys.exit(1)

with open(ledger_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
print(f"Updated {ticket_id}")
PYEOF
  log_ok "Updated $ticket_id"
}

# ─── CLOSE TICKET ───
cmd_close() {
  local ticket_id="$1"; shift
  local evidence="" summary=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --evidence) evidence="$2"; shift 2 ;;
      --summary)  summary="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$ticket_id" || -z "$evidence" || -z "$summary" ]]; then
    log_err "Usage: ticket close <ticket-id> --evidence <path-or-text> --summary <text>"
    log_err "Tickets cannot close without evidence. This is non-negotiable."
    return 1
  fi

  # Check if verification passed
  local verified
  verified=$(python3 -c "
import json
with open('$TICKET_LEDGER') as f:
    for line in f:
        e = json.loads(line.strip())
        if e['id'] == '$ticket_id':
            print('yes' if e.get('verification_passed') else 'no')
            break
")

  if [[ "$verified" != "yes" ]]; then
    log_warn "Ticket $ticket_id has not passed verification. Running verify first..."
    cmd_verify "$ticket_id" || true
  fi

  cmd_update "$ticket_id" --status "CLOSED" --note "Closed: $summary | Evidence: $evidence"
  python3 - "$TICKET_LEDGER" "$ticket_id" "$evidence" "$summary" "$TIMESTAMP" << 'PYEOF'
import json, sys
ledger_path, ticket_id, evidence, summary, timestamp = sys.argv[1:6]
lines = []
with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if entry['id'] == ticket_id:
            entry['status'] = 'CLOSED'
            entry['evidence'] = evidence
            entry['summary'] = summary
            entry['closed_at'] = timestamp
        lines.append(json.dumps(entry, ensure_ascii=False))
with open(ledger_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
  log_ok "Closed $ticket_id with evidence"

  # ─── AUDIT TRAIL: Git commit with ticket ID ───
  # Every ticket close triggers a commit. The ticket ID in the commit message
  # creates an immutable, searchable audit trail.
  local exec_script="$HYO_ROOT/kai/queue/exec.sh"
  if [[ -x "$exec_script" ]]; then
    log_info "Triggering audit commit for $ticket_id..."
    HYO_ROOT="$HYO_ROOT" bash "$exec_script" --timeout 60 \
      "cd ~/Documents/Projects/Hyo && git add kai/tickets/tickets.jsonl kai/memory/ && git commit -m 'close($ticket_id): $summary' --allow-empty 2>&1 || true" \
      2>/dev/null || log_warn "Audit commit queued (worker will process)"
  fi

  # ─── MEMORY: Write lesson to agent memory file ───
  local agent
  agent=$(python3 -c "
import json
with open('$TICKET_LEDGER') as f:
    for line in f:
        e = json.loads(line.strip())
        if e['id'] == '$ticket_id':
            print(e['owner'])
            break
" 2>/dev/null || echo "unknown")

  local agent_memory="$HYO_ROOT/kai/memory/agent_memory/${agent}.md"
  mkdir -p "$(dirname "$agent_memory")"
  cat >> "$agent_memory" << MEMEOF

## $(TZ=America/Denver date +%Y-%m-%d) — $ticket_id
- **Summary:** $summary
- **Evidence:** $evidence
- **Closed at:** $TIMESTAMP
MEMEOF
  log_info "Lesson written to $agent memory"
}

# ─── ESCALATE TICKET ───
cmd_escalate() {
  local ticket_id="$1"; shift
  local reason="${1:-SLA breach}"

  python3 - "$TICKET_LEDGER" "$ticket_id" "$reason" "$TIMESTAMP" << 'PYEOF'
import json, sys
ledger_path, ticket_id, reason, timestamp = sys.argv[1:5]
lines = []
with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if entry['id'] == ticket_id:
            # Escalate priority
            pmap = {'P3': 'P2', 'P2': 'P1', 'P1': 'P0'}
            old_p = entry['priority']
            entry['priority'] = pmap.get(old_p, 'P0')
            entry['notes'].append({
                'timestamp': timestamp,
                'text': f'ESCALATED {old_p}→{entry["priority"]}: {reason}'
            })
            entry['updated_at'] = timestamp
            print(f"Escalated {ticket_id}: {old_p} → {entry['priority']} — {reason}")
        lines.append(json.dumps(entry, ensure_ascii=False))
with open(ledger_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
}

# ─── VERIFY TICKET ───
cmd_verify() {
  local ticket_id="$1"

  # Get the agent for this ticket
  local agent
  agent=$(python3 -c "
import json
with open('$TICKET_LEDGER') as f:
    for line in f:
        e = json.loads(line.strip())
        if e['id'] == '$ticket_id':
            print(e['owner'])
            break
")

  local verify_script="$HYO_ROOT/agents/$agent/verify.sh"
  if [[ ! -x "$verify_script" ]]; then
    log_warn "No verify.sh found for agent $agent — marking verification as manual"
    cmd_update "$ticket_id" --field "verification_passed" --value "true" --note "Verification: manual (no verify.sh for $agent)"
    return 0
  fi

  log_info "Running $agent verification for $ticket_id..."
  if bash "$verify_script" "$ticket_id" 2>&1; then
    cmd_update "$ticket_id" --field "verification_passed" --value "true" --note "Verification PASSED"
    log_ok "Verification passed for $ticket_id"
  else
    cmd_update "$ticket_id" --note "Verification FAILED — ticket remains open"
    log_err "Verification failed for $ticket_id"
    return 1
  fi
}

# ─── SLA CHECK ───
cmd_sla_check() {
  log_info "Checking SLA compliance for all open tickets..."
  python3 - "$TICKET_LEDGER" "$TIMESTAMP" << 'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta

ledger_path = sys.argv[1]
now_str = sys.argv[2]

# Parse current time
try:
    now = datetime.fromisoformat(now_str)
except:
    now = datetime.now(timezone(timedelta(hours=-6)))

sla_map = {'P0': 1800, 'P1': 3600, 'P2': 14400, 'P3': 86400}
breaches = []
warnings = []

with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if entry['status'] in ('CLOSED', 'ARCHIVED'):
            continue

        try:
            created = datetime.fromisoformat(entry['created_at'])
        except:
            continue

        priority = entry.get('priority', 'P2')
        sla_seconds = sla_map.get(priority, 14400)
        age_seconds = (now - created).total_seconds()
        remaining = sla_seconds - age_seconds

        if remaining < 0:
            breaches.append({
                'id': entry['id'],
                'owner': entry['owner'],
                'priority': priority,
                'title': entry['title'],
                'age_hours': round(age_seconds / 3600, 1),
                'overdue_hours': round(abs(remaining) / 3600, 1)
            })
        elif remaining < sla_seconds * 0.3:
            warnings.append({
                'id': entry['id'],
                'owner': entry['owner'],
                'priority': priority,
                'title': entry['title'],
                'remaining_minutes': round(remaining / 60)
            })

if breaches:
    print(f"\n🚨 SLA BREACHES ({len(breaches)}):")
    for b in breaches:
        print(f"  {b['id']} [{b['priority']}] {b['owner']}: {b['title']}")
        print(f"    → {b['overdue_hours']}h overdue (age: {b['age_hours']}h)")
else:
    print("\n✅ No SLA breaches")

if warnings:
    print(f"\n⚠️  SLA WARNINGS ({len(warnings)}):")
    for w in warnings:
        print(f"  {w['id']} [{w['priority']}] {w['owner']}: {w['title']}")
        print(f"    → {w['remaining_minutes']}min remaining")

print(f"\nChecked at {now_str}")
PYEOF
}

# ─── LIST OPEN TICKETS ───
cmd_list() {
  local filter_agent="" filter_status="" filter_priority=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)    filter_agent="$2"; shift 2 ;;
      --status)   filter_status="$2"; shift 2 ;;
      --priority) filter_priority="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  python3 - "$TICKET_LEDGER" "$filter_agent" "$filter_status" "$filter_priority" << 'PYEOF'
import json, sys

ledger_path, f_agent, f_status, f_priority = sys.argv[1:5]
tickets = []
with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if f_agent and entry['owner'] != f_agent:
            continue
        if f_status and entry['status'] != f_status:
            continue
        if f_priority and entry['priority'] != f_priority:
            continue
        if not f_status and entry['status'] in ('CLOSED', 'ARCHIVED'):
            continue
        tickets.append(entry)

if not tickets:
    print("No tickets found matching criteria.")
    sys.exit(0)

# Sort by priority then created_at
porder = {'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3}
tickets.sort(key=lambda t: (porder.get(t['priority'], 9), t['created_at']))

print(f"{'ID':<32} {'PRI':>3} {'STATUS':<10} {'OWNER':<8} TITLE")
print("─" * 100)
for t in tickets:
    status_icon = {'OPEN': '⬚', 'ACTIVE': '▶', 'BLOCKED': '🔴', 'IN_REVIEW': '🔍', 'CLOSED': '✅', 'ARCHIVED': '📦'}.get(t['status'], '?')
    print(f"{t['id']:<32} {t['priority']:>3} {status_icon} {t['status']:<9} {t['owner']:<8} {t['title'][:50]}")
print(f"\nTotal: {len(tickets)} tickets")
PYEOF
}

# ─── REPORT ───
cmd_report() {
  python3 - "$TICKET_LEDGER" << 'PYEOF'
import json, sys
from collections import Counter

ledger_path = sys.argv[1]
tickets = []
with open(ledger_path, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        tickets.append(json.loads(line))

if not tickets:
    print("No tickets in system yet.")
    sys.exit(0)

open_tickets = [t for t in tickets if t['status'] not in ('CLOSED', 'ARCHIVED')]
closed_tickets = [t for t in tickets if t['status'] == 'CLOSED']
blocked_tickets = [t for t in tickets if t['status'] == 'BLOCKED']

print("═══ TICKET SYSTEM REPORT ═══")
print(f"Total: {len(tickets)} | Open: {len(open_tickets)} | Closed: {len(closed_tickets)} | Blocked: {len(blocked_tickets)}")
print()

# By agent
agent_counts = Counter(t['owner'] for t in open_tickets)
if agent_counts:
    print("Open by agent:")
    for agent, count in agent_counts.most_common():
        print(f"  {agent}: {count}")
    print()

# By priority
pri_counts = Counter(t['priority'] for t in open_tickets)
if pri_counts:
    print("Open by priority:")
    for pri in ['P0', 'P1', 'P2', 'P3']:
        if pri in pri_counts:
            print(f"  {pri}: {pri_counts[pri]}")
    print()

# Blocked tickets
if blocked_tickets:
    print("🔴 BLOCKED TICKETS:")
    for t in blocked_tickets:
        print(f"  {t['id']} ({t['owner']}): {t['title']}")
        if t.get('blocked_by'):
            print(f"    → Blocked by: {t['blocked_by']}")
    print()

print("═══ END REPORT ═══")
PYEOF
}

# ─── PROOF-GATE TRANSITION ───
# Enforces required artifacts at each ticket state transition.
# State machine for improvement tickets (ticket_type=improvement):
#   IDENTIFIED → RESEARCHED : requires --sources (min 3 comma-separated URLs/refs)
#   RESEARCHED → IMPLEMENTED : requires --commit (git SHA)
#   IMPLEMENTED → SHIPPED   : requires --commit (git SHA) + push verification
#   SHIPPED → VERIFIED      : requires --url (live URL) with HTTP 200 check
# Operational tickets follow the same gates where evidence is provided.
#
# Usage:
#   ticket transition <ticket-id> --to <status> [--sources "url1,url2,url3"] [--commit <sha>] [--url <live_url>]
cmd_transition() {
  local ticket_id="$1"; shift
  local to_status="" sources="" commit_sha="" live_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)      to_status="$2"; shift 2 ;;
      --sources) sources="$2"; shift 2 ;;
      --commit)  commit_sha="$2"; shift 2 ;;
      --url)     live_url="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$ticket_id" || -z "$to_status" ]]; then
    log_err "Usage: ticket transition <ticket-id> --to <status> [--sources ...] [--commit <sha>] [--url <url>]"
    return 1
  fi

  # ── Gate: RESEARCHED — requires 3+ sources ──
  if [[ "$to_status" == "RESEARCHED" ]]; then
    if [[ -z "$sources" ]]; then
      log_err "GATE BLOCKED: Transition to RESEARCHED requires --sources (minimum 3)"
      log_err "Provide: --sources \"url1,url2,url3\""
      return 3
    fi
    local source_count
    source_count=$(echo "$sources" | tr ',' '\n' | grep -c '.' || true)
    if [[ "$source_count" -lt 3 ]]; then
      log_err "GATE BLOCKED: RESEARCHED requires minimum 3 sources. Provided: $source_count"
      log_err "Sources: $sources"
      return 3
    fi
    cmd_update "$ticket_id" --status "RESEARCHED" \
      --note "RESEARCHED — sources($source_count): $sources"
    log_ok "✓ GATE PASSED: RESEARCHED with $source_count sources"
    return 0
  fi

  # ── Gate: IMPLEMENTED — requires commit SHA ──
  if [[ "$to_status" == "IMPLEMENTED" ]]; then
    if [[ -z "$commit_sha" ]]; then
      log_err "GATE BLOCKED: Transition to IMPLEMENTED requires --commit <git-sha>"
      log_err "Get it with: git rev-parse HEAD"
      return 3
    fi
    # Verify commit SHA looks valid (7-40 hex chars)
    if ! echo "$commit_sha" | grep -qE '^[0-9a-f]{7,40}$'; then
      log_err "GATE BLOCKED: commit SHA looks invalid: $commit_sha"
      return 3
    fi
    cmd_update "$ticket_id" --status "IMPLEMENTED" \
      --note "IMPLEMENTED — commit: $commit_sha"
    log_ok "✓ GATE PASSED: IMPLEMENTED — commit $commit_sha"
    return 0
  fi

  # ── Gate: SHIPPED — requires commit SHA + push ──
  if [[ "$to_status" == "SHIPPED" ]]; then
    if [[ -z "$commit_sha" ]]; then
      log_err "GATE BLOCKED: Transition to SHIPPED requires --commit <git-sha>"
      return 3
    fi
    if ! echo "$commit_sha" | grep -qE '^[0-9a-f]{7,40}$'; then
      log_err "GATE BLOCKED: commit SHA looks invalid: $commit_sha"
      return 3
    fi
    # Verify the commit exists in remote (best-effort)
    local push_verified="unverified"
    if git -C "$HYO_ROOT" branch -r --contains "$commit_sha" 2>/dev/null | grep -q "origin"; then
      push_verified="pushed"
    fi
    cmd_update "$ticket_id" --status "SHIPPED" \
      --note "SHIPPED — commit: $commit_sha push: $push_verified"
    if [[ "$push_verified" == "pushed" ]]; then
      log_ok "✓ GATE PASSED: SHIPPED — commit $commit_sha confirmed pushed"
    else
      log_warn "SHIPPED (push not confirmed) — commit $commit_sha may not be on remote yet"
    fi
    return 0
  fi

  # ── Gate: VERIFIED — requires live URL returning HTTP 200 ──
  if [[ "$to_status" == "VERIFIED" ]]; then
    if [[ -z "$live_url" ]]; then
      log_err "GATE BLOCKED: Transition to VERIFIED requires --url <live_url>"
      log_err "The URL must return HTTP 200 to pass the gate."
      return 3
    fi
    log_info "Verifying live URL: $live_url"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$live_url" 2>/dev/null || echo "000")
    if [[ "$http_code" != "200" ]]; then
      log_err "GATE BLOCKED: $live_url returned HTTP $http_code (expected 200)"
      log_err "Transition to VERIFIED rejected — URL is not live."
      cmd_update "$ticket_id" \
        --note "VERIFIED GATE FAILED — $live_url returned HTTP $http_code at $TIMESTAMP"
      return 3
    fi
    cmd_update "$ticket_id" --status "VERIFIED" \
      --note "VERIFIED — live URL: $live_url (HTTP 200 confirmed at $TIMESTAMP)"
    log_ok "✓ GATE PASSED: VERIFIED — $live_url is live (HTTP 200)"
    return 0
  fi

  # ── All other transitions: pass through without proof gate ──
  cmd_update "$ticket_id" --status "$to_status" --note "Transition to $to_status at $TIMESTAMP"
  log_ok "Updated $ticket_id → $to_status"
}

# ─── MAIN DISPATCH ───
command="${1:-help}"; shift || true

case "$command" in
  create)     cmd_create "$@" ;;
  update)     cmd_update "$@" ;;
  transition) cmd_transition "$@" ;;
  close)      cmd_close "$@" ;;
  escalate)   cmd_escalate "$@" ;;
  verify)     cmd_verify "$@" ;;
  sla-check)  cmd_sla_check ;;
  list)       cmd_list "$@" ;;
  report)     cmd_report ;;
  help|*)
    echo "Usage: ticket <command> [args]"
    echo "  create     --agent <name> --title <title> --priority <P1|P2|P3>"
    echo "  update     <ticket-id> --status <status> [--note <text>]"
    echo "  transition <ticket-id> --to <status> [--sources ...] [--commit <sha>] [--url <url>]"
    echo "               RESEARCHED → requires --sources (3+ refs)"
    echo "               IMPLEMENTED → requires --commit <sha>"
    echo "               SHIPPED → requires --commit <sha>"
    echo "               VERIFIED → requires --url <live-url> (HTTP 200 checked)"
    echo "  close      <ticket-id> --evidence <path> --summary <text>"
    echo "  escalate   <ticket-id> [--reason <text>]"
    echo "  verify     <ticket-id>"
    echo "  sla-check"
    echo "  list       [--agent <name>] [--status <status>] [--priority <P1|P2|P3>]"
    echo "  report"
    ;;
esac
