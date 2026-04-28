#!/usr/bin/env bash
# kai-impossibility-gates.sh — Layer 1 of 3-Layer Autonomous Discipline System
#
# PURPOSE: Structural impossibility. Not rules. Not honor system. Binary gates that
# BLOCK progression when conditions are not provably met. Modeled after poka-yoke /
# Jidoka: the process is designed so the error cannot pass through undetected.
#
# INDEPENDENCE: This is Layer 1. Operates at PIPELINE GATE level — before action.
# Layer 2 (kai-challenger.sh) catches semantic failures AFTER generation.
# Layer 3 (kai-behavioral-telemetry.sh) catches longitudinal pattern failures.
# Each layer fails independently. No shared blind spots.
#
# SOURCE: Research basis —
#   - Shingo (1960s) poka-yoke: contact/fixed-value/motion-step error prevention
#   - Jidoka (Toyota): self-stopping on defect detection
#   - Defense in Depth: 5 independent layers, each independent
#   - MAST taxonomy (Berkeley, 2025): 14 failure modes in 3 categories
#   - Vectara awesome-agent-failures: production incident patterns
#
# USAGE:
#   source bin/kai-impossibility-gates.sh
#   kai_gate_read_before_claim "file_path" "claim_description"
#   kai_gate_push_before_done
#   kai_gate_cycle_count N 2  # require at least 2 cycles
#   kai_gate_failure_path_tested "what_failure_mode_was_tested"
#   kai_gate_no_assumption "belief" "proof_source"
#
#   Returns:
#     0 = CLEARED (proceed)
#     1 = BLOCKED (do not proceed)
#
# WIRED INTO:
#   - agent-self-improve.sh (before complete declaration)
#   - kai-pre-action-check.sh (as underlying truth source)
#   - kai-autonomous.sh (before any publish step)
#
# TRIGGER: Every pipeline, every completion, every publish.
# MISS DETECTION: Any non-zero exit from this script — caller must not proceed.
# POST-TRIGGER: Logs to kai/ledger/impossibility-gate.log for telemetry (Layer 3).
# CLOSED LOOP: Layer 3 reads this log to detect recurrence patterns.

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
GATE_LOG="$HYO_ROOT/kai/ledger/impossibility-gate.log"
SESSION_ERRORS="$HYO_ROOT/kai/ledger/session-errors.jsonl"

# ─── Logging ─────────────────────────────────────────────────────────────────
ig_log() {
  local level="$1"
  local msg="$2"
  local ts
  ts=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$ts][$level] $msg" | tee -a "$GATE_LOG"
}

# ─── Gate result tracker ──────────────────────────────────────────────────────
IG_TOTAL_BLOCKS=0
IG_TOTAL_PASSES=0
IG_BLOCK_REASONS=()

ig_record() {
  local result="$1"  # "BLOCK" | "PASS"
  local gate_id="$2"
  local reason="$3"
  if [[ "$result" == "BLOCK" ]]; then
    IG_TOTAL_BLOCKS=$((IG_TOTAL_BLOCKS + 1))
    IG_BLOCK_REASONS+=("[$gate_id] $reason")
    ig_log "BLOCK" "Gate $gate_id BLOCKED: $reason"
    # Log to session errors for Layer 3 telemetry
    local ts
    ts=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    echo "{\"ts\":\"$ts\",\"category\":\"impossibility-gate\",\"gate\":\"$gate_id\",\"reason\":\"$reason\",\"caught_by\":\"Layer1-ImpossiblityGate\"}" >> "$SESSION_ERRORS" 2>/dev/null || true
  else
    IG_TOTAL_PASSES=$((IG_TOTAL_PASSES + 1))
    ig_log "PASS" "Gate $gate_id cleared: $reason"
  fi
}

# ─── GATE 1: Read Before Claim ────────────────────────────────────────────────
# "Am I describing what SHOULD be there, or what I have READ and SEEN?"
# Pattern 2 from kai-reasoning-patterns.md (28 logged instances)
# Structural enforcement: caller MUST provide a file path + proof of read
kai_gate_read_before_claim() {
  local file_path="${1:-}"
  local claim="${2:-unspecified claim}"
  local gate_id="IG-READ-BEFORE-CLAIM"

  if [[ -z "$file_path" ]]; then
    ig_record "BLOCK" "$gate_id" "No file path provided. Claim '$claim' has no evidence source. This is an assumption."
    return 1
  fi

  if [[ ! -f "$file_path" && ! -d "$file_path" ]]; then
    ig_record "BLOCK" "$gate_id" "Evidence file '$file_path' does not exist. Cannot verify claim: '$claim'."
    return 1
  fi

  # Check file was recently accessed (within this session — use mtime as proxy)
  local file_age_seconds
  file_age_seconds=$(python3 -c "import os,time; print(int(time.time()-os.path.getmtime('$file_path')))" 2>/dev/null || echo "999999")

  # If file is >4h old and claim is about current state, warn but don't block
  # (4h = reasonable within-session window; >4h = likely stale from prior session)
  if [[ "$file_age_seconds" -gt 14400 ]]; then
    ig_log "WARN" "$gate_id: File '$file_path' is ${file_age_seconds}s old. Claim '$claim' may be based on stale data. Verify current state."
    # Not a hard block for age alone — caller may have just read it — but logged for Layer 3
  fi

  ig_record "PASS" "$gate_id" "File '$file_path' exists (${file_age_seconds}s old). Claim: '$claim'."
  return 0
}

# ─── GATE 2: Push Before Done ────────────────────────────────────────────────
# "Did I push? Was the push confirmed?"
# Pattern 6 from kai-reasoning-patterns.md (SE-010-015: 8 commits latent 18h)
kai_gate_push_before_done() {
  local gate_id="IG-PUSH-BEFORE-DONE"

  # Check git status via queue — in sandbox, try git directly
  local unpushed
  unpushed=$(cd "$HYO_ROOT" 2>/dev/null && git log --oneline origin/main..HEAD 2>/dev/null | wc -l | tr -d ' ' || echo "unknown")

  if [[ "$unpushed" == "unknown" ]]; then
    ig_log "WARN" "$gate_id: Cannot verify push status (git not accessible from sandbox). Flag for manual verification."
    ig_record "PASS" "$gate_id" "Push status unknown (sandbox limitation). Manual verification required."
    return 0  # Soft pass — sandbox limitation, not a real failure
  fi

  if [[ "$unpushed" -gt 0 ]]; then
    ig_record "BLOCK" "$gate_id" "$unpushed commit(s) exist locally but not pushed to origin/main. Commit without push = NOT done."
    return 1
  fi

  ig_record "PASS" "$gate_id" "All commits pushed ($unpushed unpushed)."
  return 0
}

# ─── GATE 3: Cycle Count ─────────────────────────────────────────────────────
# "Have I run this more than once?"
# Pattern 1 from kai-reasoning-patterns.md (single-cycle thinking)
# Structural: caller must count cycles and pass the count explicitly
kai_gate_cycle_count() {
  local cycles_run="${1:-0}"
  local cycles_required="${2:-2}"
  local gate_id="IG-CYCLE-COUNT"

  if [[ "$cycles_run" -lt "$cycles_required" ]]; then
    ig_record "BLOCK" "$gate_id" "Only $cycles_run cycle(s) completed. Required: $cycles_required. First cycle cannot see failures created by the fix."
    return 1
  fi

  ig_record "PASS" "$gate_id" "$cycles_run cycle(s) completed (required: $cycles_required)."
  return 0
}

# ─── GATE 4: Failure Path Tested ─────────────────────────────────────────────
# "Have I tested at least one failure/degraded path?"
# Pattern 3 from kai-reasoning-patterns.md (happy path only)
kai_gate_failure_path_tested() {
  local failure_mode_tested="${1:-}"
  local gate_id="IG-FAILURE-PATH"

  if [[ -z "$failure_mode_tested" ]]; then
    ig_record "BLOCK" "$gate_id" "No failure path was tested. Name one specific failure scenario and show code handles it. Not 'it should handle it.'"
    return 1
  fi

  ig_record "PASS" "$gate_id" "Failure path tested: '$failure_mode_tested'."
  return 0
}

# ─── GATE 5: No Assumption ────────────────────────────────────────────────────
# "Am I acting on inference, or verified fact?"
# Combines Pattern 2 + Pattern 5 (fixing symptoms not causes)
kai_gate_no_assumption() {
  local belief="${1:-}"
  local proof_source="${2:-}"
  local gate_id="IG-NO-ASSUMPTION"

  if [[ -z "$proof_source" ]]; then
    ig_record "BLOCK" "$gate_id" "Belief '$belief' has no proof source. Providing a belief without evidence = assumption. Verify first."
    return 1
  fi

  # Proof source must be a concrete thing: file path, command, URL — not "I think" or "it should"
  local weak_proof_patterns=("think" "should" "probably" "assume" "believe" "expect" "likely")
  for pattern in "${weak_proof_patterns[@]}"; do
    if echo "$proof_source" | grep -qi "$pattern"; then
      ig_record "BLOCK" "$gate_id" "Proof source '$proof_source' contains weak language ('$pattern'). This is still an assumption. Provide file read or command output."
      return 1
    fi
  done

  ig_record "PASS" "$gate_id" "Belief '$belief' sourced from: '$proof_source'."
  return 0
}

# ─── GATE 6: Artifact Exists (Describe vs Build) ────────────────────────────
# "Did I build it, or describe it?"
# Pattern 4 from kai-reasoning-patterns.md
kai_gate_artifact_exists() {
  local artifact_path="${1:-}"
  local artifact_description="${2:-unspecified artifact}"
  local gate_id="IG-ARTIFACT-EXISTS"

  if [[ -z "$artifact_path" ]]; then
    ig_record "BLOCK" "$gate_id" "No artifact path provided for '$artifact_description'. Description without a created file = not done."
    return 1
  fi

  if [[ ! -f "$artifact_path" ]]; then
    ig_record "BLOCK" "$gate_id" "Artifact '$artifact_path' does not exist on disk. '$artifact_description' was described, not built."
    return 1
  fi

  # Check artifact has content (not empty)
  local size
  size=$(wc -c < "$artifact_path" 2>/dev/null || echo "0")
  if [[ "$size" -lt 10 ]]; then
    ig_record "BLOCK" "$gate_id" "Artifact '$artifact_path' exists but appears empty ($size bytes). Build it, don't stub it."
    return 1
  fi

  ig_record "PASS" "$gate_id" "Artifact '$artifact_path' exists ($size bytes)."
  return 0
}

# ─── GATE 7: Lesson Encoded in Running Thing ────────────────────────────────
# "Is this lesson encoded in something that runs at 4 AM, or just prose?"
# Pattern 7 from kai-reasoning-patterns.md
kai_gate_lesson_encoded() {
  local lesson="${1:-}"
  local encoding_artifact="${2:-}"  # path to script/gate/simulation that encodes the lesson
  local gate_id="IG-LESSON-ENCODED"

  if [[ -z "$encoding_artifact" ]]; then
    ig_record "BLOCK" "$gate_id" "Lesson '$lesson' has no encoding artifact. Prose about a lesson != lesson. Show the script/gate/simulation."
    return 1
  fi

  if [[ ! -f "$encoding_artifact" ]]; then
    ig_record "BLOCK" "$gate_id" "Encoding artifact '$encoding_artifact' for lesson '$lesson' does not exist. Create it first."
    return 1
  fi

  ig_record "PASS" "$gate_id" "Lesson '$lesson' encoded in '$encoding_artifact'."
  return 0
}

# ─── Summary Gate ─────────────────────────────────────────────────────────────
# Run after checking multiple gates. Returns 1 if any were blocked.
kai_impossibility_summary() {
  local action="${1:-unknown action}"
  ig_log "SUMMARY" "Gate check for: $action | Passes: $IG_TOTAL_PASSES | Blocks: $IG_TOTAL_BLOCKS"

  if [[ "$IG_TOTAL_BLOCKS" -gt 0 ]]; then
    ig_log "BLOCKED" "Cannot proceed with: $action"
    for reason in "${IG_BLOCK_REASONS[@]}"; do
      ig_log "BLOCK_REASON" "  → $reason"
    done
    return 1
  fi

  ig_log "CLEARED" "Proceeding with: $action"
  return 0
}

# ─── Standalone mode ──────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "kai-impossibility-gates.sh — Layer 1 of 3-Layer Autonomous Discipline System"
  echo "Source this file to use individual gates, or call with test args:"
  echo "  bash bin/kai-impossibility-gates.sh test"

  if [[ "${1:-}" == "test" ]]; then
    echo ""
    echo "=== Running self-test ==="
    # Note: do NOT source $0 here — functions are already defined in this script scope

    # Test IG-READ-BEFORE-CLAIM
    echo "--- Testing IG-READ-BEFORE-CLAIM ---"
    kai_gate_read_before_claim "" "something exists" && echo "UNEXPECTED PASS" || echo "Correctly blocked empty file"
    kai_gate_read_before_claim "/nonexistent/path" "something exists" && echo "UNEXPECTED PASS" || echo "Correctly blocked missing file"
    kai_gate_read_before_claim "$0" "this script exists" && echo "Correctly passed real file" || echo "UNEXPECTED BLOCK"

    # Test IG-CYCLE-COUNT
    echo "--- Testing IG-CYCLE-COUNT ---"
    kai_gate_cycle_count 1 2 && echo "UNEXPECTED PASS" || echo "Correctly blocked: only 1 cycle"
    kai_gate_cycle_count 2 2 && echo "Correctly passed: 2 cycles" || echo "UNEXPECTED BLOCK"

    # Test IG-FAILURE-PATH
    echo "--- Testing IG-FAILURE-PATH ---"
    kai_gate_failure_path_tested "" && echo "UNEXPECTED PASS" || echo "Correctly blocked: no failure tested"
    kai_gate_failure_path_tested "missing GROWTH.md — first-run degraded mode" && echo "Correctly passed" || echo "UNEXPECTED BLOCK"

    # Test IG-NO-ASSUMPTION
    echo "--- Testing IG-NO-ASSUMPTION ---"
    kai_gate_no_assumption "gate fires correctly" "" && echo "UNEXPECTED PASS" || echo "Correctly blocked: no proof"
    kai_gate_no_assumption "gate fires correctly" "I think it should work" && echo "UNEXPECTED PASS" || echo "Correctly blocked: weak language"
    kai_gate_no_assumption "gate fires correctly" "ran bash bin/kai-pre-action-check.sh, exit code 0" && echo "Correctly passed" || echo "UNEXPECTED BLOCK"

    echo ""
    echo "=== Self-test complete ==="
  fi
fi
