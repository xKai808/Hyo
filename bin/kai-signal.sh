#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# kai-signal.sh — Event-triggered improvement signal bus
# Version: 1.0 — 2026-04-28
#
# PURPOSE:
#   Improvement should fire when failure happens, not just on schedule.
#   This is the fix for the OK Plateau: schedule-only improvement = arrested
#   development. Event-triggered improvement = antifragility.
#
# HOW IT WORKS:
#   1. Any agent or script calls:  kai-signal.sh emit <agent> <signal_type> <payload>
#   2. Signal written to kai/signals/pending/ as JSON
#   3. kai-autonomous.sh polls this dir every cycle (check_signals)
#   4. Matching signals trigger targeted improvement research immediately
#   5. Signal consumed (moved to kai/signals/processed/)
#
# SIGNAL TYPES (maps to GROWTH.md weakness categories):
#   research_failure      — research phase produced empty output (brief_empty)
#   api_exhausted         — API quota hit / auth expired
#   publish_failure       — HQ push failed 2+ times
#   verification_failure  — post-action verify returned wrong result
#   stale_detection       — same error class logged >10 times without structural fix
#   knowledge_gap         — agent asked a question it couldn't answer from memory
#   quality_degradation   — SICQ or OMP score dropped >10 points in 24h
#   chaos_discovery       — chaos-inject.sh found a dependency with no fallback
#
# USAGE:
#   # Emit a signal (any script can do this):
#   bash bin/kai-signal.sh emit nel research_failure "W2 brief returned empty 3 cycles"
#   bash bin/kai-signal.sh emit aether quality_degradation "OMP dropped from 82 to 61"
#
#   # Poll and process pending signals (called by kai-autonomous.sh):
#   bash bin/kai-signal.sh poll
#
#   # List pending signals:
#   bash bin/kai-signal.sh list
#
#   # Manually consume/ack a specific signal:
#   bash bin/kai-signal.sh ack <signal_id>
#
# Called by: kai-autonomous.sh (every 5 min poll), any agent script, chaos-inject.sh
# Signals dir: kai/signals/pending/, kai/signals/processed/
# Log: kai/ledger/signals.log
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SIGNALS_DIR="$HYO_ROOT/kai/signals"
PENDING_DIR="$SIGNALS_DIR/pending"
PROCESSED_DIR="$SIGNALS_DIR/processed"
LOG="$HYO_ROOT/kai/ledger/signals.log"
SELF_IMPROVE_SH="$HYO_ROOT/bin/agent-self-improve.sh"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
INBOX="$HYO_ROOT/kai/ledger/hyo-inbox.jsonl"

mkdir -p "$PENDING_DIR" "$PROCESSED_DIR" "$(dirname "$LOG")"

NOW_MT() { TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z; }
log() { echo "[$(NOW_MT)] $*" | tee -a "$LOG"; }

# ─── Valid signal types and their urgency levels ─────────────────────────────
declare -A SIGNAL_URGENCY=(
  [research_failure]="P2"
  [api_exhausted]="P0"
  [publish_failure]="P1"
  [verification_failure]="P1"
  [stale_detection]="P1"
  [knowledge_gap]="P2"
  [quality_degradation]="P1"
  [chaos_discovery]="P1"
)

# ─── emit: write a signal to pending/ ────────────────────────────────────────
cmd_emit() {
  local agent="${1:-unknown}"
  local signal_type="${2:-unknown}"
  local payload="${3:-}"
  local caller="${4:-}"  # optional: script/function that emitted

  # Validate signal type
  if [[ -z "${SIGNAL_URGENCY[$signal_type]+x}" ]]; then
    log "WARN: unknown signal type '$signal_type' — allowed: ${!SIGNAL_URGENCY[*]}"
    log "  Emitting anyway with urgency=P2"
  fi

  local urgency="${SIGNAL_URGENCY[$signal_type]:-P2}"
  local ts
  ts=$(NOW_MT)
  local signal_id
  signal_id="sig-$(TZ=America/Denver date +%Y%m%d-%H%M%S)-${agent}-${signal_type}"
  local signal_file="$PENDING_DIR/${signal_id}.json"

  python3 - << PYEOF
import json
data = {
    "id": "$signal_id",
    "ts": "$ts",
    "agent": "$agent",
    "type": "$signal_type",
    "urgency": "$urgency",
    "payload": """$payload""",
    "caller": "$caller",
    "status": "pending",
    "retries": 0
}
with open("$signal_file", "w") as f:
    json.dump(data, f, indent=2)
print(f"[signal] Emitted: $signal_id")
PYEOF

  log "  EMIT [$urgency] $signal_type from $agent: ${payload:0:80}"

  # P0 signals also write to Hyo inbox immediately
  if [[ "$urgency" == "P0" ]]; then
    local ts_short
    ts_short=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
    echo "{\"ts\":\"$ts_short\",\"from\":\"kai-signal\",\"priority\":\"P0\",\"subject\":\"P0 signal: $signal_type from $agent\",\"body\":\"$payload\",\"status\":\"unread\"}" >> "$INBOX"
    log "  → P0 written to hyo-inbox"
  fi
}

# ─── poll: process all pending signals ───────────────────────────────────────
cmd_poll() {
  local pending_files
  pending_files=($(ls "$PENDING_DIR"/*.json 2>/dev/null || true))

  if [[ ${#pending_files[@]} -eq 0 ]]; then
    return 0
  fi

  log "Polling signals: ${#pending_files[@]} pending"

  local processed=0
  local skipped=0

  for signal_file in "${pending_files[@]}"; do
    [[ -f "$signal_file" ]] || continue

    local signal_id signal_type agent urgency payload retries
    signal_id=$(python3 -c "import json; d=json.load(open('$signal_file')); print(d.get('id','?'))" 2>/dev/null || echo "?")
    signal_type=$(python3 -c "import json; d=json.load(open('$signal_file')); print(d.get('type','?'))" 2>/dev/null || echo "?")
    agent=$(python3 -c "import json; d=json.load(open('$signal_file')); print(d.get('agent','?'))" 2>/dev/null || echo "?")
    urgency=$(python3 -c "import json; d=json.load(open('$signal_file')); print(d.get('urgency','P2'))" 2>/dev/null || echo "P2")
    payload=$(python3 -c "import json; d=json.load(open('$signal_file')); print(d.get('payload',''))" 2>/dev/null || echo "")
    retries=$(python3 -c "import json; d=json.load(open('$signal_file')); print(d.get('retries',0))" 2>/dev/null || echo "0")

    # Max retries: don't loop signals forever
    if [[ "$retries" -ge 3 ]]; then
      log "  SKIP [$signal_id] — max retries ($retries) reached, archiving"
      _consume_signal "$signal_file" "$signal_id" "max_retries"
      skipped=$((skipped + 1))
      continue
    fi

    log "  PROCESSING [$urgency] $signal_id → $signal_type for $agent"

    # Dispatch based on signal type
    local handled=true
    case "$signal_type" in
      research_failure)
        _handle_research_failure "$agent" "$payload" "$signal_id"
        ;;
      api_exhausted)
        _handle_api_exhausted "$agent" "$payload"
        ;;
      publish_failure)
        _handle_publish_failure "$agent" "$payload"
        ;;
      verification_failure)
        _handle_verification_failure "$agent" "$payload"
        ;;
      stale_detection)
        _handle_stale_detection "$agent" "$payload"
        ;;
      quality_degradation)
        _handle_quality_degradation "$agent" "$payload"
        ;;
      chaos_discovery)
        _handle_chaos_discovery "$agent" "$payload"
        ;;
      knowledge_gap)
        _handle_knowledge_gap "$agent" "$payload"
        ;;
      *)
        log "  WARN: no handler for signal type '$signal_type'"
        handled=false
        ;;
    esac

    if [[ "$handled" == true ]]; then
      _consume_signal "$signal_file" "$signal_id" "handled"
      processed=$((processed + 1))
    else
      # Increment retry count
      python3 - << PYEOF
import json
d = json.load(open("$signal_file"))
d["retries"] = d.get("retries", 0) + 1
with open("$signal_file", "w") as f:
    json.dump(d, f, indent=2)
PYEOF
      skipped=$((skipped + 1))
    fi
  done

  log "Poll complete: $processed handled, $skipped skipped"
}

# ─── Signal handlers ──────────────────────────────────────────────────────────

_handle_research_failure() {
  local agent="$1" payload="$2" signal_id="$3"
  log "  → research_failure for $agent: triggering targeted improvement cycle"
  # Write a "forward AAR" goal so next research cycle is anchored to this failure
  local aar_dir="$HYO_ROOT/agents/$agent/ledger"
  local aar_file="$aar_dir/forward-aar-$(TZ=America/Denver date +%Y-%m-%d).json"
  mkdir -p "$aar_dir"
  python3 - << PYEOF
import json, os
from pathlib import Path
ts = "$(NOW_MT)"
aar = {
    "ts": ts,
    "trigger": "research_failure_signal",
    "signal_id": "$signal_id",
    "agent": "$agent",
    "payload": """$payload""",
    "next_cycle_goal": {
        "direction": "Fix the structural cause of empty research output",
        "question": "Why did the research brief return empty? Is this Claude auth, prompt structure, or network?",
        "success_measure": "Research phase produces >500 char output for 3 consecutive cycles",
        "priority": "P1",
        "bypass_rotation": True  # Don't rotate weaknesses until this is fixed
    }
}
p = Path("$aar_file")
existing = []
if p.exists():
    try:
        existing = json.loads(p.read_text())
        if not isinstance(existing, list):
            existing = [existing]
    except:
        pass
existing.append(aar)
p.write_text(json.dumps(existing, indent=2))
print(f"[signal] Forward AAR written: $aar_file")
PYEOF

  # Also open a P1 ticket if this has happened before
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  local failure_count=0
  if [[ -f "$state_file" ]]; then
    failure_count=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('failure_count',0))" 2>/dev/null || echo 0)
  fi
  if [[ "$failure_count" -ge 2 ]] && [[ -f "$TICKET_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "$agent" \
      --title "Self-improve research failing: $payload" \
      --priority "P1" \
      --type "improvement" \
      --created-by "kai-signal" 2>/dev/null || true
    log "  → P1 ticket opened (failure_count=$failure_count)"
  fi
}

_handle_api_exhausted() {
  local agent="$1" payload="$2"
  log "  → api_exhausted: logging to daily-issues, no auto-fix (requires Hyo action)"
  local issues_log="$HYO_ROOT/kai/ledger/daily-issues.jsonl"
  local today_key
  today_key=$(TZ=America/Denver date +%Y-%m-%d)
  if ! grep -q "\"key\":\"api-exhausted-$today_key\"" "$issues_log" 2>/dev/null; then
    echo "{\"ts\":\"$(NOW_MT)\",\"key\":\"api-exhausted-$today_key\",\"agent\":\"$agent\",\"severity\":\"P0\",\"description\":\"$payload\",\"remediated\":false,\"date\":\"$today_key\"}" >> "$issues_log"
  fi
}

_handle_publish_failure() {
  local agent="$1" payload="$2"
  log "  → publish_failure: checking dedup gate and retry eligibility"
  # Retry logic is in kai.sh push — signal just ensures memory records the pattern
  local mem_note="Publish failure for $agent: $payload"
  echo "{\"ts\":\"$(NOW_MT)\",\"agent\":\"$agent\",\"event\":\"publish_failure\",\"detail\":\"$payload\"}" \
    >> "$HYO_ROOT/kai/ledger/publish-failures.jsonl" 2>/dev/null || true
}

_handle_verification_failure() {
  local agent="$1" payload="$2"
  log "  → verification_failure: triggering Nel QA cycle for $agent"
  if [[ -f "$TICKET_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "$agent" \
      --title "Verification failure: $payload" \
      --priority "P1" \
      --type "bug" \
      --created-by "kai-signal" 2>/dev/null || true
  fi
}

_handle_stale_detection() {
  local agent="$1" payload="$2"
  log "  → stale_detection: $agent has recurring error — forcing structural fix cycle"
  # Reset failure_count so self-improve doesn't get stuck, then trigger improvement
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  if [[ -f "$state_file" ]]; then
    python3 - << PYEOF
import json
from pathlib import Path
p = Path("$state_file")
d = json.loads(p.read_text())
d["failure_count"] = 0
d["stage"] = "research"
d["skip_reason"] = "stale_signal_reset"
p.write_text(json.dumps(d, indent=2))
print("[signal] State reset for stale detection")
PYEOF
  fi
  # Queue a self-improve run via kai exec
  local exec_sh="$HYO_ROOT/kai/queue/exec.sh"
  if [[ -f "$exec_sh" ]]; then
    local cmd="HYO_ROOT=$HYO_ROOT bash $SELF_IMPROVE_SH $agent"
    HYO_ROOT="$HYO_ROOT" bash "$exec_sh" "$cmd" 2>/dev/null || true
    log "  → Improvement cycle queued for $agent"
  fi
}

_handle_quality_degradation() {
  local agent="$1" payload="$2"
  log "  → quality_degradation: opening P1 ticket and triggering ARIC cycle"
  if [[ -f "$TICKET_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "$agent" \
      --title "Quality degradation: $payload" \
      --priority "P1" \
      --type "improvement" \
      --weakness "W1" \
      --created-by "kai-signal" 2>/dev/null || true
  fi
}

_handle_chaos_discovery() {
  local agent="$1" payload="$2"
  log "  → chaos_discovery: $agent has fragile dependency — scheduling hardening"
  local aar_file="$HYO_ROOT/kai/ledger/chaos-discoveries.jsonl"
  echo "{\"ts\":\"$(NOW_MT)\",\"agent\":\"$agent\",\"finding\":\"$payload\",\"status\":\"hardening_scheduled\"}" \
    >> "$aar_file" 2>/dev/null || true
  if [[ -f "$TICKET_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "$agent" \
      --title "Chaos discovery: $payload" \
      --priority "P1" \
      --type "improvement" \
      --created-by "chaos-inject" 2>/dev/null || true
  fi
}

_handle_knowledge_gap() {
  local agent="$1" payload="$2"
  log "  → knowledge_gap: writing to KNOWLEDGE.md TODO section"
  local knowledge_md="$HYO_ROOT/kai/memory/KNOWLEDGE.md"
  if [[ -f "$knowledge_md" ]]; then
    echo "" >> "$knowledge_md"
    echo "## [KNOWLEDGE GAP — $(TZ=America/Denver date +%Y-%m-%d)] $agent" >> "$knowledge_md"
    echo "$payload" >> "$knowledge_md"
    echo "_Source: kai-signal knowledge_gap — resolve by next session_" >> "$knowledge_md"
    log "  → Knowledge gap appended to KNOWLEDGE.md"
  fi
}

# ─── Consume (move pending → processed) ──────────────────────────────────────
_consume_signal() {
  local signal_file="$1" signal_id="$2" reason="${3:-handled}"
  local dest="$PROCESSED_DIR/${signal_id}-${reason}.json"
  python3 - << PYEOF
import json
from pathlib import Path
p = Path("$signal_file")
if not p.exists():
    exit(0)
d = json.loads(p.read_text())
d["status"] = "$reason"
d["consumed_at"] = "$(NOW_MT)"
Path("$dest").write_text(json.dumps(d, indent=2))
p.unlink()
PYEOF
}

# ─── list: show pending signals ───────────────────────────────────────────────
cmd_list() {
  local pending_files
  pending_files=($(ls "$PENDING_DIR"/*.json 2>/dev/null || true))
  if [[ ${#pending_files[@]} -eq 0 ]]; then
    echo "[signals] No pending signals"
    return 0
  fi
  echo "[signals] ${#pending_files[@]} pending:"
  for f in "${pending_files[@]}"; do
    python3 -c "
import json
d=json.load(open('$f'))
print(f\"  [{d.get('urgency','?')}] {d.get('type','?')} | {d.get('agent','?')} | {d.get('payload','')[:60]}\")
" 2>/dev/null || echo "  (unreadable)"
  done
}

# ─── ack: manually consume a signal ──────────────────────────────────────────
cmd_ack() {
  local signal_id="${1:-}"
  if [[ -z "$signal_id" ]]; then
    echo "Usage: kai-signal.sh ack <signal_id>"
    exit 1
  fi
  local signal_file="$PENDING_DIR/${signal_id}.json"
  if [[ ! -f "$signal_file" ]]; then
    echo "[signals] Signal not found: $signal_id"
    exit 1
  fi
  _consume_signal "$signal_file" "$signal_id" "manual_ack"
  echo "[signals] Acked: $signal_id"
}

# ─── stats: summary of processed signals ─────────────────────────────────────
cmd_stats() {
  local pending_count
  pending_count=$(ls "$PENDING_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
  local processed_count
  processed_count=$(ls "$PROCESSED_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
  echo "[signals] Pending: $pending_count | Processed total: $processed_count"
  if [[ "$pending_count" -gt 0 ]]; then
    cmd_list
  fi
}

# ─── Main dispatch ────────────────────────────────────────────────────────────
CMD="${1:-}"
shift || true

case "$CMD" in
  emit)   cmd_emit "$@" ;;
  poll)   cmd_poll ;;
  list)   cmd_list ;;
  ack)    cmd_ack "$@" ;;
  stats)  cmd_stats ;;
  *)
    echo "Usage: kai-signal.sh <emit|poll|list|ack|stats>"
    echo ""
    echo "  emit <agent> <signal_type> <payload> [caller]"
    echo "  poll          — process all pending signals"
    echo "  list          — show pending signals"
    echo "  ack <id>      — manually consume a signal"
    echo "  stats         — summary counts"
    echo ""
    echo "Signal types: ${!SIGNAL_URGENCY[*]}"
    exit 1
    ;;
esac
