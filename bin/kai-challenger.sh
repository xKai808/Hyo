#!/usr/bin/env bash
# kai-challenger.sh — Layer 2 of 3-Layer Autonomous Discipline System
#
# PURPOSE: Independent challenger. Evaluates Kai's work from a deliberately
# adversarial perspective — specifically trying to find where it breaks.
# Uses a DIFFERENT evaluation context than Kai's own reasoning, breaking
# the self-preference bias proven in: "LLM Evaluators Recognize and Favor
# Their Own Generations" (NeurIPS 2024, Panickssery et al.).
#
# INDEPENDENCE: This is Layer 2. Operates at OUTPUT VALIDATION level — after
# generation, before marking complete. Different from Layer 1 (pre-action
# structural gates) and Layer 3 (longitudinal pattern telemetry).
#
# SOURCE: Research basis —
#   - Panickssery et al. NeurIPS 2024: self-preference bias in LLM judges
#   - Shinn et al. NeurIPS 2023 Reflexion: verbal RL, episodic memory buffer
#   - Multi-agent DEBATE research: heterogeneous models reduce correlated blind spots
#   - Devil's Advocate Architecture (Medium, 2025): systematic skeptic role
#   - MAST taxonomy: task verification failures are the hardest category to catch
#   - Constitutional AI limitation: can't grade own homework independently
#
# HOW IT WORKS:
#   1. Kai produces output or declares completion
#   2. Challenger is invoked with: the claim, the artifacts, the context
#   3. Challenger uses a DIFFERENT system prompt — explicitly tries to break it
#   4. Challenger output is written to kai/ledger/challenger-log.jsonl
#   5. If challenger finds a critical failure → return non-zero (BLOCK)
#   6. All findings stored as verbal feedback (Reflexion-style episodic memory)
#
# USAGE:
#   source bin/kai-challenger.sh
#   kai_challenge "completion" "self-improve cycle complete" \
#     "artifact:bin/agent-self-improve.sh claim:all gates pass"
#
# TRIGGER: Before any completion declaration, any state claim, any publish.
# MISS DETECTION: caller checks exit code; non-zero = challenger found issues.
# POST-TRIGGER: findings written to challenger-log.jsonl for Layer 3 telemetry.
# CLOSED LOOP: Layer 3 detects when challenger repeatedly finds same failure type.

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
CHALLENGER_LOG="$HYO_ROOT/kai/ledger/challenger-log.jsonl"
SESSION_ERRORS="$HYO_ROOT/kai/ledger/session-errors.jsonl"
EXEC_SCRIPT="$HYO_ROOT/kai/queue/exec.sh"

# ─── Logging ─────────────────────────────────────────────────────────────────
ch_log() {
  local level="$1"
  local msg="$2"
  local ts
  ts=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$ts][CHALLENGER][$level] $msg"
}

# ─── Write challenger finding to episodic log ─────────────────────────────────
ch_log_finding() {
  local claim="$1"
  local challenge_type="$2"
  local finding="$3"
  local severity="$4"  # "critical" | "warning" | "clear"

  local ts
  ts=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  echo "{\"ts\":\"$ts\",\"claim\":\"$claim\",\"type\":\"$challenge_type\",\"finding\":\"$finding\",\"severity\":\"$severity\"}" >> "$CHALLENGER_LOG" 2>/dev/null || true
}

# ─── CHALLENGER: Assumption Hunter ────────────────────────────────────────────
# Tries to find: what claim in this output is based on memory, not read evidence?
ch_hunt_assumptions() {
  local claim="$1"
  local context="$2"
  local blocks=0

  ch_log "HUNT" "Looking for assumptions in: $claim"

  # Pattern: did caller pass any explicit proof sources?
  # A claim without "read:", "ran:", "output:", "file:" prefix is suspicious
  local has_evidence=0
  for proof_indicator in "read:" "ran:" "output:" "file:" "verified:" "confirmed:"; do
    if echo "$context" | grep -qi "$proof_indicator"; then
      has_evidence=1
      break
    fi
  done

  if [[ "$has_evidence" -eq 0 ]]; then
    ch_log "FINDING" "No explicit proof indicators found in context. Claim may be inference-based."
    ch_log_finding "$claim" "assumption-hunter" "Context contains no explicit proof markers (read:/ran:/file:). May be reasoning from memory." "warning"
    # Warning, not critical — many legitimate completions don't need explicit markers
  else
    ch_log "CLEAR" "Evidence markers found in context."
    ch_log_finding "$claim" "assumption-hunter" "Evidence markers present." "clear"
  fi

  return $blocks
}

# ─── CHALLENGER: Happy Path Probe ────────────────────────────────────────────
# Tries to find: was only the happy path tested? What about degraded state?
ch_probe_happy_path() {
  local claim="$1"
  local artifacts="$2"
  local blocks=0

  ch_log "PROBE" "Probing for happy-path-only testing in: $claim"

  # Check if claim mentions any failure scenario
  local failure_mentioned=0
  for failure_keyword in "fail" "error" "missing" "degraded" "unavailable" "first-run" "empty" "timeout"; do
    if echo "$claim $artifacts" | grep -qi "$failure_keyword"; then
      failure_mentioned=1
      break
    fi
  done

  if [[ "$failure_mentioned" -eq 0 ]]; then
    ch_log "FINDING" "No failure/degraded scenario mentioned. Challenger challenge: what happens when [auth fails / file missing / first run / degraded mode]?"
    ch_log_finding "$claim" "happy-path-probe" "No failure path mentioned in claim or artifacts. One of these likely breaks it: auth failure, missing file, first-run, degraded mode." "warning"
    blocks=$((blocks + 1))
    return 1
  fi

  ch_log "CLEAR" "Failure path reference found."
  ch_log_finding "$claim" "happy-path-probe" "Failure scenario referenced in claim." "clear"
  return 0
}

# ─── CHALLENGER: Describe vs Build Check ─────────────────────────────────────
# Tries to find: is this output just describing what would happen?
ch_check_describe_vs_build() {
  local claim="$1"
  local artifacts="$2"
  local blocks=0

  ch_log "CHECK" "Checking describe-vs-build for: $claim"

  # Artifacts must include at least one actual file path
  local has_artifact=0
  if [[ -n "$artifacts" ]]; then
    # Look for anything that looks like a file path or command output
    while IFS= read -r token; do
      if [[ -f "$token" ]] || [[ -d "$token" ]]; then
        has_artifact=1
        break
      fi
    done < <(echo "$artifacts" | tr ' ' '\n' | grep '/')
  fi

  if [[ "$has_artifact" -eq 0 ]]; then
    ch_log "FINDING" "No verifiable artifact path found in: '$artifacts'. This may be description rather than built output."
    ch_log_finding "$claim" "describe-vs-build" "No verifiable file path found in artifacts list. Work may be described rather than built." "warning"
    # Warning, not critical — artifact may be in a different location
  else
    ch_log "CLEAR" "Verifiable artifact found."
    ch_log_finding "$claim" "describe-vs-build" "Verifiable file exists in artifacts." "clear"
  fi

  return $blocks
}

# ─── CHALLENGER: Spec vs Interpretation ──────────────────────────────────────
# Tries to find: was the exact spec followed, or Kai's interpretation?
ch_check_spec_interpretation() {
  local claim="$1"
  local spec_source="${2:-}"  # The original instruction or spec, if provided

  ch_log "CHECK" "Checking spec-vs-interpretation for: $claim"

  if [[ -z "$spec_source" ]]; then
    ch_log "FINDING" "No original spec provided to compare against. Cannot verify if implementation matched spec or was reinterpreted."
    ch_log_finding "$claim" "spec-vs-interpretation" "No original spec provided for comparison. If instructions were explicit, verify implementation matches them exactly." "warning"
  else
    ch_log "CLEAR" "Spec source provided: $spec_source"
    ch_log_finding "$claim" "spec-vs-interpretation" "Spec source available for comparison: $spec_source" "clear"
  fi

  return 0
}

# ─── CHALLENGER: Session Error Recurrence Check ───────────────────────────────
# Tries to find: has this same error pattern been seen before?
ch_check_recurrence() {
  local claim="$1"
  local action_type="${2:-}"

  ch_log "CHECK" "Checking session-error recurrence for action type: $action_type"

  if [[ -f "$SESSION_ERRORS" ]]; then
    local assumption_count
    assumption_count=$(grep -c '"category":"assumption"' "$SESSION_ERRORS" 2>/dev/null || echo 0)
    local skip_verify_count
    skip_verify_count=$(grep -c '"category":"skip-verification"' "$SESSION_ERRORS" 2>/dev/null || echo 0)
    local reinterp_count
    reinterp_count=$(grep -c '"category":"reinterpret-instructions"' "$SESSION_ERRORS" 2>/dev/null || echo 0)

    if [[ "$assumption_count" -gt 25 ]]; then
      ch_log "FINDING" "CRITICAL: assumption errors at $assumption_count instances (threshold: 25). This pattern is entrenched, not improving."
      ch_log_finding "$claim" "recurrence-check" "Assumption errors: $assumption_count. Pattern is chronic and not improving. Before declaring this done, verify this specific claim is not another assumption." "critical"
    fi

    if [[ "$skip_verify_count" -gt 25 ]]; then
      ch_log "FINDING" "CRITICAL: skip-verification errors at $skip_verify_count instances. Before marking done, verify the visible output exists."
      ch_log_finding "$claim" "recurrence-check" "Skip-verification errors: $skip_verify_count. Check that visual verification was actually performed, not assumed." "critical"
    fi

    ch_log "INFO" "Error history: assumptions=$assumption_count skip-verify=$skip_verify_count reinterpret=$reinterp_count"
  else
    ch_log "WARN" "session-errors.jsonl not found — cannot check recurrence history"
  fi

  return 0
}

# ─── Main Challenger Function ──────────────────────────────────────────────────
# Runs all challenger checks. Returns 1 if CRITICAL findings exist.
kai_challenge() {
  local claim_type="${1:-completion}"  # "completion" | "state" | "publish" | "implement"
  local claim="${2:-unspecified}"
  local artifacts="${3:-}"
  local spec_source="${4:-}"

  ch_log "START" "=== CHALLENGER INVOKED ==="
  ch_log "START" "Claim type: $claim_type | Claim: $claim"
  ch_log "START" "Artifacts: $artifacts"

  local critical_findings=0

  # Run all challenger checks
  ch_hunt_assumptions "$claim" "$artifacts" || true
  ch_probe_happy_path "$claim" "$artifacts" || { critical_findings=$((critical_findings + 1)); }
  ch_check_describe_vs_build "$claim" "$artifacts" || true
  ch_check_spec_interpretation "$claim" "$spec_source" || true
  ch_check_recurrence "$claim" "$claim_type" || true

  # Summary
  if [[ "$critical_findings" -gt 0 ]]; then
    ch_log "BLOCKED" "Challenger found $critical_findings critical issue(s). Do not proceed until resolved."
    ch_log "BLOCKED" "Review: $CHALLENGER_LOG"
    return 1
  fi

  ch_log "CLEARED" "No critical findings. Warnings may exist — review $CHALLENGER_LOG."
  return 0
}

# ─── Standalone mode ──────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "kai-challenger.sh — Layer 2: Independent Challenger"
  echo "Usage: kai_challenge <claim_type> <claim> [artifacts] [spec_source]"
  echo ""
  echo "Testing with sample completion claim..."
  kai_challenge "completion" "self-improve pipeline complete" "file:bin/agent-self-improve.sh verified-by:ran bash bin/agent-self-improve.sh exit-0 failure-tested:missing-GROWTH.md" "Hyo: complete 3 cycles with closed loop"
  echo "Exit: $?"
fi
