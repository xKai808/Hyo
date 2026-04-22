#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# cross-agent-review.sh — Weekly adversarial peer review between agents
# Version: 1.0 — 2026-04-21
#
# PURPOSE — Breaking the echo chamber:
#   Each agent reviews a peer's last 7 days of improvement work.
#   Nel reviews Sam. Sam reviews Nel. Ra reviews Aether. (Dex reviews all.)
#
#   Self-improvement without external review = agents diagnosing their own
#   blindspots. An agent cannot see its own blindspots by definition.
#   This script forces a second opinion from a peer who has no stake in
#   validating the other's self-assessment.
#
# REVIEW PAIRS:
#   nel → reviews sam's improvements + code changes
#   sam → reviews nel's improvements + system health findings
#   ra  → reviews aether's analysis quality + research citations
#   dex → reviews all agents' pattern consistency
#
# OUTPUT:
#   agents/<reviewer>/research/peer-review-<target>-<date>.md
#   HQ Research tab: published as research-drop type
#   Ticket opened if critical gaps found (P1 or P0)
#
# SCHEDULE:
#   Saturday 06:45 MT via kai-autonomous.sh
#
# USAGE:
#   bash bin/cross-agent-review.sh              # all pairs
#   bash bin/cross-agent-review.sh nel sam      # nel reviews sam only
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/cross-agent-review.log"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
PUBLISH_SH="$HYO_ROOT/bin/publish-to-feed.sh"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
WEEK_AGO=$(TZ=America/Denver date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null || echo "")

log()          { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_section()  { echo "" >> "$LOG"; echo "══ $* ══" | tee -a "$LOG"; }
log_ok()       { echo "[$NOW_MT] ✓ $*" | tee -a "$LOG"; }
log_warn()     { echo "[$NOW_MT] ⚠ $*" | tee -a "$LOG"; }
log_err()      { echo "[$NOW_MT] ✗ $*" | tee -a "$LOG"; }

# ─── Find Claude binary ────────────────────────────────────────────────────────
_find_claude_bin() {
  for candidate in \
    "$HOME/.npm-global/bin/claude" \
    "/usr/local/bin/claude" \
    "/opt/homebrew/bin/claude" \
    "$(which claude 2>/dev/null || echo "")"; do
    [[ -n "$candidate" && -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

# ─── Core: collect evidence for a given agent ─────────────────────────────────
collect_agent_evidence() {
  local agent="$1"
  local evidence=""

  # GROWTH.md weaknesses + status
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
  if [[ -f "$growth_file" ]]; then
    evidence+="=== GROWTH.md (weaknesses and status) ===\n"
    evidence+="$(head -80 "$growth_file")\n\n"
  fi

  # Last 7 days of improvement research files
  local research_dir="$HYO_ROOT/agents/$agent/research/improvements"
  if [[ -d "$research_dir" ]]; then
    evidence+="=== IMPROVEMENT RESEARCH FILES (last 7 days) ===\n"
    local count=0
    for f in $(ls -t "$research_dir"/*.md 2>/dev/null | head -7); do
      evidence+="--- $(basename "$f") ---\n"
      evidence+="$(head -40 "$f")\n\n"
      count=$((count + 1))
    done
    [[ "$count" -eq 0 ]] && evidence+="(no research files found in last 7 days)\n\n"
  fi

  # Self-improve state
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  if [[ -f "$state_file" ]]; then
    evidence+="=== SELF-IMPROVE STATE ===\n"
    evidence+="$(cat "$state_file")\n\n"
  fi

  # Recent logs (last 3 days)
  local log_dir="$HYO_ROOT/agents/$agent/logs"
  if [[ -d "$log_dir" ]]; then
    evidence+="=== RECENT LOG EXCERPTS (last 3 days, 20 lines each) ===\n"
    local log_count=0
    for f in $(ls -t "$log_dir"/${agent}-*.log 2>/dev/null | head -3); do
      evidence+="--- $(basename "$f") ---\n"
      evidence+="$(tail -20 "$f")\n\n"
      log_count=$((log_count + 1))
    done
    [[ "$log_count" -eq 0 ]] && evidence+="(no logs found)\n\n"
  fi

  # Active tickets for this agent (grep from ticket ledger)
  local ticket_dir="$HYO_ROOT/kai/ledger/tickets"
  if [[ -d "$ticket_dir" ]]; then
    local agent_tickets
    agent_tickets=$(grep -l "\"agent\":\"$agent\"" "$ticket_dir"/*.json 2>/dev/null | head -5)
    if [[ -n "$agent_tickets" ]]; then
      evidence+="=== ACTIVE TICKETS ===\n"
      for t in $agent_tickets; do
        local status title
        status=$(python3 -c "import json,sys; d=json.load(open('$t')); print(d.get('status','?'))" 2>/dev/null || echo "?")
        title=$(python3 -c "import json,sys; d=json.load(open('$t')); print(d.get('title','?'))" 2>/dev/null || echo "?")
        evidence+="  [$status] $title\n"
      done
      evidence+="\n"
    fi
  fi

  printf "%s" "$evidence"
}

# ─── Core: run one peer review ─────────────────────────────────────────────────
run_peer_review() {
  local reviewer="$1"
  local target="$2"

  log_section "Peer review: $reviewer → $target"

  # Check Claude Code is available
  local claude_bin
  if ! claude_bin=$(_find_claude_bin 2>/dev/null); then
    log_err "Claude Code binary not found — skipping $reviewer → $target review"
    return 1
  fi

  # Collect evidence about the target agent
  log "  Collecting evidence for $target..."
  local target_evidence
  target_evidence=$(collect_agent_evidence "$target")

  # Collect reviewer's own context (what they know about their domain)
  local reviewer_growth_file="$HYO_ROOT/agents/$reviewer/GROWTH.md"
  local reviewer_context=""
  if [[ -f "$reviewer_growth_file" ]]; then
    reviewer_context=$(head -30 "$reviewer_growth_file")
  fi

  # Output path
  local output_dir="$HYO_ROOT/agents/$reviewer/research"
  mkdir -p "$output_dir"
  local output_file="$output_dir/peer-review-${target}-${TODAY}.md"

  # Build review prompt
  local prompt
  prompt=$(cat << PROMPT
You are $reviewer, an agent in the hyo.world system. Your job right now is to perform a critical peer review of $target's self-improvement work from the last 7 days.

You are NOT validating $target's work — you are looking for what $target missed, misdiagnosed, or got wrong.

## $target's recent work and state:

$target_evidence

## Your task:

Perform an adversarial review. For each section below, be specific and evidence-based.

### 1. DIAGNOSIS QUALITY
- Are $target's identified weaknesses real and specific, or vague/self-serving?
- Did $target correctly identify the ROOT CAUSE, or just the symptom?
- What weaknesses has $target missed that you can see from the evidence?

### 2. RESEARCH QUALITY
- Does $target's research cite specific external sources, or is it internal-only reasoning?
- Is $target's research testable and falsifiable?
- What assumptions did $target make that aren't backed by evidence?

### 3. IMPLEMENTATION CRITIQUE
- Do $target's proposed fixes actually address the root cause?
- Are there simpler or more systemic fixes $target didn't consider?
- What risks did $target's implementation create that weren't accounted for?

### 4. ECHO CHAMBER RISK
- Is $target's improvement work self-referential (measuring its own process with its own metrics)?
- Is there external validation of whether $target's improvements actually work?
- What external perspective would change $target's assessment?

### 5. CRITICAL GAPS
Rate each as P0/P1/P2:
- [P?] Gap 1: description
- [P?] Gap 2: description
(Include at least 2 specific, actionable gaps. If you find none, explain why — but be honest, not diplomatic.)

### 6. REVIEWER VERDICT
One of: STRONG | ADEQUATE | WEAK | THEATER
- STRONG: real root cause analysis + external validation + systemic fix
- ADEQUATE: correct diagnosis but shallow fix or missing validation
- WEAK: symptom-level, no external sources, or low-effort
- THEATER: looks like improvement work but produces no real change

Signed: $reviewer, peer review of $target, $TODAY
PROMPT
)

  # Call Claude Code
  log "  Calling Claude Code for adversarial review..."
  local review_output
  if review_output=$(echo "$prompt" | timeout 120 "$claude_bin" --print --no-markdown 2>/dev/null); then
    if [[ -n "$review_output" && ${#review_output} -gt 200 ]]; then
      # Write review to file
      {
        echo "# Peer Review: $reviewer → $target"
        echo "**Date:** $TODAY"
        echo "**Reviewer:** $reviewer"
        echo "**Target:** $target"
        echo "**Type:** Adversarial weekly peer review"
        echo ""
        echo "---"
        echo ""
        echo "$review_output"
        echo ""
        echo "---"
        echo "*Generated by cross-agent-review.sh v1.0*"
      } > "$output_file"
      log_ok "Review written: $output_file"

      # Extract verdict
      local verdict
      verdict=$(echo "$review_output" | grep -oE "(STRONG|ADEQUATE|WEAK|THEATER)" | tail -1)
      verdict="${verdict:-UNKNOWN}"
      log "  Verdict: $verdict"

      # Extract P0/P1 gaps and open tickets
      local gaps
      gaps=$(echo "$review_output" | grep -E "^\- \[P[01]\]" | head -5)
      if [[ -n "$gaps" ]]; then
        log "  Critical gaps found — opening tickets"
        while IFS= read -r gap_line; do
          local severity gap_text
          severity=$(echo "$gap_line" | grep -oE "P[012]")
          gap_text=$(echo "$gap_line" | sed 's/^\- \[P[012]\] //')
          if [[ -f "$TICKET_SH" && -n "$gap_text" ]]; then
            bash "$TICKET_SH" create \
              --agent "$target" \
              --type peer-review-gap \
              --severity "${severity:-P1}" \
              --title "Peer review gap ($reviewer→$target): $gap_text" \
              --description "Found during weekly cross-agent adversarial review. Reviewer: $reviewer. Review file: $output_file" \
              >> "$LOG" 2>&1 || true
          fi
        done <<< "$gaps"
      fi

      # Publish to HQ Research tab if verdict is not STRONG
      if [[ "$verdict" != "STRONG" && -f "$PUBLISH_SH" ]]; then
        log "  Publishing review to HQ Research (verdict: $verdict)..."
        local finding
        finding="$reviewer reviewed $target's last 7 days of improvement work. Verdict: $verdict."
        if [[ -n "$gaps" ]]; then
          finding="$finding Critical gaps: $(echo "$gaps" | head -2 | tr '\n' ' ')"
        fi

        bash "$PUBLISH_SH" \
          --agent "$reviewer" \
          --type "research-drop" \
          --topic "Peer Review: $reviewer assesses $target (weekly)" \
          --date "$TODAY" \
          --finding "$finding" \
          --sources "https://hyo.world/hq" \
          --implications "Echo chamber check: $target's self-assessment $([ "$verdict" = "ADEQUATE" ] && echo "roughly accurate" || echo "needs external validation")" \
          --next-steps "Review peer-review-${target}-${TODAY}.md. Open tickets: $(echo "$gaps" | wc -l | tr -d ' ') gaps identified." \
          >> "$LOG" 2>&1 || true
      fi

      # Write summary to reviewer's evolution.jsonl
      local evol_file="$HYO_ROOT/agents/$reviewer/evolution.jsonl"
      if [[ -f "$evol_file" || -d "$(dirname "$evol_file")" ]]; then
        python3 << EVEOF 2>/dev/null || true
import json, os
entry = {
    "ts": os.environ.get("NOW_MT", ""),
    "event": "peer_review_complete",
    "reviewer": "$reviewer",
    "target": "$target",
    "verdict": "$verdict",
    "review_file": "$output_file",
    "gaps_found": len("""$gaps""".strip().split("\n")) if """$gaps""".strip() else 0
}
with open("$evol_file", "a") as f:
    f.write(json.dumps(entry) + "\n")
EVEOF
      fi

      return 0
    else
      log_err "Claude Code returned empty or short output for $reviewer → $target review"
      return 1
    fi
  else
    log_err "Claude Code failed for $reviewer → $target review (timeout or error)"
    return 1
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log_section "Cross-Agent Adversarial Review — $TODAY"
  log "Starting weekly peer review cycle"

  # Determine which pairs to run
  local arg1="${1:-}"
  local arg2="${2:-}"

  # Default review pairs
  # nel reviews sam (system/infra quality)
  # sam reviews nel (code/QA integrity)
  # ra reviews aether (analysis citation quality)
  # dex reviews all (pattern consistency across agents)
  declare -A pairs
  pairs=(
    ["nel"]="sam"
    ["sam"]="nel"
    ["ra"]="aether"
    ["dex"]="nel sam ra aether"
  )

  if [[ -n "$arg1" && -n "$arg2" ]]; then
    # Single pair mode
    log "Single pair mode: $arg1 reviews $arg2"
    run_peer_review "$arg1" "$arg2"
  else
    # Full weekly review
    log "Full weekly review — all pairs"
    local total=0 success=0 failed=0

    for reviewer in nel sam ra dex; do
      local targets="${pairs[$reviewer]:-}"
      for target in $targets; do
        total=$((total + 1))
        if run_peer_review "$reviewer" "$target"; then
          success=$((success + 1))
        else
          failed=$((failed + 1))
        fi
        sleep 5  # throttle API calls
      done
    done

    log_section "Cross-Agent Review Summary"
    log "Total pairs: $total | Success: $success | Failed: $failed"

    # Write summary to kai ledger
    local summary_file="$HYO_ROOT/kai/ledger/cross-agent-review-latest.json"
    python3 << SUMEOF 2>/dev/null || true
import json, os
summary = {
    "ts": "$NOW_MT",
    "date": "$TODAY",
    "total_pairs": $total,
    "success": $success,
    "failed": $failed,
    "pairs_run": list({"nel": "sam", "sam": "nel", "ra": "aether", "dex": ["nel","sam","ra","aether"]}.items())
}
with open("$summary_file", "w") as f:
    json.dump(summary, f, indent=2)
SUMEOF
    log "Summary written: $summary_file"
  fi

  log_section "Cross-Agent Review Complete"
}

NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
main "$@"
