#!/usr/bin/env bash
# kai-behavioral-telemetry.sh — Layer 3 of 3-Layer Autonomous Discipline System
#
# PURPOSE: Longitudinal behavioral pattern detection. Watches for drift — the
# same failure modes repeating across sessions — and escalates automatically,
# without being prompted. Modeled after chaos engineering (Netflix) + dead
# reckoning drift correction + behavioral economics nudge theory.
#
# INDEPENDENCE: This is Layer 3. Operates at BEHAVIORAL TREND level — across
# sessions, longitudinal. Different from Layer 1 (pre-action structural gates)
# and Layer 2 (per-output challenger). If Layer 1 and 2 both miss a failure,
# Layer 3 detects it via pattern frequency over time.
#
# SOURCE: Research basis —
#   - Netflix Chaos Engineering: Chaos Monkey (2011), Simian Army — fault injection
#   - Dead reckoning: AI-IMU (Brossard et al.) — drift correction without GPS
#   - Agent drift research (Tacnode, Getmaxim): memory drift, state mismatch
#   - Taleb Antifragile: systems that improve under stress, barbell strategy
#   - ICML 2025: intrinsic metacognitive learning needed for self-improvement
#   - Session errors ledger (Hyo system): 28 assumptions, 29 skip-verify = chronic
#   - KS test / PSI: statistical drift detection from ML production monitoring
#
# HOW IT WORKS:
#   1. Reads kai/ledger/session-errors.jsonl — all historical error patterns
#   2. Reads kai/ledger/impossibility-gate.log — Layer 1 block history
#   3. Reads kai/ledger/challenger-log.jsonl — Layer 2 findings history
#   4. Computes: frequency, trend (improving/worsening), category concentrations
#   5. Generates telemetry report → kai/ledger/behavioral-telemetry.json
#   6. If any pattern exceeds CRITICAL threshold → opens P1 ticket, alerts morning report
#   7. Runs FAULT INJECTION test: deliberately triggers known failure paths to verify
#      that Layer 1 and Layer 2 catch them (self-testing the gatekeepers)
#
# FAULT INJECTION (chaos engineering analog):
#   - Monthly: test that IG-READ-BEFORE-CLAIM blocks an empty proof
#   - Monthly: test that challenger catches a happy-path-only completion
#   - If gatekeepers fail their own tests → P0 alert
#
# USAGE:
#   bash bin/kai-behavioral-telemetry.sh [--report] [--fault-inject] [--check-thresholds]
#
# TRIGGER: kai-autonomous.sh runs this at 06:00 MT daily (before morning report)
# MISS DETECTION: Non-zero exit, or P1 ticket created for pattern exceedance
# POST-TRIGGER: behavioral-telemetry.json updated, morning report reads it
# CLOSED LOOP: Morning report publishes telemetry; Kai sees pattern at session start

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
SESSION_ERRORS="$HYO_ROOT/kai/ledger/session-errors.jsonl"
GATE_LOG="$HYO_ROOT/kai/ledger/impossibility-gate.log"
CHALLENGER_LOG="$HYO_ROOT/kai/ledger/challenger-log.jsonl"
TELEMETRY_FILE="$HYO_ROOT/kai/ledger/behavioral-telemetry.json"
DAILY_ISSUES="$HYO_ROOT/kai/ledger/daily-issues.jsonl"

TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

# Thresholds — based on observed data from session-errors.jsonl
THRESHOLD_ASSUMPTION_CRITICAL=30      # >30 assumption errors = P0 (currently at 28)
THRESHOLD_SKIP_VERIFY_CRITICAL=35     # >35 skip-verify errors = P0 (currently at 29)
THRESHOLD_REINTERPRET_WARNING=15      # >15 reinterpret errors = P1 (currently at 16, already past!)
THRESHOLD_RECURRENCE_7DAY=5           # >5 same error in 7 days = intervention needed
THRESHOLD_GATE_BLOCKS_PER_DAY=3       # >3 impossibility gate blocks/day = systemic issue

bt_log() {
  local level="$1"
  local msg="$2"
  echo "[$NOW][TELEMETRY][$level] $msg"
}

# ─── Read and count session errors by category ────────────────────────────────
analyze_session_errors() {
  local -A category_counts
  local total=0

  if [[ ! -f "$SESSION_ERRORS" ]]; then
    bt_log "WARN" "session-errors.jsonl not found — no error history to analyze"
    echo "{}"
    return
  fi

  # Use python for robust counting — avoids grep -c edge cases with zero matches
  python3 - "$SESSION_ERRORS" <<'PYEOF'
import json, sys, collections

path = sys.argv[1]
counts = collections.defaultdict(int)
total = 0

try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                cat = entry.get("category", "unknown")
                counts[cat] += 1
                total += 1
            except json.JSONDecodeError:
                pass
except FileNotFoundError:
    pass

# 7-day proxy (last 100 lines)
recent_counts = collections.defaultdict(int)
try:
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
        recent = lines[-100:]
        for line in recent:
            try:
                entry = json.loads(line)
                cat = entry.get("category", "unknown")
                recent_counts[cat] += 1
            except json.JSONDecodeError:
                pass
except FileNotFoundError:
    pass

print(json.dumps({
    "total": total,
    "assumption": counts.get("assumption", 0),
    "skip_verification": counts.get("skip-verification", 0),
    "reinterpret_instructions": counts.get("reinterpret-instructions", 0),
    "wrong_path": counts.get("wrong-path", 0),
    "technical_failure": counts.get("technical-failure", 0),
    "impossibility_gate": counts.get("impossibility-gate", 0),
    "assumption_7d_proxy": recent_counts.get("assumption", 0),
    "skip_verification_7d_proxy": recent_counts.get("skip-verification", 0)
}))
PYEOF
}

# ─── Check thresholds and generate alerts ────────────────────────────────────
check_thresholds() {
  local errors_json="$1"
  local alerts=()
  local status="healthy"

  local assumption skip_verify reinterpret
  assumption=$(echo "$errors_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('assumption',0))")
  skip_verify=$(echo "$errors_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('skip_verification',0))")
  reinterpret=$(echo "$errors_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('reinterpret_instructions',0))")

  # Check assumption threshold
  if [[ "$assumption" -ge "$THRESHOLD_ASSUMPTION_CRITICAL" ]]; then
    alerts+=("P0: assumption errors at $assumption (threshold: $THRESHOLD_ASSUMPTION_CRITICAL). CHRONIC pattern. Layer 1 gate IG-READ-BEFORE-CLAIM must be enforced more aggressively.")
    status="critical"
    bt_log "P0" "Assumption errors ($assumption) exceeded critical threshold ($THRESHOLD_ASSUMPTION_CRITICAL)"
  elif [[ "$assumption" -ge $((THRESHOLD_ASSUMPTION_CRITICAL - 5)) ]]; then
    alerts+=("P1: assumption errors at $assumption — approaching P0 threshold ($THRESHOLD_ASSUMPTION_CRITICAL). Trend: worsening.")
    status="warning"
  fi

  # Check skip-verify threshold
  if [[ "$skip_verify" -ge "$THRESHOLD_SKIP_VERIFY_CRITICAL" ]]; then
    alerts+=("P0: skip-verification errors at $skip_verify (threshold: $THRESHOLD_SKIP_VERIFY_CRITICAL). CHRONIC pattern. Chrome visual verification must be enforced before every completion.")
    status="critical"
    bt_log "P0" "Skip-verification errors ($skip_verify) exceeded critical threshold ($THRESHOLD_SKIP_VERIFY_CRITICAL)"
  fi

  # Check reinterpret threshold
  if [[ "$reinterpret" -ge "$THRESHOLD_REINTERPRET_WARNING" ]]; then
    alerts+=("P1: reinterpret-instructions at $reinterpret (threshold: $THRESHOLD_REINTERPRET_WARNING). Layer 2 challenger must actively compare against original spec before completion.")
    [[ "$status" == "healthy" ]] && status="warning"
    bt_log "P1" "Reinterpret-instructions ($reinterpret) exceeded warning threshold ($THRESHOLD_REINTERPRET_WARNING)"
  fi

  # Write alerts to daily issues if any
  if [[ "${#alerts[@]}" -gt 0 ]]; then
    for alert in "${alerts[@]}"; do
      echo "{\"ts\":\"$NOW\",\"date\":\"$TODAY\",\"source\":\"behavioral-telemetry\",\"severity\":\"P1\",\"message\":\"$alert\"}" >> "$DAILY_ISSUES" 2>/dev/null || true
    done
  fi

  # Return status and alerts
  local alerts_json="[]"
  if [[ "${#alerts[@]}" -gt 0 ]]; then
    alerts_json=$(printf '"%s",' "${alerts[@]}")
    alerts_json="[${alerts_json%,}]"
  fi

  cat <<EOF
{
  "status": "$status",
  "alerts": $alerts_json
}
EOF
}

# ─── Layer Integrity Test (Fault Injection) ────────────────────────────────────
# "Are the gatekeepers actually working?"
# Runs monthly via kai-autonomous.sh fault-injection schedule.
# Tests that Layer 1 and Layer 2 themselves catch known failure patterns.
fault_injection_test() {
  bt_log "FAULT-INJECT" "=== Running fault injection test ==="
  local test_failures=0
  local test_passes=0

  # Source Layer 1
  local layer1="$HYO_ROOT/bin/kai-impossibility-gates.sh"
  if [[ ! -f "$layer1" ]]; then
    bt_log "FAULT-INJECT" "FAIL: Layer 1 (kai-impossibility-gates.sh) not found. Layer 1 is dead."
    test_failures=$((test_failures + 1))
  else
    source "$layer1" 2>/dev/null || true

    # Test 1: IG-READ-BEFORE-CLAIM should block empty proof
    if kai_gate_read_before_claim "" "test claim" 2>/dev/null; then
      bt_log "FAULT-INJECT" "FAIL: IG-READ-BEFORE-CLAIM did not block empty proof. Gate is broken."
      test_failures=$((test_failures + 1))
    else
      bt_log "FAULT-INJECT" "PASS: IG-READ-BEFORE-CLAIM correctly blocked empty proof."
      test_passes=$((test_passes + 1))
    fi

    # Test 2: IG-CYCLE-COUNT should block 1 cycle when 2 required
    if kai_gate_cycle_count 1 2 2>/dev/null; then
      bt_log "FAULT-INJECT" "FAIL: IG-CYCLE-COUNT did not block single-cycle completion. Gate is broken."
      test_failures=$((test_failures + 1))
    else
      bt_log "FAULT-INJECT" "PASS: IG-CYCLE-COUNT correctly blocked single-cycle completion."
      test_passes=$((test_passes + 1))
    fi

    # Test 3: IG-FAILURE-PATH should block when no failure tested
    if kai_gate_failure_path_tested "" 2>/dev/null; then
      bt_log "FAULT-INJECT" "FAIL: IG-FAILURE-PATH did not block empty failure test. Gate is broken."
      test_failures=$((test_failures + 1))
    else
      bt_log "FAULT-INJECT" "PASS: IG-FAILURE-PATH correctly blocked no-failure-tested."
      test_passes=$((test_passes + 1))
    fi
  fi

  # Source Layer 2
  local layer2="$HYO_ROOT/bin/kai-challenger.sh"
  if [[ ! -f "$layer2" ]]; then
    bt_log "FAULT-INJECT" "FAIL: Layer 2 (kai-challenger.sh) not found. Layer 2 is dead."
    test_failures=$((test_failures + 1))
  else
    source "$layer2" 2>/dev/null || true

    # Test 4: Challenger should catch happy-path-only completion
    if kai_challenge "completion" "pipeline complete" "" "" 2>/dev/null; then
      bt_log "FAULT-INJECT" "FAIL: Challenger did not catch happy-path-only claim. Layer 2 is broken."
      test_failures=$((test_failures + 1))
    else
      bt_log "FAULT-INJECT" "PASS: Challenger correctly flagged happy-path-only claim."
      test_passes=$((test_passes + 1))
    fi
  fi

  bt_log "FAULT-INJECT" "=== Results: $test_passes passed, $test_failures failed ==="

  if [[ "$test_failures" -gt 0 ]]; then
    echo "{\"ts\":\"$NOW\",\"date\":\"$TODAY\",\"source\":\"fault-injection\",\"severity\":\"P0\",\"message\":\"$test_failures gate(s) failed fault injection test. Gatekeepers are broken.\"}" >> "$DAILY_ISSUES" 2>/dev/null || true
    return 1
  fi

  return 0
}

# ─── Generate Telemetry Report ────────────────────────────────────────────────
generate_report() {
  bt_log "REPORT" "Generating behavioral telemetry report..."

  # Fully Python-driven to avoid bash stdout mixing issues
  python3 - "$SESSION_ERRORS" "$GATE_LOG" "$CHALLENGER_LOG" "$DAILY_ISSUES" \
    "$TELEMETRY_FILE" "$TODAY" "$NOW" \
    "$THRESHOLD_ASSUMPTION_CRITICAL" "$THRESHOLD_SKIP_VERIFY_CRITICAL" \
    "$THRESHOLD_REINTERPRET_WARNING" <<'PYEOF'
import json, sys, collections, os

(errors_path, gate_log, challenger_log, daily_issues, telemetry_file,
 today, now, thr_assumption, thr_skip, thr_reinterpret) = sys.argv[1:]
thr_assumption = int(thr_assumption)
thr_skip = int(thr_skip)
thr_reinterpret = int(thr_reinterpret)

# Count session errors
counts = collections.defaultdict(int)
try:
    with open(errors_path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                counts[json.loads(line).get("category","unknown")] += 1
            except: pass
except FileNotFoundError:
    pass

assumption = counts.get("assumption", 0)
skip_verify = counts.get("skip-verification", 0)
reinterpret = counts.get("reinterpret-instructions", 0)
total = sum(counts.values())

# Count Layer 1 blocks today
layer1_today = 0
try:
    with open(gate_log) as f:
        for line in f:
            if today in line and "[BLOCK]" in line:
                layer1_today += 1
except FileNotFoundError:
    pass

# Count Layer 2 criticals
challenger_criticals = 0
try:
    with open(challenger_log) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                if json.loads(line).get("severity") == "critical":
                    challenger_criticals += 1
            except: pass
except FileNotFoundError:
    pass

# Threshold checks
alerts = []
status = "healthy"

if assumption >= thr_assumption:
    alerts.append(f"P0: assumption errors at {assumption} (threshold: {thr_assumption}). CHRONIC. Layer 1 IG-READ-BEFORE-CLAIM must be aggressively enforced.")
    status = "critical"
elif assumption >= thr_assumption - 5:
    alerts.append(f"P1: assumption errors at {assumption} — approaching P0 threshold ({thr_assumption}). Trend: worsening.")
    status = "warning"

if skip_verify >= thr_skip:
    alerts.append(f"P0: skip-verification errors at {skip_verify} (threshold: {thr_skip}). CHRONIC. Chrome visual verification must precede every completion.")
    status = "critical"

if reinterpret >= thr_reinterpret:
    alerts.append(f"P1: reinterpret-instructions at {reinterpret} (threshold: {thr_reinterpret}). Layer 2 challenger must compare against original spec.")
    if status == "healthy": status = "warning"

# Write alerts to daily issues
if alerts:
    try:
        with open(daily_issues, "a") as f:
            for alert in alerts:
                f.write(json.dumps({"ts": now, "date": today, "source": "behavioral-telemetry",
                                    "severity": "P1", "message": alert}) + "\n")
    except: pass

report = {
    "generated": now,
    "date": today,
    "status": status,
    "error_counts": {
        "total": total,
        "assumption": assumption,
        "skip_verification": skip_verify,
        "reinterpret_instructions": reinterpret,
        "wrong_path": counts.get("wrong-path", 0),
        "technical_failure": counts.get("technical-failure", 0),
        "impossibility_gate": counts.get("impossibility-gate", 0)
    },
    "thresholds": {
        "assumption_critical": thr_assumption,
        "skip_verify_critical": thr_skip,
        "reinterpret_warning": thr_reinterpret
    },
    "layer1_blocks_today": layer1_today,
    "layer2_critical_findings_total": challenger_criticals,
    "alerts": alerts,
    "trending": {
        "assumption": "chronic" if assumption >= 25 else "elevated" if assumption >= 15 else "nominal",
        "skip_verification": "chronic" if skip_verify >= 25 else "elevated" if skip_verify >= 15 else "nominal",
        "reinterpret": "chronic" if reinterpret >= 15 else "nominal"
    },
    "recommended_action": (
        "P0: immediate intervention required" if status == "critical"
        else "P1: monitor and enforce gates" if status == "warning"
        else "nominal operation"
    )
}
with open(telemetry_file, "w") as f:
    json.dump(report, f, indent=2)

print(f"Status: {status}")
if alerts:
    for a in alerts:
        print(f"  ALERT: {a}")
PYEOF

  if [[ -f "$TELEMETRY_FILE" ]]; then
    bt_log "REPORT" "Telemetry written to $TELEMETRY_FILE"
    local telem_status
    telem_status=$(python3 -c "import json; d=json.load(open('$TELEMETRY_FILE')); print(d.get('status','?'))" 2>/dev/null || echo "unknown")
    bt_log "REPORT" "Status: $telem_status"
    if [[ "$telem_status" != "healthy" ]]; then
      bt_log "ALERT" "=== BEHAVIORAL ALERT === Review $TELEMETRY_FILE"
    fi
  else
    bt_log "ERROR" "Failed to write telemetry report"
    return 1
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  local mode="${1:---report}"

  case "$mode" in
    --report)
      generate_report
      ;;
    --fault-inject)
      fault_injection_test
      ;;
    --check-thresholds)
      local errors_json
      errors_json=$(analyze_session_errors)
      check_thresholds "$errors_json"
      ;;
    --full)
      generate_report
      fault_injection_test
      ;;
    *)
      echo "Usage: $0 [--report] [--fault-inject] [--check-thresholds] [--full]"
      exit 1
      ;;
  esac
}

main "$@"
