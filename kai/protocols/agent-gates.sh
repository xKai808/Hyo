#!/usr/bin/env bash
# kai/protocols/agent-gates.sh — Shared reasoning gates for ALL agent runners
#
# Source this in every agent runner:
#   source "$ROOT/kai/protocols/agent-gates.sh"
#
# Then call during self-evolution:
#   run_self_review "$AGENT_NAME"
#
# This file provides the QUESTIONS. The agent provides the ANSWERS.
# The goal: agents become domain experts that know more than Kai.

: "${ROOT:?ROOT must be set before sourcing agent-gates.sh}"

# ──────────────────────────────────────────────────────────────
# SELF-REVIEW: The core reasoning loop
# ──────────────────────────────────────────────────────────────
# This is the master function. It runs ALL the reasoning gates
# in order. Each gate asks questions and logs what it finds.
# Agents extend this by adding domain-specific logic in their
# own runners AFTER calling this function.

run_self_review() {
  local agent="${1:?Usage: run_self_review <agent_name>}"
  local agent_dir="$ROOT/agents/$agent"
  local review_log="$agent_dir/logs/self-review-$(TZ='America/Denver' date +%Y-%m-%d).md"
  local findings=0

  mkdir -p "$agent_dir/logs" 2>/dev/null

  echo "# $agent Self-Review — $(TZ='America/Denver' date +%Y-%m-%dT%H:%M)" > "$review_log"
  echo "" >> "$review_log"

  # ── Gate 1: What did I create or modify? Does it have a trigger? ──
  echo "## Gate 1: Trigger Validation" >> "$review_log"
  local created_files=0
  local untriggered=0

  for f in $(find "$agent_dir" "$ROOT/bin" "$ROOT/website/data" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.json" \) -mmin -360 2>/dev/null | grep -v "evolution" | grep -v "ledger/" | grep -v "__pycache__" | head -30); do
    [[ ! -f "$f" ]] && continue
    local fname
    fname=$(basename "$f")
    created_files=$((created_files + 1))

    # Question: does anything call this?
    local callers
    callers=$(grep -rl "$fname" "$ROOT" --include="*.sh" --include="*.py" --include="*.html" --include="*.md" 2>/dev/null | grep -v ".git" | grep -v "$f" | grep -v "evolution" | grep -v "known-issues" | wc -l | tr -d ' ')

    if [[ "$callers" -eq 0 ]]; then
      echo "- ✗ **$fname**: WHAT triggers this? Found 0 callers." >> "$review_log"
      echo "  - Agent: investigate. Is this dead or newly created?" >> "$review_log"
      untriggered=$((untriggered + 1))
      findings=$((findings + 1))
    fi
  done

  if [[ $created_files -eq 0 ]]; then
    echo "- No recently modified files to validate." >> "$review_log"
  elif [[ $untriggered -eq 0 ]]; then
    echo "- ✓ $created_files files checked, all have triggers." >> "$review_log"
  fi
  echo "" >> "$review_log"

  # ── Gate 2: Did my work reach the user? ──
  echo "## Gate 2: Visibility Check" >> "$review_log"
  echo "Questions for $agent to answer:" >> "$review_log"
  echo "- Did the output of my last cycle reach somewhere visible?" >> "$review_log"
  echo "- If I generated data, does it render on HQ or another surface?" >> "$review_log"
  echo "- If I fixed something, is the fix deployed?" >> "$review_log"

  # Concrete check: data files in website/data/ must be referenced in hq.html
  local hq_html="$ROOT/website/hq.html"
  if [[ -f "$hq_html" ]]; then
    for jf in "$ROOT"/website/data/*.json; do
      [[ ! -f "$jf" ]] && continue
      local jname
      jname=$(basename "$jf")
      if ! grep -q "$jname" "$hq_html" 2>/dev/null; then
        echo "- ✗ **$jname**: data exists but is NOT referenced in hq.html — invisible to user" >> "$review_log"
        findings=$((findings + 1))
      fi
    done
  fi
  echo "" >> "$review_log"

  # ── Gate 3: Open resolutions — can I advance any? ──
  echo "## Gate 3: Resolution Pickup" >> "$review_log"
  local res_dir="$ROOT/kai/ledger/resolutions"
  local resolve="$ROOT/kai/protocols/resolve.sh"
  local open_relevant=0

  if [[ -d "$res_dir" ]] && [[ -f "$resolve" ]]; then
    for res_file in "$res_dir"/RES-*.md; do
      [[ ! -f "$res_file" ]] && continue
      if grep -q "IN-PROGRESS" "$res_file" 2>/dev/null && grep -qi "$agent" "$res_file" 2>/dev/null; then
        local res_id
        res_id=$(basename "$res_file" .md)
        echo "- Open resolution **$res_id** is relevant to $agent" >> "$review_log"

        # Question: can I contribute verification?
        if grep -q "(pending)" "$res_file" 2>/dev/null; then
          echo "  - This resolution has pending steps. Can $agent contribute?" >> "$review_log"
          echo "  - Agent: read the resolution and add your findings." >> "$review_log"
        fi
        open_relevant=$((open_relevant + 1))
      fi
    done
  fi

  if [[ $open_relevant -eq 0 ]]; then
    echo "- No open resolutions relevant to $agent." >> "$review_log"
  fi
  echo "" >> "$review_log"

  # ── Gate 4: Prior art recall ──
  echo "## Gate 4: Recall" >> "$review_log"
  local recall="$ROOT/kai/protocols/recall.py"
  if [[ -f "$recall" ]]; then
    local recall_count
    recall_count=$(python3 "$recall" "$agent" 2>/dev/null | grep -oP '\d+ matches' | head -1 || echo "0 matches")
    echo "- Prior resolutions for '$agent': $recall_count" >> "$review_log"
    if [[ "$recall_count" != "0 matches" ]]; then
      echo "- Agent: review relevant resolutions before starting new work." >> "$review_log"
    fi
  fi
  echo "" >> "$review_log"

  # ── Gate 5: Self-adoption check ──
  echo "## Gate 5: Gate Adoption" >> "$review_log"
  local missing_gates=0
  for runner in "$ROOT"/agents/*/[a-z]*.sh; do
    [[ ! -f "$runner" ]] && continue
    local rbase
    rbase=$(basename "$runner")
    # Skip sub-scripts that aren't main runners
    [[ "$rbase" == "cipher.sh" || "$rbase" == "sentinel.sh" || "$rbase" == "consolidate.sh" ]] && continue
    [[ "$rbase" == "nel-qa-cycle.sh" || "$rbase" == "github-security-scan.sh" || "$rbase" == "link-check.sh" ]] && continue
    [[ "$rbase" == "run_factcheck.sh" ]] && continue

    if ! grep -q "agent-gates.sh" "$runner" 2>/dev/null; then
      local ragent
      ragent=$(basename "$(dirname "$runner")")
      echo "- ✗ **$ragent/$rbase** does not source agent-gates.sh" >> "$review_log"
      missing_gates=$((missing_gates + 1))
      findings=$((findings + 1))
    fi
  done
  if [[ $missing_gates -eq 0 ]]; then
    echo "- ✓ All agent runners source agent-gates.sh" >> "$review_log"
  fi
  echo "" >> "$review_log"

  # ── Gate 6: Domain growth questions (agent fills these in) ──
  echo "## Gate 6: Domain Growth" >> "$review_log"
  echo "Questions for $agent to answer in PLAYBOOK.md:" >> "$review_log"
  echo "- What do I know now that I didn't know last cycle?" >> "$review_log"
  echo "- What am I weakest at in my domain?" >> "$review_log"
  echo "- What would make me 2x more effective?" >> "$review_log"
  echo "- What question should I be asking that isn't on this list?" >> "$review_log"
  echo "" >> "$review_log"

  # ── Summary ──
  echo "## Summary" >> "$review_log"
  echo "- Findings: $findings" >> "$review_log"
  echo "- Gate results: trigger=$((created_files - untriggered))/$created_files, visibility=checked, resolutions=$open_relevant, adoption=$((5 - missing_gates))/5" >> "$review_log"
  echo "" >> "$review_log"

  # Output for the agent's runner to capture
  if [[ $findings -gt 0 ]]; then
    echo "[SELF-REVIEW] $agent: $findings findings — see $review_log"
  else
    echo "[SELF-REVIEW] $agent: all gates passed"
  fi

  # Flag significant findings
  if [[ $untriggered -gt 0 ]] && [[ -f "$ROOT/bin/dispatch.sh" ]]; then
    bash "$ROOT/bin/dispatch.sh" flag "$agent" P2 \
      "[SELF-REVIEW] $untriggered untriggered files found" 2>/dev/null || true
  fi

  return $findings
}
