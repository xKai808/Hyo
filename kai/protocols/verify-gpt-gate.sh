#!/usr/bin/env bash
# verify-gpt-gate.sh — Pre-commit gate for AetherBot analysis files
# Ensures no Analysis file is committed without GPT_VERIFIED: YES
#
# Usage: bash kai/protocols/verify-gpt-gate.sh
# Returns: exit 0 if all analyses verified, exit 1 if any are not
#
# Wire this into: git hooks, scheduled task post-analysis step, kai verify

set -euo pipefail

ANALYSIS_DIR="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/agents/aether/analysis"
FAILED=0

for f in "$ANALYSIS_DIR"/Analysis_*.txt; do
  [ -f "$f" ] || continue
  filename=$(basename "$f")

  # Check if GPT_VERIFIED line exists
  if ! grep -q "^GPT_VERIFIED:" "$f"; then
    echo "FAIL: $filename — missing GPT_VERIFIED line entirely"
    FAILED=1
    continue
  fi

  # Check if it's YES
  if grep -q "^GPT_VERIFIED: YES" "$f"; then
    echo "PASS: $filename — GPT verified"
  else
    echo "FAIL: $filename — GPT_VERIFIED is not YES"
    grep "^GPT_VERIFIED:" "$f"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "BLOCKED: One or more analysis files have not been GPT-verified."
  echo "Run gpt_crosscheck.py for the relevant date(s), integrate the review,"
  echo "then set GPT_VERIFIED: YES | <timestamp> | <review_file>"
  exit 1
fi

echo ""
echo "All analysis files GPT-verified. Clear to commit."
exit 0
