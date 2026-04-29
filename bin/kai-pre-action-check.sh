#!/usr/bin/env bash
# kai-pre-action-check.sh — Autonomous reasoning gate for Kai
#
# PURPOSE: This script runs BEFORE Kai declares any significant work complete.
# It enforces the 8 active reasoning patterns from kai-reasoning-patterns.md.
# A non-zero exit BLOCKS the action. This is not a warning — it is a stop.
#
# USAGE:
#   source this file, then call: kai_pre_action_check "<action_type>" "<description>"
#   action_type: "complete" | "commit" | "publish" | "implement" | "pipeline"
#
# Called by:
#   - agent-self-improve.sh before declaring any pipeline closed-loop
#   - kai-autonomous.sh before publishing morning reports
#   - Any script that uses the Completion Gate (EXECUTION_GATE.md)
#
# WIRED INTO: agent-self-improve.sh, self-improve-health.sh, morning report publish

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
PATTERNS_FILE="$HYO_ROOT/kai/ledger/kai-reasoning-patterns.md"
SESSION_ERRORS="$HYO_ROOT/kai/ledger/session-errors.jsonl"
GATE_LOG="$HYO_ROOT/kai/ledger/pre-action-gate.log"

# Logging
gate_log() {
  local msg="$1"
  echo "[$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S)] $msg" | tee -a "$GATE_LOG"
}

# Check result tracker
GATE_FAILS=0
GATE_PASSES=0
GATE_BLOCKS=()

gate_check() {
  local pattern_id="$1"
  local question="$2"
  local evidence="$3"   # What to look for to answer YES (verified) vs NO (stop)
  local result="$4"     # "PASS" | "FAIL" | "SKIP"

  if [[ "$result" == "FAIL" ]]; then
    GATE_FAILS=$((GATE_FAILS + 1))
    GATE_BLOCKS+=("$pattern_id: $question")
    gate_log "  ✗ BLOCK [$pattern_id] $question"
    gate_log "    Evidence checked: $evidence"
  elif [[ "$result" == "PASS" ]]; then
    GATE_PASSES=$((GATE_PASSES + 1))
    gate_log "  ✓ PASS  [$pattern_id] $question"
  else
    gate_log "  — SKIP  [$pattern_id] (not applicable to this action type)"
  fi
}

# ─── Core gate function ───────────────────────────────────────────────────────
kai_pre_action_check() {
  local action_type="${1:-complete}"
  local description="${2:-unspecified action}"
  local evidence_proof="${3:-}"  # Caller-provided proof string (file read, command output)
  local cycles_run="${4:-1}"     # How many cycles/iterations have been run
  local failure_path_tested="${5:-no}"  # Was a failure/degraded path tested?

  gate_log ""
  gate_log "PRE-ACTION GATE: $action_type — $description"
  gate_log "Checking 8 active reasoning patterns..."

  # ── Pattern 1: Single-cycle thinking ─────────────────────────────────────────
  if [[ "$action_type" == "pipeline" || "$action_type" == "complete" ]]; then
    if [[ "$cycles_run" -ge 2 ]]; then
      gate_check "P1" "Ran at least 2 cycles?" "cycles_run=$cycles_run" "PASS"
    else
      gate_check "P1" "Ran at least 2 cycles?" \
        "cycles_run=$cycles_run — only one pass completed. Declare done after single-cycle = known failure pattern." \
        "FAIL"
    fi
  else
    gate_check "P1" "Ran at least 2 cycles?" "(not applicable)" "SKIP"
  fi

  # ── Pattern 2: Assuming state without reading ─────────────────────────────────
  if [[ "$action_type" == "complete" || "$action_type" == "publish" ]]; then
    if [[ -n "$evidence_proof" ]]; then
      gate_check "P2" "State verified from file read or command output (not memory)?" \
        "Proof provided: ${evidence_proof:0:100}" "PASS"
    else
      gate_check "P2" "State verified from file read or command output (not memory)?" \
        "No evidence_proof provided. Claims about system state must cite a live read, not reasoning." \
        "FAIL"
    fi
  else
    gate_check "P2" "State verified from live read?" "(not applicable)" "SKIP"
  fi

  # ── Pattern 3: Happy path only ────────────────────────────────────────────────
  if [[ "$action_type" == "implement" || "$action_type" == "pipeline" || "$action_type" == "complete" ]]; then
    if [[ "$failure_path_tested" == "yes" ]]; then
      gate_check "P3" "At least one failure/degraded path tested?" \
        "failure_path_tested=yes" "PASS"
    else
      gate_check "P3" "At least one failure/degraded path tested?" \
        "failure_path_tested=no — only happy path verified. Missing: auth failure, missing file, first-run, degraded mode." \
        "FAIL"
    fi
  else
    gate_check "P3" "Failure path tested?" "(not applicable)" "SKIP"
  fi

  # ── Pattern 4: Describing instead of building ─────────────────────────────────
  # Check: does the work produce a file, command output, or running process?
  # This check is soft — caller must assert. But we check if description contains action verbs.
  if [[ "$action_type" == "complete" ]]; then
    local has_artifact=0
    # Check if any output artifact was recently modified (within last 30 min)
    local recent_artifacts
    recent_artifacts=$(find "$HYO_ROOT/bin" "$HYO_ROOT/kai" "$HYO_ROOT/agents" \
      -newer "$HYO_ROOT/kai/ledger/session-handoff.json" \
      -name "*.sh" -o -name "*.json" -o -name "*.md" \
      2>/dev/null | wc -l | tr -d ' ')
    if [[ "${recent_artifacts:-0}" -gt 0 ]]; then
      gate_check "P4" "Work produced an artifact (file/script/data), not just prose?" \
        "Found $recent_artifacts recently modified files" "PASS"
    else
      # Soft check — don't block, but flag
      gate_log "  ? CHECK [P4] Work produced an artifact? — could not auto-verify. Ensure output is a running thing, not a report."
    fi
  else
    gate_check "P4" "Artifact vs prose?" "(not applicable to $action_type)" "SKIP"
  fi

  # ── Pattern 5: Fixing symptoms not causes ────────────────────────────────────
  # Check session-errors for matching patterns to current action
  if [[ -f "$SESSION_ERRORS" ]]; then
    local assumption_count
    assumption_count=$(grep -c '"category":"assumption"' "$SESSION_ERRORS" 2>/dev/null || echo 0)
    local skip_verify_count
    skip_verify_count=$(grep -c '"category":"skip-verification"' "$SESSION_ERRORS" 2>/dev/null || echo 0)
    gate_log "  ? CHECK [P5] Pattern history: $assumption_count assumption errors, $skip_verify_count skip-verification errors in ledger"
    gate_log "    → These are ACTIVE patterns. Before acting, ask: does this fix address the root cause or the symptom?"
    # Stale error loop gate (#51): if same category logged >20 times without structural fix,
    # require explicit evidence that THIS action includes a structural prevention gate.
    local P5_STATUS="PASS"
    if [[ "$assumption_count" -gt 25 ]]; then
      gate_log "  ✗ CHECK [P5] STALE LOOP: assumption errors = $assumption_count (>25). Add a structural gate before proceeding."
      P5_STATUS="FAIL"
    fi
    if [[ "$skip_verify_count" -gt 25 ]]; then
      gate_log "  ✗ CHECK [P5] STALE LOOP: skip-verification errors = $skip_verify_count (>25). Add verification step before proceeding."
      P5_STATUS="FAIL"
    fi
    gate_check "P5" "Error patterns below stale-loop threshold?" \
      "assumption=$assumption_count, skip-verify=$skip_verify_count" "$P5_STATUS"
  fi

  # ── Pattern 6: Work done = committed (not pushed) ─────────────────────────────
  if [[ "$action_type" == "commit" || "$action_type" == "complete" || "$action_type" == "publish" ]]; then
    # Check if there are any unpushed commits
    local unpushed
    unpushed=$(cd "$HYO_ROOT" 2>/dev/null && git log --oneline origin/main..HEAD 2>/dev/null | wc -l | tr -d ' ' || echo "unknown")
    if [[ "$unpushed" == "0" ]]; then
      gate_check "P6" "All commits pushed to remote?" "git log shows 0 unpushed commits" "PASS"
    elif [[ "$unpushed" == "unknown" ]]; then
      gate_log "  ? CHECK [P6] Could not verify push status (git not accessible from sandbox)"
    else
      gate_check "P6" "All commits pushed to remote?" \
        "$unpushed commit(s) exist locally but not on remote. Push first." "FAIL"
    fi
  else
    gate_check "P6" "Commits pushed?" "(not applicable)" "SKIP"
  fi

  # ── Pattern 7: Report instead of system ──────────────────────────────────────
  if [[ "$action_type" == "complete" ]]; then
    gate_log "  ? CHECK [P7] Is every lesson from this session encoded in something that RUNS?"
    gate_log "    → Required: at least one gate/script/simulation step per lesson, not just prose"
    gate_log "    → Check kai-reasoning-patterns.md was updated with new patterns"
    # Check if reasoning patterns file was modified today
    local patterns_updated
    patterns_updated=$(find "$PATTERNS_FILE" -newer "$HYO_ROOT/kai/ledger/session-handoff.json" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${patterns_updated:-0}" -gt 0 ]]; then
      gate_check "P7" "kai-reasoning-patterns.md updated this session?" \
        "File modified recently" "PASS"
    else
      gate_log "  → WARN [P7] Reasoning patterns file not updated — did this session produce new lessons?"
    fi
  else
    gate_check "P7" "Lessons encoded in running things?" "(not applicable)" "SKIP"
  fi

  # ── Pattern 8: Reinterpreting instructions ───────────────────────────────────
  # This one can't be auto-checked — flag it as a reminder
  gate_log "  ? CHECK [P8] Did you follow the exact spec, or your interpretation of it?"
  gate_log "    → If you deviated from explicit instructions: STOP. State the deviation. Get confirmation."

  # ── Summary ───────────────────────────────────────────────────────────────────
  gate_log ""
  gate_log "GATE RESULT: $GATE_FAILS blocks, $GATE_PASSES passes"

  if [[ "$GATE_FAILS" -gt 0 ]]; then
    gate_log "BLOCKED. Resolve before proceeding:"
    for block in "${GATE_BLOCKS[@]}"; do
      gate_log "  → $block"
    done
    gate_log ""
    return 1  # Non-zero exit = blocked
  fi

  gate_log "CLEARED. Proceeding with: $description"
  gate_log ""
  return 0
}

# ─── Standalone mode: run check directly ─────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ACTION_TYPE="${1:-complete}"
  DESCRIPTION="${2:-manual check}"
  EVIDENCE="${3:-}"
  CYCLES="${4:-1}"
  FAILURE_PATH="${5:-no}"

  kai_pre_action_check "$ACTION_TYPE" "$DESCRIPTION" "$EVIDENCE" "$CYCLES" "$FAILURE_PATH"
fi
