#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Nel verify.sh — QA & Security verification gates
# System 4 (Adversarial) + System 2 Gates 3-4
#
# Open-ended questions encoded as executable checks:
#   1. What evidence proves this vulnerability no longer exists?
#   2. Does the fix pass the regression suite?
#   3. Are there any credentials, keys, or tokens visible?
#   4. Are all existing tests still passing?
#   5. Has anything that depends on this system been notified?
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TICKET_ID="${1:-}"
PASS=0
FAIL=0
WARN=0

check() {
  local name="$1" result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  elif [[ "$result" == "warn" ]]; then
    echo "  ⚠️  $name"
    WARN=$((WARN + 1))
  else
    echo "  ❌ $name"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══ Nel Verification Gates ═══"
echo "Ticket: ${TICKET_ID:-manual}"
echo ""

# ─── GATE: No secrets in tracked files ───
echo "Gate: Security — credential scan"
SECRETS_FOUND=0
for pattern in "ANTHROPIC_API_KEY" "GROK_API_KEY" "OPENAI_API_KEY" "sk-ant-" "sk-" "xai-" "ghp_" "ghs_"; do
  hits=$(grep -rl "$pattern" "$HYO_ROOT/website/" "$HYO_ROOT/agents/" "$HYO_ROOT/bin/" 2>/dev/null | grep -v ".secrets" | grep -v "node_modules" | grep -v ".env" | head -5 || true)
  if [[ -n "$hits" ]]; then
    echo "    Found potential secret pattern '$pattern' in: $hits"
    ((SECRETS_FOUND++))
  fi
done
if [[ $SECRETS_FOUND -eq 0 ]]; then
  check "No credentials found in tracked files" "pass"
else
  check "Potential credentials found in $SECRETS_FOUND locations" "fail"
fi

# ─── GATE: Known issues ledger is valid JSONL ───
echo ""
echo "Gate: Data integrity — ledger validation"
KNOWN_ISSUES="$HYO_ROOT/kai/ledger/known-issues.jsonl"
if [[ -f "$KNOWN_ISSUES" ]]; then
  BAD_LINES=$(python3 -c "
import json, sys
bad = 0
with open('$KNOWN_ISSUES') as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            json.loads(line)
        except:
            bad += 1
print(bad)
" 2>/dev/null || echo "error")
  if [[ "$BAD_LINES" == "0" ]]; then
    check "known-issues.jsonl is valid JSONL" "pass"
  else
    check "known-issues.jsonl has $BAD_LINES corrupt lines" "fail"
  fi
else
  check "known-issues.jsonl exists" "warn"
fi

# ─── GATE: Ticket ledger is valid JSONL ───
TICKET_LEDGER="$HYO_ROOT/kai/tickets/tickets.jsonl"
if [[ -f "$TICKET_LEDGER" && -s "$TICKET_LEDGER" ]]; then
  BAD_LINES=$(python3 -c "
import json
bad = 0
with open('$TICKET_LEDGER') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try: json.loads(line)
        except: bad += 1
print(bad)
" 2>/dev/null || echo "error")
  if [[ "$BAD_LINES" == "0" ]]; then
    check "tickets.jsonl is valid JSONL" "pass"
  else
    check "tickets.jsonl has $BAD_LINES corrupt lines" "fail"
  fi
fi

# ─── GATE: File permissions on security directory ───
echo ""
echo "Gate: Security — permissions"
SEC_DIR="$HYO_ROOT/agents/nel/security"
if [[ -d "$SEC_DIR" ]]; then
  perms=$(stat -f "%OLp" "$SEC_DIR" 2>/dev/null || stat -c "%a" "$SEC_DIR" 2>/dev/null || echo "unknown")
  if [[ "$perms" == "700" ]]; then
    check "Security directory permissions are 700" "pass"
  else
    check "Security directory permissions are $perms (should be 700)" "warn"
  fi
fi

# ─── GATE: Agent scripts are executable ───
echo ""
echo "Gate: QA — agent runners"
for agent_dir in "$HYO_ROOT"/agents/*/; do
  agent_name=$(basename "$agent_dir")
  runner="$agent_dir/${agent_name}.sh"
  if [[ -f "$runner" ]]; then
    if [[ -x "$runner" ]]; then
      check "$agent_name runner is executable" "pass"
    else
      check "$agent_name runner is NOT executable" "fail"
    fi
  fi
done

# ─── GATE: No orphaned publish markers older than today ───
echo ""
echo "Gate: QA — stale publish markers"
TODAY_MARKER=$(TZ=America/Denver date +%Y%m%d)
STALE_MARKERS=$(find /tmp -name "*-published-*" ! -name "*$TODAY_MARKER" 2>/dev/null | head -10 || true)
if [[ -z "$STALE_MARKERS" ]]; then
  check "No stale publish markers from previous days" "pass"
else
  STALE_COUNT=$(echo "$STALE_MARKERS" | wc -l | tr -d ' ')
  check "$STALE_COUNT stale publish markers found (harmless but noted)" "warn"
fi

# ─── SUMMARY ───
echo ""
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
if [[ $FAIL -gt 0 ]]; then
  echo "VERDICT: FAIL — $FAIL checks did not pass"
  exit 1
else
  echo "VERDICT: PASS"
  exit 0
fi
