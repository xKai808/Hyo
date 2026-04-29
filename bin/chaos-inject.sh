#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# chaos-inject.sh — Deliberate failure injection for antifragility testing
# Version: 1.0 — 2026-04-28
#
# PHILOSOPHY (Taleb / Netflix Chaos Engineering):
#   Fragile systems break when stressed. Antifragile systems discover
#   single points of failure BEFORE production does. We inject chaos
#   deliberately — in a controlled window — so we know exactly where
#   our agents are fragile and can fix it proactively.
#
#   "The best way to find out if your fallback works is to use it."
#   — Netflix Chaos Engineering team
#
# HOW IT WORKS:
#   1. Selects one dependency per agent at random (from its dependency manifest)
#   2. Simulates failure: redirects/renames/blocks the dependency for CHAOS_WINDOW_MIN
#   3. Triggers a mini run of the affected agent
#   4. Measures: did it detect the failure? Did it fall back? Did it alert?
#   5. Restores the dependency
#   6. Logs findings to kai/ledger/chaos-results.jsonl
#   7. Emits kai-signal.sh chaos_discovery if a SPOF is found (no fallback)
#
# DEPENDENCY CATEGORIES TESTED:
#   binary_dep    — a tool binary (claude, python3, jq, etc.)
#   file_dep      — a critical file (GROWTH.md, state.json, feed.json)
#   api_dep       — an API endpoint (HQ, OpenAI, Anthropic)
#   env_dep       — an environment variable (HYO_ROOT, tokens)
#
# SAFETY RULES:
#   - Never runs on Sunday (no-op Sunday)
#   - Chaos window: max 5 minutes (hardcoded, non-configurable)
#   - Never touches production secrets
#   - Never runs if a P0 ticket is open (system already in distress)
#   - Always restores, even if test crashes (trap + cleanup)
#   - Dry-run mode available: --dry-run shows what would be tested
#
# USAGE:
#   bash bin/chaos-inject.sh                    # run for all agents
#   bash bin/chaos-inject.sh nel                # run for one agent
#   bash bin/chaos-inject.sh --dry-run          # show plan, don't execute
#   bash bin/chaos-inject.sh --agent nel --dep file_dep  # test specific category
#
# Called by: kai-autonomous.sh (weekly, Saturday 05:00 MT)
# Results: kai/ledger/chaos-results.jsonl
# Log: kai/ledger/chaos-inject.log
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/chaos-inject.log"
RESULTS="$HYO_ROOT/kai/ledger/chaos-results.jsonl"
SIGNAL_SH="$HYO_ROOT/bin/kai-signal.sh"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"

CHAOS_WINDOW_MIN=5   # max failure window in minutes — hardcoded safety limit
DRY_RUN=false
TARGET_AGENT=""
TARGET_DEP_CATEGORY=""

mkdir -p "$(dirname "$LOG")"
NOW_MT() { TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z; }
TODAY() { TZ=America/Denver date +%Y-%m-%d; }
DOW=$(TZ=America/Denver date +%u)  # 1=Mon, 7=Sun

log()     { echo "[$(NOW_MT)] $*" | tee -a "$LOG"; }
log_ok()  { echo "[$(NOW_MT)] ✓ $*" | tee -a "$LOG"; }
log_err() { echo "[$(NOW_MT)] ✗ $*" | tee -a "$LOG"; }

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --agent)      TARGET_AGENT="$2"; shift 2 ;;
    --dep)        TARGET_DEP_CATEGORY="$2"; shift 2 ;;
    -*)           log "Unknown flag: $1"; exit 1 ;;
    *)            TARGET_AGENT="$1"; shift ;;
  esac
done

# ─── Safety checks ───────────────────────────────────────────────────────────
safety_check() {
  # Never run on Sunday
  if [[ "$DOW" -eq 7 && "$DRY_RUN" == false ]]; then
    log "SKIP: Sunday — no chaos injection on rest day"
    exit 0
  fi

  # Never run if P0 ticket open
  local tickets_file="$HYO_ROOT/kai/tickets/tickets.jsonl"
  if [[ -f "$tickets_file" ]]; then
    local p0_open
    p0_open=$(grep '"priority":"P0"' "$tickets_file" 2>/dev/null | grep '"status":"open"' | wc -l | tr -d ' ')
    if [[ "$p0_open" -gt 0 && "$DRY_RUN" == false ]]; then
      log "SKIP: $p0_open open P0 tickets — chaos injection blocked until P0s resolved"
      exit 0
    fi
  fi

  log "Safety checks passed (DOW=$DOW, dry_run=$DRY_RUN)"
}

# ─── Agent dependency manifest ───────────────────────────────────────────────
# Returns JSON array of dependencies for an agent.
# In the future this comes from agents/<name>/manifest.json.
# For now: hardcoded based on known structure.
get_dependencies() {
  local agent="$1"
  python3 - << PYEOF
import json, os

# Common deps for all agents
base_deps = [
    {"category": "file_dep", "name": "GROWTH.md",
     "path": f"$HYO_ROOT/agents/$agent/GROWTH.md",
     "fallback_expected": False,
     "test": "missing_file"},
    {"category": "file_dep", "name": "self-improve-state.json",
     "path": f"$HYO_ROOT/agents/$agent/self-improve-state.json",
     "fallback_expected": True,
     "test": "missing_file"},
    {"category": "binary_dep", "name": "python3",
     "path": "python3",
     "fallback_expected": True,
     "test": "binary_absent"},
]

# Agent-specific deps
agent_specific = {
    "nel": [
        {"category": "file_dep", "name": "cipher.sh",
         "path": "$HYO_ROOT/agents/nel/cipher.sh",
         "fallback_expected": False, "test": "missing_file"},
    ],
    "aether": [
        {"category": "file_dep", "name": "PROTOCOL_DAILY_ANALYSIS.md",
         "path": "$HYO_ROOT/agents/aether/PROTOCOL_DAILY_ANALYSIS.md",
         "fallback_expected": False, "test": "missing_file"},
        {"category": "env_dep", "name": "OPENAI_API_KEY",
         "path": "OPENAI_API_KEY",
         "fallback_expected": True, "test": "env_unset"},
    ],
    "sam": [
        {"category": "file_dep", "name": "feed.json",
         "path": "$HYO_ROOT/agents/sam/website/data/feed.json",
         "fallback_expected": False, "test": "missing_file"},
    ],
    "ra": [
        {"category": "file_dep", "name": "sources.json",
         "path": "$HYO_ROOT/agents/ra/pipeline/sources.json",
         "fallback_expected": True, "test": "missing_file"},
    ],
    "kai": [
        {"category": "file_dep", "name": "session-handoff.json",
         "path": "$HYO_ROOT/kai/ledger/session-handoff.json",
         "fallback_expected": True, "test": "missing_file"},
        {"category": "file_dep", "name": "verified-state.json",
         "path": "$HYO_ROOT/kai/ledger/verified-state.json",
         "fallback_expected": True, "test": "missing_file"},
    ],
}

deps = base_deps + agent_specific.get("$agent", [])
print(json.dumps(deps))
PYEOF
}

# ─── Run a chaos test on one dependency ──────────────────────────────────────
run_chaos_test() {
  local agent="$1"
  local dep_json="$2"

  local dep_name dep_category dep_path fallback_expected test_type
  dep_name=$(echo "$dep_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['name'])")
  dep_category=$(echo "$dep_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['category'])")
  dep_path=$(echo "$dep_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['path'])")
  fallback_expected=$(echo "$dep_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['fallback_expected'])")
  test_type=$(echo "$dep_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['test'])")

  log ""
  log "──────────────────────────────────────────────"
  log "CHAOS TEST: $agent / $dep_category / $dep_name"
  log "  Test type: $test_type"
  log "  Fallback expected: $fallback_expected"

  if [[ "$DRY_RUN" == true ]]; then
    log "  DRY RUN: would inject failure for $CHAOS_WINDOW_MIN min"
    _record_result "$agent" "$dep_name" "$dep_category" "dry_run" "not_tested" "false" "dry_run mode — no injection"
    return 0
  fi

  local start_ts
  start_ts=$(NOW_MT)
  local backup_path=""
  local env_backup=""
  local chaos_applied=false
  local restore_needed=false

  # ─── TRAP: always restore, even on crash ──────────────────────────────────
  local trap_cmd=""

  # ─── Apply chaos ──────────────────────────────────────────────────────────
  case "$test_type" in
    missing_file)
      if [[ -f "$dep_path" ]]; then
        backup_path="${dep_path}.chaos-backup"
        mv "$dep_path" "$backup_path"
        chaos_applied=true
        restore_needed=true
        log "  ✗ INJECTED: renamed $dep_name → .chaos-backup"
        trap "mv '$backup_path' '$dep_path' 2>/dev/null || true; log 'RESTORED (trap): $dep_name'" EXIT
      else
        log "  SKIP: $dep_name doesn't exist — can't test missing_file"
        _record_result "$agent" "$dep_name" "$dep_category" "skip" "not_applicable" "false" "file did not exist before test"
        return 0
      fi
      ;;
    env_unset)
      env_backup="${!dep_path:-}"
      unset "$dep_path" 2>/dev/null || true
      chaos_applied=true
      log "  ✗ INJECTED: unset env $dep_path"
      trap "export $dep_path='$env_backup'; log 'RESTORED (trap): $dep_path'" EXIT
      ;;
    binary_absent)
      log "  SKIP: binary_absent test skipped (too destructive without container)"
      _record_result "$agent" "$dep_name" "$dep_category" "skip" "not_testable" "false" "binary test skipped (no container)"
      return 0
      ;;
    *)
      log "  SKIP: unknown test type '$test_type'"
      return 0
      ;;
  esac

  # ─── Measure: run a lightweight check of the agent ────────────────────────
  log "  Running agent health check with dep removed (${CHAOS_WINDOW_MIN}min window)..."

  local agent_script="$HYO_ROOT/agents/$agent/${agent}.sh"
  local check_output=""
  local check_rc=0
  local detected_failure=false
  local used_fallback=false
  local alerted=false

  # Run a very lightweight "health probe" — not the full runner (too slow)
  # Use parse_weaknesses call or a minimal script probe
  check_output=$(HYO_ROOT="$HYO_ROOT" timeout $((CHAOS_WINDOW_MIN * 60)) bash -c "
    source '$HYO_ROOT/bin/agent-self-improve.sh' 2>/dev/null || true
    # Test: does get_state handle missing dep gracefully?
    get_state_result=\$(get_state '$agent' 2>&1 || echo 'error')
    parse_result=\$(parse_weaknesses '$agent' 2>&1 | head -5 || echo 'error')
    echo \"get_state: \$get_state_result\"
    echo \"parse_weaknesses: \${parse_result:0:200}\"
  " 2>&1 || echo "CHAOS_TIMEOUT_OR_CRASH")

  check_rc=$?

  log "  Agent response: ${check_output:0:200}"

  # Analyze response
  if echo "$check_output" | grep -qiE "error|ALERT|CIRCUIT|fallback|backup|default"; then
    detected_failure=true
    log "  ✓ Agent detected the failure (good)"
  else
    log "  ✗ Agent did NOT detect the failure (SPOF confirmed)"
  fi

  if echo "$check_output" | grep -qiE "fallback|default|backup|alternative"; then
    used_fallback=true
    log "  ✓ Fallback was used"
  fi

  if echo "$check_output" | grep -qiE "ALERT|ticket|inbox|P0|P1|ERROR"; then
    alerted=true
    log "  ✓ Alert was generated"
  fi

  # ─── Restore dependency ───────────────────────────────────────────────────
  trap - EXIT  # Remove trap so we handle restore explicitly

  case "$test_type" in
    missing_file)
      if [[ -n "$backup_path" && -f "$backup_path" ]]; then
        mv "$backup_path" "$dep_path"
        log_ok "RESTORED: $dep_name"
      fi
      ;;
    env_unset)
      export "$dep_path"="$env_backup"
      log_ok "RESTORED: env $dep_path"
      ;;
  esac

  # ─── Determine SPOF ───────────────────────────────────────────────────────
  local is_spof=false
  local severity="ok"
  local finding=""

  if [[ "$fallback_expected" == "True" && "$used_fallback" == false ]]; then
    is_spof=true
    severity="spof_no_fallback"
    finding="$dep_category/$dep_name has no fallback despite one being expected. Agent continued without detecting the loss."
  elif [[ "$detected_failure" == false && "$fallback_expected" == "False" ]]; then
    is_spof=true
    severity="spof_silent_failure"
    finding="$dep_category/$dep_name failure went undetected. Agent silently failed without alerting."
  elif [[ "$detected_failure" == true && "$alerted" == false ]]; then
    severity="detected_no_alert"
    finding="$dep_category/$dep_name failure detected but no alert generated. Monitoring gap."
  else
    finding="$dep_category/$dep_name failure handled correctly (detected=$detected_failure, fallback=$used_fallback, alerted=$alerted)"
  fi

  log "  Result: $severity | SPOF=$is_spof | $finding"

  # ─── Record result ────────────────────────────────────────────────────────
  _record_result "$agent" "$dep_name" "$dep_category" "$severity" "$start_ts" "$is_spof" "$finding"

  # Emit signal if SPOF found
  if [[ "$is_spof" == true && -f "$SIGNAL_SH" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$SIGNAL_SH" emit "$agent" "chaos_discovery" \
      "$finding" "chaos-inject" 2>/dev/null || true
    log "  → chaos_discovery signal emitted"
  fi
}

# ─── Record result to JSONL ───────────────────────────────────────────────────
_record_result() {
  local agent="$1" dep_name="$2" dep_category="$3" severity="$4"
  local start_ts="$5" is_spof="$6" finding="$7"

  python3 - << PYEOF
import json
from pathlib import Path
result = {
    "ts": "$(NOW_MT)",
    "date": "$(TODAY)",
    "agent": "$agent",
    "dep_name": "$dep_name",
    "dep_category": "$dep_category",
    "severity": "$severity",
    "is_spof": $( [[ "$is_spof" == "true" ]] && echo "true" || echo "false"),
    "finding": """$finding""",
    "dry_run": $( [[ "$DRY_RUN" == "true" ]] && echo "true" || echo "false")
}
results_path = Path("$RESULTS")
results_path.parent.mkdir(parents=True, exist_ok=True)
with open(results_path, "a") as f:
    f.write(json.dumps(result) + "\n")
PYEOF
}

# ─── Run chaos for one agent ──────────────────────────────────────────────────
run_agent_chaos() {
  local agent="$1"

  log ""
  log "════════════════════════════════════════"
  log "CHAOS INJECTION: $agent"

  local deps_json
  deps_json=$(get_dependencies "$agent")

  # Filter by category if specified
  if [[ -n "$TARGET_DEP_CATEGORY" ]]; then
    deps_json=$(echo "$deps_json" | python3 -c "
import json, sys
deps = json.load(sys.stdin)
filtered = [d for d in deps if d['category'] == '$TARGET_DEP_CATEGORY']
print(json.dumps(filtered))
")
  fi

  local dep_count
  dep_count=$(echo "$deps_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

  if [[ "$dep_count" -eq 0 ]]; then
    log "  No testable dependencies for $agent with filters"
    return 0
  fi

  log "  $dep_count dependencies to test"

  # Run one random test per agent (not all — avoid overwhelming the system)
  local chosen_dep
  chosen_dep=$(echo "$deps_json" | python3 -c "
import json, sys, random
deps = json.load(sys.stdin)
chosen = random.choice(deps)
print(json.dumps(chosen))
")

  run_chaos_test "$agent" "$chosen_dep"
}

# ─── Summary report ──────────────────────────────────────────────────────────
print_summary() {
  log ""
  log "════════════════════════════════════════"
  log "CHAOS INJECTION SUMMARY — $(TODAY)"

  local total_spofs total_tests
  total_spofs=$(grep '"is_spof":true' "$RESULTS" 2>/dev/null | grep "\"date\":\"$(TODAY)\"" | wc -l | tr -d ' ')
  total_tests=$(grep "\"date\":\"$(TODAY)\"" "$RESULTS" 2>/dev/null | wc -l | tr -d ' ')

  log "  Tests run: $total_tests"
  log "  SPOFs found: $total_spofs"

  if [[ "$total_spofs" -gt 0 ]]; then
    log "  ⚠ SPOF details:"
    grep '"is_spof":true' "$RESULTS" 2>/dev/null | grep "\"date\":\"$(TODAY)\"" | \
      python3 -c "
import json, sys
for line in sys.stdin:
    d = json.loads(line.strip())
    print(f\"    [{d['agent']}] {d['dep_name']}: {d['finding'][:100]}\")
" 2>/dev/null || true
  fi

  log "Full results: $RESULTS"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
log "════════════════════════════════════════"
log "CHAOS INJECTOR v1.0 — $(NOW_MT)"
log "Dry run: $DRY_RUN"

safety_check

AGENTS=("nel" "aether" "sam" "ra" "kai")
if [[ -n "$TARGET_AGENT" ]]; then
  AGENTS=("$TARGET_AGENT")
fi

for agent in "${AGENTS[@]}"; do
  run_agent_chaos "$agent"
  sleep 2  # brief pause between agents
done

print_summary

log ""
log "Chaos injection complete."
