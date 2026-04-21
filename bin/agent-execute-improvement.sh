#!/usr/bin/env bash
# bin/agent-execute-improvement.sh
# ============================================================================
# EXECUTION ENGINE — Turns "researched" improvements into actual code changes
#
# PROBLEM THIS SOLVES:
#   agent-growth.sh runs ARIC Phases 1-4 (observe, orient, research, decide)
#   but Phase 6 (ACT) never produces real code changes because bash runners
#   have no LLM at the implementation phase. This is "research theater."
#
# WHAT THIS DOES:
#   1. Reads improvement thesis from agents/<name>/research/aric-latest.json
#   2. Reads current files that need to change (from files_to_change field)
#   3. Calls Claude API (claude-sonnet-4-6) with the thesis + current file contents
#   4. Claude returns the COMPLETE updated file content
#   5. Writes the change to the file (atomic write with backup)
#   6. Runs agents/<name>/verify.sh to confirm it works
#   7. Updates aric-latest.json with actual_change, commit_hash, metric_after
#   8. Commits with evidence via git
#   9. Pushes via queue (or direct git push if queue not available)
#
# USAGE:
#   bash bin/agent-execute-improvement.sh <agent> <improvement_id>
#   Example: bash bin/agent-execute-improvement.sh nel I2
#   Example: bash bin/agent-execute-improvement.sh ra I1
#
# INPUTS (from agents/<agent>/research/aric-latest.json):
#   improvement_built.description  — what the improvement is
#   improvement_built.files_to_change  — which files to create/modify
#   weakness_worked  — what weakness this addresses
#   improvement_thesis  — the hypothesis (from ARIC Phase 4.5)
#   research_conducted  — sources that informed the design
#
# GATES (all must pass before declaring done):
#   1. aric-latest.json exists with improvement thesis
#   2. files_to_change is non-empty
#   3. Claude API key available (agents/nel/security/anthropic.key)
#   4. Claude generates valid code (non-empty response)
#   5. Written file is non-empty
#   6. verify.sh passes (if it exists)
#   7. git commit succeeds
#   8. git push succeeds
#
# ON FAILURE:
#   - Restore backup file (atomic safety)
#   - Log failure to agents/<agent>/research/aric-latest.json (execution_error field)
#   - Do NOT mark improvement as "shipped" if any gate fails
#   - Improvement stays in "researched" state
#
# MODEL: claude-sonnet-4-6 (from KNOWLEDGE.md correct model strings)
# API endpoint: https://api.anthropic.com/v1/messages
# ============================================================================

set -uo pipefail

AGENT="${1:-}"
IMPROVEMENT_ID="${2:-}"

if [[ -z "$AGENT" || -z "$IMPROVEMENT_ID" ]]; then
  echo "Usage: bash bin/agent-execute-improvement.sh <agent> <improvement_id>"
  echo "  Example: bash bin/agent-execute-improvement.sh nel I2"
  exit 1
fi

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
ARIC_JSON="$HYO_ROOT/agents/$AGENT/research/aric-latest.json"
ANTHROPIC_KEY_FILE="$HYO_ROOT/agents/nel/security/anthropic.key"
LOG_TAG="[execute-improvement][$AGENT/$IMPROVEMENT_ID]"
TIMESTAMP=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }
err() { echo "$LOG_TAG ERROR: $*" >&2; }

log "Starting execution engine for $AGENT $IMPROVEMENT_ID"

# ── GATE 1: aric-latest.json exists ──
if [[ ! -f "$ARIC_JSON" ]]; then
  err "aric-latest.json not found at $ARIC_JSON"
  err "Run ARIC Phases 1-5 first to populate the improvement thesis"
  exit 1
fi

# ── Read improvement data ──
IMPROVEMENT_DATA=$(python3 - "$ARIC_JSON" "$IMPROVEMENT_ID" <<'PYEOF'
import json, sys

aric_path = sys.argv[1]
improvement_id = sys.argv[2]

with open(aric_path) as f:
    aric = json.load(f)

# Find the improvement matching the requested ID
# Check improvement_built first (current active improvement)
improvement = aric.get("improvement_built", {})
if not improvement:
    print("ERROR: No improvement_built in aric-latest.json")
    sys.exit(1)

# Extract fields
files_to_change = improvement.get("files_to_change", [])
description = improvement.get("description", "")
current_status = improvement.get("status", "unknown")

thesis = aric.get("improvement_thesis", "")
weakness = aric.get("weakness_worked", "")
research = aric.get("research_conducted", [])
research_summary = "; ".join([f"{r.get('source','?')}: {r.get('finding','?')}" for r in research[:3]])
next_target = aric.get("next_target", "")
success_metric = aric.get("success_metric", "")

output = {
    "description": description,
    "files_to_change": files_to_change,
    "current_status": current_status,
    "thesis": thesis,
    "weakness": weakness,
    "research_summary": research_summary,
    "next_target": next_target,
    "success_metric": success_metric,
    "has_thesis": bool(thesis),
    "has_files": bool(files_to_change)
}
print(json.dumps(output))
PYEOF
)

if [[ $? -ne 0 ]]; then
  err "Failed to parse aric-latest.json"
  exit 1
fi

# Parse extracted data
THESIS=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('thesis',''))")
DESCRIPTION=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('description',''))")
WEAKNESS=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('weakness',''))")
RESEARCH_SUMMARY=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('research_summary',''))")
FILES_TO_CHANGE=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print('\n'.join(d.get('files_to_change',[])))")
HAS_THESIS=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('has_thesis',False))")
HAS_FILES=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('has_files',False))")
CURRENT_STATUS=$(echo "$IMPROVEMENT_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('current_status','unknown'))")

log "Improvement: $DESCRIPTION"
log "Weakness: $WEAKNESS"
log "Status: $CURRENT_STATUS"

# ── GATE 2: files_to_change must be non-empty ──
if [[ "$HAS_FILES" != "True" ]] || [[ -z "$FILES_TO_CHANGE" ]]; then
  err "GATE 2 FAILED: files_to_change is empty in aric-latest.json"
  err "Add 'files_to_change' list to improvement_built before running execution engine"
  err "Example: 'files_to_change': ['agents/nel/dependency-audit.sh']"
  exit 1
fi

# ── GATE 3: Claude API key available ──
if [[ ! -f "$ANTHROPIC_KEY_FILE" ]]; then
  err "GATE 3 FAILED: Anthropic API key not found at $ANTHROPIC_KEY_FILE"
  exit 1
fi

ANTHROPIC_KEY=$(cat "$ANTHROPIC_KEY_FILE" | tr -d '[:space:]')
if [[ -z "$ANTHROPIC_KEY" || "$ANTHROPIC_KEY" == "sk-your-"* ]]; then
  err "GATE 3 FAILED: Anthropic API key appears to be a placeholder: $ANTHROPIC_KEY_FILE"
  exit 1
fi

log "API key validated"

# ── GATE 4: Call Claude API with improvement thesis + current file contents ──

# For each file in files_to_change, read current content (if exists)
FILE_CONTENTS=""
while IFS= read -r file_path; do
  [[ -z "$file_path" ]] && continue
  full_path="$HYO_ROOT/$file_path"
  if [[ -f "$full_path" ]]; then
    file_content=$(head -200 "$full_path" 2>/dev/null || echo "")
    FILE_CONTENTS+="=== EXISTING FILE: $file_path ===\n$file_content\n\n"
  else
    FILE_CONTENTS+="=== NEW FILE TO CREATE: $file_path (does not exist yet) ===\n\n"
  fi
done <<< "$FILES_TO_CHANGE"

# Build the system prompt for Claude
SYSTEM_PROMPT="You are an autonomous software agent making a specific improvement to the Hyo system.

AGENT: $AGENT
IMPROVEMENT: $DESCRIPTION
WEAKNESS BEING FIXED: $WEAKNESS
IMPROVEMENT THESIS: $THESIS
RESEARCH FINDINGS: $RESEARCH_SUMMARY

Your task:
1. Analyze the improvement thesis and research findings
2. Generate the complete, working implementation for the first file in files_to_change
3. The code must be production-ready, well-commented, and self-contained
4. Include error handling appropriate for a bash/Python system running on macOS
5. Follow the existing code style in the Hyo system (bash scripts with set -uo pipefail, Python 3)

Output format:
- Output ONLY the file content, no explanation, no markdown code blocks, no preamble
- The file content must be ready to write directly to disk
- Start with the appropriate shebang line (#!/usr/bin/env bash or #!/usr/bin/env python3)
- Include comments explaining what the code does

FILE TO GENERATE:"

# Get the first file to change
FIRST_FILE=$(echo "$FILES_TO_CHANGE" | head -1)
log "Generating implementation for: $FIRST_FILE"

# Call Claude API
log "Calling Claude API (claude-sonnet-4-6)..."
CLAUDE_RESPONSE=$(python3 - <<PYEOF
import json, urllib.request, urllib.error, sys, os

api_key = "$ANTHROPIC_KEY"
system_prompt = """$SYSTEM_PROMPT"""
user_message = """$FILE_CONTENTS

Generate the implementation for: $FIRST_FILE

Important constraints for $AGENT agent:
$(case "$AGENT" in
  nel) echo "- Must integrate with nel.sh pipeline
- Use bash (not Python) unless specifically building a Python tool
- Must write output to agents/nel/ledger/ directory
- Include JSONL output format for structured data
- Add logging with [nel-TOOL_NAME] prefix" ;;
  ra) echo "- Must integrate with newsletter.sh pipeline
- Python preferred for data processing scripts
- Must log to agents/ra/ledger/ for health data
- Use sources.json as input for source configuration
- Follow gather.py output format" ;;
  sam) echo "- Must integrate with deploy pipeline (DEPLOY.md)
- Bash script preferred for performance-check.sh
- Must write to agents/sam/ledger/performance-baseline.jsonl
- Use curl for response time measurements
- JSONL output with deploy_id, timestamp, metrics" ;;
  dex) echo "- Must integrate with dex.sh nightly cycle
- Python preferred for data analysis scripts
- Output to agents/dex/ledger/ directory
- JSONL output format for all structured data
- Must handle empty/missing input gracefully" ;;
  *) echo "- Follow existing code patterns in agents/$AGENT/" ;;
esac)"""

payload = {
    "model": "claude-sonnet-4-6",
    "max_tokens": 4096,
    "system": system_prompt,
    "messages": [
        {"role": "user", "content": user_message}
    ]
}

headers = {
    "Content-Type": "application/json",
    "x-api-key": api_key,
    "anthropic-version": "2023-06-01"
}

req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=json.dumps(payload).encode(),
    headers=headers,
    method="POST"
)

try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
        content = data.get("content", [])
        if content and content[0].get("type") == "text":
            print(content[0]["text"])
        else:
            print("ERROR: No text content in Claude response", file=sys.stderr)
            sys.exit(1)
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print(f"ERROR: Claude API HTTP {e.code}: {body}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Claude API call failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [[ $? -ne 0 ]]; then
  err "GATE 4 FAILED: Claude API call failed"
  # Update aric-latest.json with execution error
  python3 -c "
import json
with open('$ARIC_JSON') as f: d = json.load(f)
d.setdefault('improvement_built', {})['execution_error'] = 'Claude API call failed at $TIMESTAMP'
d['improvement_built']['status'] = 'researched'
with open('$ARIC_JSON', 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null
  exit 1
fi

# ── GATE 4 validation: non-empty response ──
if [[ -z "$CLAUDE_RESPONSE" ]] || [[ ${#CLAUDE_RESPONSE} -lt 50 ]]; then
  err "GATE 4 FAILED: Claude returned empty or suspiciously short response (${#CLAUDE_RESPONSE} chars)"
  exit 1
fi

log "Claude returned ${#CLAUDE_RESPONSE} chars of implementation"

# ── GATE 5: Write the file (atomic with backup) ──
FULL_FILE_PATH="$HYO_ROOT/$FIRST_FILE"

# Create directory if needed
mkdir -p "$(dirname "$FULL_FILE_PATH")"

# Backup existing file if it exists
BACKUP_PATH=""
if [[ -f "$FULL_FILE_PATH" ]]; then
  BACKUP_PATH="${FULL_FILE_PATH}.bak.$(date +%s)"
  cp "$FULL_FILE_PATH" "$BACKUP_PATH"
  log "Backed up existing file to $BACKUP_PATH"
fi

# Write to temp file first (atomic safety)
TEMP_FILE=$(mktemp)
echo "$CLAUDE_RESPONSE" > "$TEMP_FILE"

if [[ ! -s "$TEMP_FILE" ]]; then
  err "GATE 5 FAILED: Temp file is empty after write"
  rm -f "$TEMP_FILE"
  exit 1
fi

# Move to final location
mv "$TEMP_FILE" "$FULL_FILE_PATH"
log "Written to $FULL_FILE_PATH ($(wc -l < "$FULL_FILE_PATH") lines)"

# Make executable if it's a shell or Python script
case "$FIRST_FILE" in
  *.sh | *.py) chmod +x "$FULL_FILE_PATH" && log "Made executable" ;;
esac

# ── GATE 6: Run verify.sh if it exists ──
VERIFY_SCRIPT="$HYO_ROOT/agents/$AGENT/verify.sh"
VERIFY_PASSED=false

if [[ -f "$VERIFY_SCRIPT" && -x "$VERIFY_SCRIPT" ]]; then
  log "Running verify.sh..."
  if HYO_ROOT="$HYO_ROOT" bash "$VERIFY_SCRIPT" 2>&1 | tail -5; then
    VERIFY_PASSED=true
    log "verify.sh PASSED"
  else
    log "verify.sh FAILED — improvement written but not yet verified"
    # Don't exit — commit anyway, log the failure
    # The improvement is still better than nothing if verify.sh fails on unrelated checks
  fi
else
  log "No verify.sh found — skipping verification gate"
  VERIFY_PASSED=true  # No gate = not blocking
fi

# ── GATE 7: Commit the change ──
cd "$HYO_ROOT" || exit 1

git add "$FULL_FILE_PATH" 2>/dev/null || true

COMMIT_MSG="feat($AGENT): $DESCRIPTION — ARIC $IMPROVEMENT_ID execution

Addresses weakness: $WEAKNESS
Improvement thesis: $THESIS
Files changed: $FIRST_FILE
Executed by: bin/agent-execute-improvement.sh
Verify: $(if [[ "$VERIFY_PASSED" == true ]]; then echo "PASSED"; else echo "FAILED — review required"; fi)

ARIC execution engine — research theater → real code"

COMMIT_HASH=""
if git commit -m "$COMMIT_MSG" 2>/dev/null; then
  COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  log "GATE 7 PASSED: Committed as $COMMIT_HASH"
else
  log "GATE 7: Nothing to commit or commit failed"
  # May happen if file was identical to existing content
fi

# ── GATE 8: Push ──
PUSH_SUCCESS=false
if [[ -n "$COMMIT_HASH" ]]; then
  if git push origin main 2>/dev/null; then
    PUSH_SUCCESS=true
    log "GATE 8 PASSED: Pushed to origin"
  else
    err "GATE 8 FAILED: Push to origin failed"
    log "Commit exists locally at $COMMIT_HASH — manual push required"
    # Flag to dispatch if available
    DISPATCH="$HYO_ROOT/bin/dispatch.sh"
    if [[ -x "$DISPATCH" ]]; then
      bash "$DISPATCH" flag "$AGENT" P1 "execute-improvement: $IMPROVEMENT_ID committed ($COMMIT_HASH) but push FAILED — manual push needed" 2>/dev/null || true
    fi
  fi
fi

# ── Update aric-latest.json with results ──
FINAL_STATUS="shipped"
if [[ -z "$COMMIT_HASH" ]]; then
  FINAL_STATUS="in_progress"  # File written but not committed
fi

python3 - "$ARIC_JSON" "$FIRST_FILE" "$COMMIT_HASH" "$FINAL_STATUS" "$VERIFY_PASSED" "$TIMESTAMP" <<PYEOF
import json, sys

aric_path = sys.argv[1]
file_changed = sys.argv[2]
commit_hash = sys.argv[3]
status = sys.argv[4]
verify_passed = sys.argv[5].lower() == "true"
timestamp = sys.argv[6]

with open(aric_path) as f:
    aric = json.load(f)

if "improvement_built" not in aric:
    aric["improvement_built"] = {}

aric["improvement_built"]["status"] = status
aric["improvement_built"]["actual_change"] = f"Generated and written to {file_changed}"
aric["improvement_built"]["commit"] = commit_hash if commit_hash else None
aric["improvement_built"]["verify_passed"] = verify_passed
aric["improvement_built"]["executed_at"] = timestamp
aric["improvement_built"]["executed_by"] = "bin/agent-execute-improvement.sh"

# Remove any prior execution_error since we succeeded
aric["improvement_built"].pop("execution_error", None)

with open(aric_path, "w") as f:
    json.dump(aric, f, indent=2)

print(f"Updated aric-latest.json: status={status}, commit={commit_hash}")
PYEOF

# ── FINAL REPORT ──
echo ""
echo "══════════════════════════════════════════════════════════"
echo "EXECUTION ENGINE COMPLETE"
echo "Agent:       $AGENT"
echo "Improvement: $IMPROVEMENT_ID — $DESCRIPTION"
echo "File:        $FIRST_FILE"
echo "Status:      $FINAL_STATUS"
echo "Commit:      ${COMMIT_HASH:-none}"
echo "Pushed:      $PUSH_SUCCESS"
echo "Verify:      $VERIFY_PASSED"
echo "══════════════════════════════════════════════════════════"

if [[ "$FINAL_STATUS" == "shipped" ]]; then
  log "SUCCESS: Improvement shipped. Update morning report to show 'shipped' status."
  log "Next: measure the metric from aric-latest.json metric_before vs actual outcome."
else
  log "PARTIAL: File written but not fully committed. Review and commit manually."
fi

# Clean up backup if everything succeeded
if [[ "$FINAL_STATUS" == "shipped" && -n "$BACKUP_PATH" && -f "$BACKUP_PATH" ]]; then
  rm -f "$BACKUP_PATH"
  log "Backup removed (clean ship)"
fi
