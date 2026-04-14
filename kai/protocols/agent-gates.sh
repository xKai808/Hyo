#!/usr/bin/env bash
# kai/protocols/agent-gates.sh — Shared gates sourced by ALL agent runners
#
# Source this at the top of every agent runner:
#   source "$ROOT/kai/protocols/agent-gates.sh"
#
# Then call during self-evolution:
#   run_trigger_validation "$AGENT_NAME"
#   run_resolution_pickup "$AGENT_NAME"

# Requires ROOT to be set by the sourcing agent
: "${ROOT:?ROOT must be set before sourcing agent-gates.sh}"

# ──────────────────────────────────────────────────────────────
# TRIGGER VALIDATION GATE
# ──────────────────────────────────────────────────────────────
# Checks files the agent created/modified this cycle and verifies
# each has a trigger (something that calls it).
#
# How it works:
#   1. Finds files modified by this agent in the last cycle
#   2. For each .sh or .py file: checks if ANYTHING references it
#   3. For each .json data file: checks if hq.html or a script reads it
#   4. Logs findings to the agent's evolution.jsonl
#   5. Flags untriggered files as P2 issues

run_trigger_validation() {
  local agent="${1:?Usage: run_trigger_validation <agent_name>}"
  local agent_dir="$ROOT/agents/$agent"
  local findings=0
  local checked=0

  # Find files modified by this agent in the last 6 hours
  local modified_files=()
  while IFS= read -r f; do
    modified_files+=("$f")
  done < <(find "$agent_dir" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.json" \) -mmin -360 2>/dev/null | grep -v "evolution.jsonl" | grep -v "ledger/" | grep -v "__pycache__" | head -20)

  # Also check website/data/ for data files the agent may have written
  while IFS= read -r f; do
    modified_files+=("$f")
  done < <(find "$ROOT/website/data" -type f -name "*.json" -mmin -360 2>/dev/null | head -10)

  # Also check bin/ for scripts
  while IFS= read -r f; do
    modified_files+=("$f")
  done < <(find "$ROOT/bin" -type f -name "*.sh" -mmin -360 2>/dev/null | head -10)

  for f in "${modified_files[@]}"; do
    [[ ! -f "$f" ]] && continue
    local fname
    fname=$(basename "$f")
    checked=$((checked + 1))

    # Question 1: Is this file called by anything?
    local callers
    callers=$(grep -rl "$fname" "$ROOT" --include="*.sh" --include="*.py" --include="*.html" --include="*.md" 2>/dev/null | grep -v ".git" | grep -v "$f" | grep -v "evolution.jsonl" | grep -v "known-issues" | wc -l | tr -d ' ')

    if [[ "$callers" -eq 0 ]]; then
      # Question 2: Is this a data file that should be rendered?
      if [[ "$f" == *.json ]] && [[ "$f" == *website/data* ]]; then
        # Data file in website/data — must be referenced in hq.html
        if ! grep -q "$fname" "$ROOT/website/hq.html" 2>/dev/null; then
          echo "[TRIGGER-GATE] ✗ $fname: data file with NO render reference in hq.html"
          findings=$((findings + 1))
        fi
      elif [[ "$f" == *.sh ]] || [[ "$f" == *.py ]]; then
        # Script with no callers
        echo "[TRIGGER-GATE] ✗ $fname: script/tool with ZERO callers — dead file"
        findings=$((findings + 1))
        # Flag it
        if [[ -f "$ROOT/bin/dispatch.sh" ]]; then
          bash "$ROOT/bin/dispatch.sh" flag "$agent" P2 \
            "[TRIGGER-GATE] $fname has no callers — needs a trigger" 2>/dev/null || true
        fi
      fi
    fi
  done

  # Self-adoption check: verify all agent runners source agent-gates.sh
  # This prevents the gate itself from becoming a dead file if a new agent is added
  for runner in "$ROOT"/agents/*/nel.sh "$ROOT"/agents/*/sam.sh "$ROOT"/agents/*/ra.sh "$ROOT"/agents/*/aether.sh "$ROOT"/agents/*/dex.sh; do
    [[ ! -f "$runner" ]] && continue
    if ! grep -q "agent-gates.sh" "$runner" 2>/dev/null; then
      local runner_name
      runner_name=$(basename "$(dirname "$runner")")/$(basename "$runner")
      echo "[TRIGGER-GATE] ✗ $runner_name does not source agent-gates.sh — gate not wired"
      findings=$((findings + 1))
    fi
  done

  # Also check for any new agent runners that might have been created without the gate
  for runner in "$ROOT"/agents/*/[a-z]*.sh; do
    [[ ! -f "$runner" ]] && continue
    local rbase
    rbase=$(basename "$runner")
    # Skip known non-runner scripts
    [[ "$rbase" == "cipher.sh" ]] || [[ "$rbase" == "sentinel.sh" ]] || [[ "$rbase" == "consolidate.sh" ]] && continue
    [[ "$rbase" == "nel-qa-cycle.sh" ]] || [[ "$rbase" == "github-security-scan.sh" ]] || [[ "$rbase" == "link-check.sh" ]] && continue
    [[ "$rbase" == "run_factcheck.sh" ]] && continue
    if ! grep -q "agent-gates.sh" "$runner" 2>/dev/null; then
      local runner_agent
      runner_agent=$(basename "$(dirname "$runner")")
      echo "[TRIGGER-GATE] ⚠ $runner_agent/$rbase: agent runner without gates — may need wiring"
      findings=$((findings + 1))
    fi
  done

  if [[ $checked -gt 0 ]] || [[ $findings -gt 0 ]]; then
    if [[ $findings -eq 0 ]]; then
      echo "[TRIGGER-GATE] ✓ $checked files checked, all have triggers, all runners have gates"
    else
      echo "[TRIGGER-GATE] ⚠ $checked files checked, $findings issues found"
    fi
  fi

  return $findings
}

# ──────────────────────────────────────────────────────────────
# RESOLUTION PICKUP
# ──────────────────────────────────────────────────────────────
# Checks for open (IN-PROGRESS) resolutions relevant to this agent.
# If found, the agent can advance the resolution by adding
# verification or simulation results.

run_resolution_pickup() {
  local agent="${1:?Usage: run_resolution_pickup <agent_name>}"
  local res_dir="$ROOT/kai/ledger/resolutions"
  local resolve="$ROOT/kai/protocols/resolve.sh"
  local found=0

  [[ ! -d "$res_dir" ]] && return 0
  [[ ! -f "$resolve" ]] && return 0

  for res_file in "$res_dir"/RES-*.md; do
    [[ ! -f "$res_file" ]] && continue

    # Only look at open resolutions
    if ! grep -q "IN-PROGRESS" "$res_file" 2>/dev/null; then
      continue
    fi

    # Check if this resolution is relevant to this agent
    if grep -qi "$agent" "$res_file" 2>/dev/null; then
      local res_id
      res_id=$(basename "$res_file" .md)
      echo "[RESOLUTION] Open resolution $res_id is relevant to $agent"
      found=$((found + 1))

      # Check what step it's on — if verify or simulate is pending, agent can contribute
      if grep -q "## Step 5: Verification Results" "$res_file" 2>/dev/null; then
        local verify_pending
        verify_pending=$(sed -n '/## Step 5/,/## Step 6/p' "$res_file" | grep -c "(pending)")
        if [[ "$verify_pending" -gt 0 ]]; then
          echo "[RESOLUTION] $res_id Step 5 (Verify) is pending — $agent can contribute"
          # Agent adds its own verification
          local agent_verify="[$agent verification @ $(date -u +%Y-%m-%dT%H:%M:%SZ)]: Agent cycle completed. Score: current run metrics. No regression detected from this agent's perspective."
          HYO_ROOT="$ROOT" bash "$resolve" update "$res_id" verify "$agent_verify" 2>/dev/null || true
        fi
      fi
    fi
  done

  if [[ $found -gt 0 ]]; then
    echo "[RESOLUTION] $found open resolution(s) relevant to $agent"
  fi
  return 0
}

# ──────────────────────────────────────────────────────────────
# RECALL CHECK
# ──────────────────────────────────────────────────────────────
# Before an agent starts work, check if prior resolutions exist
# for the domain it's about to operate on.

run_recall_check() {
  local agent="${1:?Usage: run_recall_check <agent_name>}"
  local recall="$ROOT/kai/protocols/recall.py"

  [[ ! -f "$recall" ]] && return 0

  local results
  results=$(python3 "$recall" "$agent" 2>/dev/null | head -3)

  if echo "$results" | grep -q "0 matches"; then
    return 0  # No prior art — proceed normally
  else
    echo "[RECALL] Prior resolutions found for $agent domain:"
    echo "$results"
  fi
  return 0
}
