#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# ticket-agent-hooks.sh — Source this at the top of every agent runner
#
# Provides:
#   ticket_cycle_start <agent>
#     - Stamps a "cycle ran" note on all ACTIVE tickets for this agent
#     - Prevents enforcer from treating a running agent as stale
#
#   ticket_cycle_complete <ticket_id> <summary> [evidence]
#     - Marks ticket RESOLVED with evidence + summary
#     - Enforcer skips RESOLVED tickets
#
#   ticket_open_for_agent <agent>
#     - Returns count of OPEN/ACTIVE tickets owned by agent
#     - Useful for agents to check their own load
#
#   ticket_create_if_missing <agent> <title> <priority> [type] [weakness]
#     - Creates a ticket if same title doesn't already exist for agent
#     - Prevents daily re-creation of recurring tickets
#
# Usage in runner:
#   source "$ROOT/bin/ticket-agent-hooks.sh"
#   ticket_cycle_start "nel"
#   ...work...
#   ticket_cycle_complete "TASK-20260421-nel-001" "Fixed broken symlinks" "nel.sh line 42"
# ═══════════════════════════════════════════════════════════════════════════

# Guard against double-source
[[ -n "${_TICKET_HOOKS_LOADED:-}" ]] && return 0
_TICKET_HOOKS_LOADED=1

_TICKET_BIN="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}/bin/ticket.sh"
_TICKET_LEDGER="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}/kai/tickets/tickets.jsonl"
_TICKET_TS=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

# ─── Stamp all ACTIVE tickets for this agent with a cycle-ran note ────────────
ticket_cycle_start() {
  local agent="${1:?ticket_cycle_start requires agent name}"
  [[ ! -f "$_TICKET_LEDGER" ]] && return 0

  local active_ids
  active_ids=$(python3 - "$_TICKET_LEDGER" "$agent" << 'PYEOF'
import json, sys
ledger, agent = sys.argv[1], sys.argv[2]
with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
        except:
            continue
        if e.get('owner') == agent and e.get('status') in ('OPEN', 'ACTIVE'):
            print(e['id'])
PYEOF
)

  local count=0
  while IFS= read -r tid; do
    [[ -z "$tid" ]] && continue
    HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}" \
      bash "$_TICKET_BIN" update "$tid" \
        --status "ACTIVE" \
        --note "cycle_ran: $_TICKET_TS" 2>/dev/null && count=$((count+1))
  done <<< "$active_ids"

  [[ $count -gt 0 ]] && echo "[ticket-hooks] $agent cycle start: $count tickets marked ACTIVE"
  return 0
}

# ─── Mark a ticket as RESOLVED with evidence ─────────────────────────────────
ticket_cycle_complete() {
  local ticket_id="${1:?ticket_cycle_complete requires ticket_id}"
  local summary="${2:?ticket_cycle_complete requires summary}"
  local evidence="${3:-verified by runner}"

  HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}" \
    bash "$_TICKET_BIN" update "$ticket_id" \
      --status "RESOLVED" \
      --note "RESOLVED: $summary | evidence: $evidence" 2>/dev/null \
    && echo "[ticket-hooks] Resolved $ticket_id: $summary" \
    || echo "[ticket-hooks] WARNING: Could not resolve $ticket_id"
}

# ─── Count open/active tickets for agent ─────────────────────────────────────
ticket_open_for_agent() {
  local agent="${1:?ticket_open_for_agent requires agent name}"
  [[ ! -f "$_TICKET_LEDGER" ]] && echo 0 && return 0
  python3 - "$_TICKET_LEDGER" "$agent" << 'PYEOF'
import json, sys
ledger, agent = sys.argv[1], sys.argv[2]
count = 0
with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
        except:
            continue
        if e.get('owner') == agent and e.get('status') in ('OPEN', 'ACTIVE', 'BLOCKED'):
            count += 1
print(count)
PYEOF
}

# ─── Create ticket only if a matching title doesn't exist for agent ───────────
ticket_create_if_missing() {
  local agent="${1:?}" title="${2:?}" priority="${3:-P2}"
  local ticket_type="${4:-operational}" weakness="${5:-}"

  [[ ! -f "$_TICKET_LEDGER" ]] && {
    HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}" \
      bash "$_TICKET_BIN" create --agent "$agent" --title "$title" --priority "$priority" \
        --type "$ticket_type" --weakness "$weakness" 2>/dev/null
    return 0
  }

  # Check for existing ticket with same title and owner (not closed/archived)
  local exists
  exists=$(python3 - "$_TICKET_LEDGER" "$agent" "$title" << 'PYEOF'
import json, sys
ledger, agent, title = sys.argv[1], sys.argv[2], sys.argv[3]
with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
        except:
            continue
        if (e.get('owner') == agent
                and e.get('title') == title
                and e.get('status') not in ('CLOSED', 'ARCHIVED', 'RESOLVED')):
            print("yes")
            break
PYEOF
)

  if [[ "$exists" == "yes" ]]; then
    echo "[ticket-hooks] Ticket already exists for $agent: '$title' — skipping create"
    return 0
  fi

  HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}" \
    bash "$_TICKET_BIN" create \
      --agent "$agent" \
      --title "$title" \
      --priority "$priority" \
      --type "$ticket_type" \
      --weakness "$weakness" 2>/dev/null
}
