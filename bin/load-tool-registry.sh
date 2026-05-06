#!/usr/bin/env bash
# bin/load-tool-registry.sh
# ============================================================================
# TOOL INTERFACE REGISTRY LOADER
#
# Marina Wyss (AI Agents Course, 15:51):
# "Every tool has two parts: the interface for the agent — a tool name, a plain
# English description of when to use it, and a typed input schema — and the
# implementation code. The agent only sees the interface."
#
# PROBLEM THIS SOLVES:
#   agents/tools.json is the canonical tool interface registry but was never
#   loaded by any runner. Agents called dispatch.sh, ticket.sh, kai.sh from
#   memory — if the interface changed, runners broke silently with no schema
#   violation error.
#
# WHAT THIS DOES:
#   1. Sources agents/tools.json into shell variables/functions
#   2. Exports validate_tool_call() — validates args before any tool call
#   3. Exports why_log() — structured WHY logging per Marina 34:00
#   4. Exports tool_describe() — prints interface summary for a tool name
#   5. Sets TOOL_REGISTRY_LOADED=1 so runners can gate on it
#
# USAGE (add to top of every runner, after HYO_ROOT is set):
#   source "$HYO_ROOT/bin/load-tool-registry.sh"
#
# WHY: This makes every agent's tool calls schema-validated before execution,
#   not just documented in a file nobody reads.
# ============================================================================

# Guard: don't load twice
[[ "${TOOL_REGISTRY_LOADED:-0}" == "1" ]] && return 0

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TOOL_REGISTRY_FILE="$HYO_ROOT/agents/tools.json"

# ── Warn if registry file missing ──────────────────────────────────────────
if [[ ! -f "$TOOL_REGISTRY_FILE" ]]; then
  echo "[load-tool-registry] WARN: agents/tools.json not found — tool validation disabled" >&2
  TOOL_REGISTRY_LOADED=0
  export TOOL_REGISTRY_LOADED
  return 0
fi

# ── why_log: structured WHY logging (Marina 34:00) ─────────────────────────
# Usage: why_log "$AGENT_NAME" "chose dispatch flag P1 because failure_count=3 exceeds threshold"
why_log() {
  local agent="${1:-unknown}" reason="${2:-}"
  local ts
  ts=$(TZ=America/Denver date +%H:%M:%S 2>/dev/null || date +%H:%M:%S)
  echo "[WHY][$agent][$ts] $reason"
}
export -f why_log 2>/dev/null || true

# ── validate_tool_call: validate args against tool schema ──────────────────
# Usage: validate_tool_call "dispatch" "subcommand=report" "agent=nel" "message=done"
# Returns 0 if valid, 1 if invalid (with error to stderr)
validate_tool_call() {
  local tool_name="$1"; shift
  local args=("$@")  # key=value pairs

  if [[ ! -f "$TOOL_REGISTRY_FILE" ]]; then
    return 0  # fail open if registry missing
  fi

  python3 - "$TOOL_REGISTRY_FILE" "$tool_name" "${args[@]}" << 'PYEOF' 2>/dev/null
import json, sys

registry_file = sys.argv[1]
tool_name = sys.argv[2]
raw_args = sys.argv[3:]

# Parse key=value args
provided = {}
for arg in raw_args:
    if "=" in arg:
        k, v = arg.split("=", 1)
        provided[k.strip()] = v.strip()

try:
    registry = json.loads(open(registry_file).read())
    tools = registry.get("tools", {})
except Exception:
    sys.exit(0)  # fail open on parse error

if tool_name not in tools:
    # Unknown tool — warn but don't block
    print(f"[validate_tool_call] WARN: tool '{tool_name}' not in registry — consider adding it", file=sys.stderr)
    sys.exit(0)

tool = tools[tool_name]
schema = tool.get("input_schema", {})

errors = []
for field_name, field_spec in schema.items():
    if isinstance(field_spec, dict):
        required = field_spec.get("required", False)
        # required can be True, "for report and flag", etc.
        is_required = (required is True)
        if is_required and field_name not in provided:
            errors.append(f"missing required field '{field_name}'")

if errors:
    tool_desc = tool.get("description", "")
    example = tool.get("example", "")
    print(f"[validate_tool_call] SCHEMA ERROR for '{tool_name}': {'; '.join(errors)}", file=sys.stderr)
    print(f"  Tool: {tool_desc}", file=sys.stderr)
    print(f"  Example: {example}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PYEOF
  return $?
}
export -f validate_tool_call 2>/dev/null || true

# ── tool_describe: print interface summary for a tool ──────────────────────
# Usage: tool_describe "dispatch"
tool_describe() {
  local tool_name="${1:-}"
  if [[ -z "$tool_name" || ! -f "$TOOL_REGISTRY_FILE" ]]; then
    echo "Usage: tool_describe <tool_name>"
    return 1
  fi

  python3 - "$TOOL_REGISTRY_FILE" "$tool_name" << 'PYEOF' 2>/dev/null
import json, sys

registry_file = sys.argv[1]
tool_name = sys.argv[2]

try:
    registry = json.loads(open(registry_file).read())
    tool = registry.get("tools", {}).get(tool_name)
except Exception:
    print(f"Could not read registry: {registry_file}")
    sys.exit(1)

if not tool:
    print(f"Tool '{tool_name}' not found in registry")
    sys.exit(1)

print(f"Tool: {tool_name}")
print(f"  Description: {tool.get('description', '')}")
print(f"  When to use: {tool.get('when_to_use', '')}")
print(f"  Binary: {tool.get('binary', '')}")
print(f"  Input schema:")
for k, v in tool.get("input_schema", {}).items():
    if isinstance(v, dict):
        req = v.get("required", False)
        typ = v.get("type", "string")
        desc = v.get("description", "")
        req_label = " [REQUIRED]" if req is True else " [optional]"
        print(f"    {k} ({typ}){req_label}: {desc}")
print(f"  Output: {tool.get('output_format', '')}")
print(f"  Example: {tool.get('example', '')}")
PYEOF
}
export -f tool_describe 2>/dev/null || true

# ── Preload: extract key interface values for fast bash access ──────────────
# These are used by runners to build dispatch calls without looking up the registry
# on every call (Python startup cost would add 100-300ms per call)
DISPATCH_BIN="$HYO_ROOT/bin/dispatch.sh"
TICKET_BIN="$HYO_ROOT/bin/ticket.sh"
KAI_BIN="$HYO_ROOT/bin/kai.sh"
STRUCTURED_REPORT_BIN="$HYO_ROOT/bin/agent-structured-report.sh"

export DISPATCH_BIN TICKET_BIN KAI_BIN STRUCTURED_REPORT_BIN

# ── Mark loaded ─────────────────────────────────────────────────────────────
TOOL_REGISTRY_LOADED=1
export TOOL_REGISTRY_LOADED

# ── Log load (WHY: confirms every runner has the typed interface at startup) ──
_lr_agent="${AGENT_NAME:-$(basename "${BASH_SOURCE[1]:-unknown}" .sh)}"
echo "[load-tool-registry][$_lr_agent] WHY: Tool registry loaded — agents/tools.json gives typed interfaces for dispatch, ticket, kai_push, agent_execute_improvement"
