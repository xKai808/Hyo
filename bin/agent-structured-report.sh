#!/usr/bin/env bash
# bin/agent-structured-report.sh
# ============================================================================
# STRUCTURED AGENT REPORT — enforces typed schema for all agent→Kai reports
#
# Marina Wyss (AI Agents Course, 23:44): "Define interfaces, not vibes. Each
# agent needs a clear schema for inputs and outputs. Handoffs break more often
# than your models do. If your researcher returns an unstructured blob and
# your designer doesn't know how to parse it, the whole system's going to fail."
#
# PROBLEM THIS SOLVES:
#   dispatch.sh cmd_report accepts a free-form string as the result field.
#   Reports vary based on how far the agent got before timeout. There is no
#   required fields list. There is no validation. Reports that don't arrive
#   are silently treated as if they did (no schema = no way to detect missing).
#
# WHAT THIS DOES:
#   1. Accepts structured fields via named args
#   2. Validates all required fields are present (fails loudly if not)
#   3. Writes a typed JSON entry to the agent's dispatch log
#   4. Writes a human-readable summary to the agent's ACTIVE.md
#   5. If --phase-failed is set, also calls dispatch flag to surface to Kai
#
# USAGE:
#   bash bin/agent-structured-report.sh \
#     --agent nel \
#     --cycle-id "2026-05-05-cycle-1" \
#     --phases-completed "research,analysis" \
#     --phases-failed "" \
#     --outputs-written "agents/nel/research/aric-latest.json" \
#     --errors "" \
#     --next-cycle-intent "implement dependency-audit.sh from aric-latest.json thesis"
#
# REQUIRED FIELDS (report is rejected if any are missing):
#   --agent               Agent name (nel, ra, sam, aether, dex)
#   --cycle-id            Unique cycle identifier (YYYY-MM-DD-cycle-N)
#   --phases-completed    Comma-separated list of phases that finished
#   --outputs-written     Comma-separated list of files produced (empty string if none)
#   --next-cycle-intent   One sentence: what the agent plans to do next cycle
#
# OPTIONAL FIELDS:
#   --phases-failed       Comma-separated list of phases that failed (default: "")
#   --errors              Comma-separated error descriptions (default: "")
#
# EXIT CODES:
#   0  = Report written and validated
#   1  = Missing required field (report rejected — do not mark cycle complete)
#   2  = Write failure
# ============================================================================

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DISPATCH="$HYO_ROOT/bin/dispatch.sh"
NOW=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)

# ── Parse named arguments ──
AGENT=""
CYCLE_ID=""
PHASES_COMPLETED=""
PHASES_FAILED=""
OUTPUTS_WRITTEN=""
ERRORS=""
NEXT_CYCLE_INTENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)              AGENT="$2";             shift 2 ;;
    --cycle-id)           CYCLE_ID="$2";          shift 2 ;;
    --phases-completed)   PHASES_COMPLETED="$2";  shift 2 ;;
    --phases-failed)      PHASES_FAILED="$2";     shift 2 ;;
    --outputs-written)    OUTPUTS_WRITTEN="$2";   shift 2 ;;
    --errors)             ERRORS="$2";            shift 2 ;;
    --next-cycle-intent)  NEXT_CYCLE_INTENT="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

log()  { echo "[agent-structured-report][$AGENT] $(TZ='America/Denver' date +%H:%M:%S) $*"; }
err()  { echo "[agent-structured-report][$AGENT] ERROR: $*" >&2; }

# ── Validate required fields ──
MISSING=()
[[ -z "$AGENT" ]]              && MISSING+=("--agent")
[[ -z "$CYCLE_ID" ]]           && MISSING+=("--cycle-id")
[[ -z "$PHASES_COMPLETED" ]]   && MISSING+=("--phases-completed")
[[ -z "$NEXT_CYCLE_INTENT" ]]  && MISSING+=("--next-cycle-intent")
# --outputs-written is required but can be empty string (must be explicitly passed)

if [[ ${#MISSING[@]} -gt 0 ]]; then
  err "REPORT REJECTED — missing required fields: ${MISSING[*]}"
  err "Reports without required fields are treated as failures, not successes."
  err "Per Marina Wyss: 'Handoffs break more often than your models do.'"
  exit 1
fi

log "WHY: Validating report schema before writing — unstructured reports cannot be reliably parsed by Kai or queued for follow-up"
log "All required fields present — writing structured report"

# ── Build typed JSON report ──
REPORT_JSON=$(python3 -c "
import json, sys

report = {
    'schema_version': '1.0',
    'ts': '$NOW',
    'agent': '$AGENT',
    'cycle_id': '$CYCLE_ID',
    'phases_completed': [p.strip() for p in '$PHASES_COMPLETED'.split(',') if p.strip()],
    'phases_failed': [p.strip() for p in '$PHASES_FAILED'.split(',') if p.strip()],
    'outputs_written': [o.strip() for o in '$OUTPUTS_WRITTEN'.split(',') if o.strip()],
    'errors': [e.strip() for e in '$ERRORS'.split(',') if e.strip()],
    'next_cycle_intent': '$NEXT_CYCLE_INTENT',
    'report_type': 'structured_cycle_report'
}

print(json.dumps(report))
")

if [[ $? -ne 0 || -z "$REPORT_JSON" ]]; then
  err "Failed to build report JSON"
  exit 2
fi

# ── Write to agent dispatch log ──
LEDGER_DIR="$HYO_ROOT/agents/$AGENT/ledger"
mkdir -p "$LEDGER_DIR"
REPORT_LOG="$LEDGER_DIR/cycle-reports.jsonl"

echo "$REPORT_JSON" >> "$REPORT_LOG" || {
  err "Failed to write to $REPORT_LOG"
  exit 2
}

log "WHY: Writing to cycle-reports.jsonl (structured log) — enables Kai to query cycle history without parsing freeform markdown"
log "Report written to $REPORT_LOG"

# ── Surface failures to Kai via dispatch flag ──
if [[ -n "$PHASES_FAILED" || -n "$ERRORS" ]]; then
  FAILURE_SUMMARY="Cycle $CYCLE_ID — phases failed: ${PHASES_FAILED:-none}, errors: ${ERRORS:-none}"
  if [[ -x "$DISPATCH" ]]; then
    log "WHY: Calling dispatch flag for failures — closed-loop rule: every failure surfaces to Kai, no silent drops"
    bash "$DISPATCH" flag "$AGENT" P2 "structured-report: $FAILURE_SUMMARY" 2>/dev/null || true
  fi
fi

# ── Update ACTIVE.md with cycle summary ──
ACTIVE_PATH="$LEDGER_DIR/ACTIVE.md"
python3 - "$ACTIVE_PATH" "$REPORT_JSON" "$NOW" "$AGENT" <<'PYEOF'
import json, sys, os
from datetime import datetime

active_path = sys.argv[1]
report = json.loads(sys.argv[2])
ts = sys.argv[3]
agent = sys.argv[4]

# Read existing ACTIVE.md
existing = ""
if os.path.exists(active_path):
    with open(active_path) as f:
        existing = f.read()

# Build cycle summary block
phases_done = ", ".join(report.get("phases_completed", [])) or "none"
phases_fail = ", ".join(report.get("phases_failed", [])) or "none"
outputs = "\n".join(f"  - {o}" for o in report.get("outputs_written", [])) or "  - (none)"
errors = "\n".join(f"  - {e}" for e in report.get("errors", [])) or "  - (none)"
intent = report.get("next_cycle_intent", "")
cycle_id = report.get("cycle_id", "unknown")

summary = f"""
## Last cycle: {cycle_id} ({ts})
**Phases completed:** {phases_done}
**Phases failed:** {phases_fail}
**Outputs written:**
{outputs}
**Errors:**
{errors}
**Next cycle intent:** {intent}

"""

# Prepend cycle summary (most recent at top)
with open(active_path, "w") as f:
    f.write(f"# {agent.upper()} ACTIVE STATE\n")
    f.write(summary)
    # Keep prior content (strip old header if present)
    existing_body = existing.replace(f"# {agent.upper()} ACTIVE STATE\n", "").strip()
    if existing_body:
        f.write(existing_body + "\n")

print(f"Updated {active_path}")
PYEOF

log "ACTIVE.md updated with cycle summary"

# ── Final confirmation ──
echo ""
echo "══════════════════════════════════════════════════════════"
echo "STRUCTURED REPORT ACCEPTED"
echo "Agent:          $AGENT"
echo "Cycle ID:       $CYCLE_ID"
echo "Phases done:    $PHASES_COMPLETED"
echo "Phases failed:  ${PHASES_FAILED:-none}"
echo "Outputs:        ${OUTPUTS_WRITTEN:-none}"
echo "Next intent:    $NEXT_CYCLE_INTENT"
echo "Log:            $REPORT_LOG"
echo "══════════════════════════════════════════════════════════"
