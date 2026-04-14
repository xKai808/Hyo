#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/kai/sam.sh
#
# Sam — master coder agent dispatcher
# Runs on Claude Code CLI on the Mini with full network + filesystem access
#
# Usage:
#   kai sam deploy       - git add, commit, push to Vercel; verify deployment live
#   kai sam test         - run all available tests (API, static files, JSON data)
#   kai sam build        - run any build steps needed
#   kai sam fix <issue>  - accept issue description, create plan, implement fix
#   kai sam review       - scan recent changes, check for issues, report findings
#
# INVOCATION FROM THE MINI:
#   claude -p "Read KAI_TASKS.md, pick the top [K] code task, implement it, test it, deploy it, update KAI_TASKS.md"
#

set -uo pipefail

# ---- repo root detection ----------------------------------------------------
if [[ -n "${HYO_ROOT:-}" ]] && [[ -d "$HYO_ROOT" ]]; then
  ROOT="$HYO_ROOT"
else
  ROOT="$HOME/Documents/Projects/Hyo"
fi

LOGS="$ROOT/agents/nel/logs"
TASKS="$ROOT/KAI_TASKS.md"
WEBSITE="$ROOT/agents/sam/website"
API_BASE="${HYO_API_BASE:-https://www.hyo.world}"

mkdir -p "$LOGS"

# ---- color helpers ----------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); MAG=$(tput setaf 5); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; MAG=""; RST=""
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$RST" "$BOLD" "$*" "$RST"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- logging ----------------------------------------------------------------
log_activity() {
  local cmd="$1" status="$2" details="${3:-}"
  local logfile="$LOGS/sam-$(date +%Y-%m-%d).md"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Initialize log if needed
  if [[ ! -f "$logfile" ]]; then
    {
      echo "# Sam Activity Log — $(date +%Y-%m-%d)"
      echo ""
      echo "Master coder agent operations and deployment history."
      echo ""
      echo "---"
      echo ""
    } > "$logfile"
  fi

  # Append activity
  {
    echo "## $timestamp — $cmd ($status)"
    if [[ -n "$details" ]]; then
      echo "$details"
    fi
    echo ""
  } >> "$logfile"

  ok "logged to $logfile"
}

# ---- deploy -----------------------------------------------------------------
cmd_deploy() {
  hdr "Sam: Deploy pipeline"

  local timestamp=$(date '+%Y-%m-%dT%H:%M:%SZ')

  # 1. Check git status
  hdr "1/5 Git status"
  cd "$ROOT"
  git status --short
  echo ""

  # 2. Stage all changes
  hdr "2/5 Stage changes"
  git add -A
  ok "staged"
  echo ""

  # 3. Commit
  hdr "3/5 Create commit"
  local msg="Sam deployment: $timestamp"
  if git commit -m "$msg"; then
    ok "committed"
  else
    warn "no changes to commit"
  fi
  echo ""

  # 4. Push to origin
  hdr "4/5 Push to origin"
  if git push origin "$(git branch --show-current)"; then
    ok "pushed"
  else
    err "push failed — verify git config"
    return 1
  fi
  echo ""

  # 5. Verify deployment live
  hdr "5/5 Verify deployment live"
  sleep 5
  local retry=0
  while [[ $retry -lt 10 ]]; do
    if curl -sf "$API_BASE/api/health" > /dev/null 2>&1; then
      ok "API is live at $API_BASE"
      log_activity "deploy" "success" "Git commit and push completed. Vercel deployment verified live."
      return 0
    fi
    warn "Deployment check $((retry+1))/10 — waiting..."
    sleep 3
    ((retry++))
  done

  err "Deployment verification timeout — check Vercel dashboard"
  log_activity "deploy" "timeout" "Git operations succeeded but Vercel deployment verification failed after 10 attempts."
  return 1
}

# ---- test -------------------------------------------------------------------
cmd_test() {
  hdr "Sam: Test suite"

  local passed=0
  local failed=0

  # 1. API endpoint tests
  hdr "1/3 API smoke tests"
  local tests=(
    "health"
    "register-founder-401"
    "marketplace-400"
  )

  for test in "${tests[@]}"; do
    case "$test" in
      health)
        if curl -sf "$API_BASE/api/health" > /dev/null 2>&1; then
          ok "/api/health"
          ((passed++))
        else
          err "/api/health"
          ((failed++))
        fi
        ;;
      register-founder-401)
        local code
        code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/api/register-founder" \
          -H 'content-type: application/json' \
          -d '{"token":"wrong","agent_name":"test"}')
        if [[ "$code" == "401" ]]; then
          ok "/api/register-founder returns 401 on bad token"
          ((passed++))
        else
          err "/api/register-founder expected 401, got $code"
          ((failed++))
        fi
        ;;
      marketplace-400)
        code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/api/marketplace-request" \
          -H 'content-type: application/json' \
          -d '{"handle":"toolong","email":"test@hyo.world"}')
        if [[ "$code" == "400" ]]; then
          ok "/api/marketplace-request returns 400 for 4+ char handle"
          ((passed++))
        else
          err "/api/marketplace-request expected 400, got $code"
          ((failed++))
        fi
        ;;
    esac
  done
  echo ""

  # 2. Static file tests
  hdr "2/3 Static file verification"
  local static_files=(
    "$WEBSITE/index.html"
    "$WEBSITE/founder-register.html"
    "$WEBSITE/marketplace.html"
    "$WEBSITE/aurora.html"
    "$WEBSITE/hq.html"
    "$WEBSITE/research.html"
    "$WEBSITE/viewer.html"
  )

  for f in "${static_files[@]}"; do
    if [[ -f "$f" && -s "$f" ]]; then
      ok "$(basename "$f") exists and is not empty"
      ((passed++))
    else
      err "$(basename "$f") missing or empty"
      ((failed++))
    fi
  done
  echo ""

  # 3. JSON validation
  hdr "3/3 JSON data validation"
  local json_files=(
    "$ROOT/agents/manifests/aurora.hyo.json"
    "$ROOT/agents/manifests/sentinel.hyo.json"
    "$ROOT/agents/manifests/cipher.hyo.json"
    "$ROOT/agents/manifests/sam.hyo.json"
    "$ROOT/agents/manifests/nel.hyo.json"
    "$ROOT/agents/manifests/ra.hyo.json"
  )

  for f in "${json_files[@]}"; do
    if [[ -f "$f" ]]; then
      if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        ok "$(basename "$f") valid JSON"
        ((passed++))
      else
        err "$(basename "$f") invalid JSON"
        ((failed++))
      fi
    else
      warn "$(basename "$f") not found (may be pending creation)"
    fi
  done
  echo ""

  hdr "Test summary"
  say "Passed: $passed | Failed: $failed"

  # Dispatch integration: report results to Kai ledger
  local DISPATCH="$ROOT/bin/dispatch.sh"
  if [[ -x "$DISPATCH" ]]; then
    if [[ $failed -eq 0 ]]; then
      bash "$DISPATCH" self-delegate sam P3 "Sam test run: $passed passed, 0 failed — all clear" 2>/dev/null || true
    else
      bash "$DISPATCH" flag sam P2 "Sam test run: $failed failure(s) out of $((passed+failed)) tests" 2>/dev/null || true
      # Self-delegate fix tasks for each failure category
      if [[ $failed -gt 3 ]]; then
        bash "$DISPATCH" flag sam P1 "Sam: $failed test failures — needs immediate attention" 2>/dev/null || true
      fi
    fi
  fi

  if [[ $failed -eq 0 ]]; then
    ok "All tests passed"
    log_activity "test" "success" "Passed: $passed tests. Failed: 0."
    return 0
  else
    err "$failed test(s) failed"
    log_activity "test" "failure" "Passed: $passed tests. Failed: $failed."
    return 1
  fi
}

# ---- build ------------------------------------------------------------------
cmd_build() {
  hdr "Sam: Build pipeline"

  cd "$WEBSITE"

  # Check for package.json
  if [[ ! -f "package.json" ]]; then
    warn "No package.json found — assuming static-only website"
    log_activity "build" "skipped" "No package.json — static website, no build needed."
    ok "No build required (static website)"
    return 0
  fi

  # Run npm install
  hdr "npm install"
  if npm install; then
    ok "dependencies installed"
  else
    err "npm install failed"
    log_activity "build" "failure" "npm install failed"
    return 1
  fi

  # Check for build script
  if grep -q '"build"' package.json; then
    hdr "npm run build"
    if npm run build; then
      ok "build completed"
      log_activity "build" "success" "npm install and npm run build completed."
      return 0
    else
      err "build script failed"
      log_activity "build" "failure" "npm run build failed"
      return 1
    fi
  else
    ok "no build script in package.json"
    log_activity "build" "success" "No build script needed (static assets)."
    return 0
  fi
}

# ---- fix --------------------------------------------------------------------
cmd_fix() {
  local issue="$*"
  [[ -z "$issue" ]] && die "usage: kai sam fix <issue description>"

  hdr "Sam: Fix issue"
  say ""
  say "Issue: $issue"
  say ""
  say "Next step: Run on the Mini to implement the fix:"
  say ""
  say "  ${BOLD}claude -p \"Issue: $issue. Read the code, create a plan, implement the fix, test it, and report status.\"${RST}"
  say ""

  log_activity "fix" "initiated" "Issue: $issue"
}

# ---- review -----------------------------------------------------------------
cmd_review() {
  hdr "Sam: Code review"

  cd "$ROOT"

  local issues=0

  # 1. Recent git changes (if git repo exists)
  hdr "1/3 Recent commits"
  if git log --oneline -n 10 2>/dev/null; then
    echo ""
  else
    warn "not a git repository — skipping commit history"
    echo ""
  fi

  # 2. Uncommitted changes (if git repo exists)
  hdr "2/3 Uncommitted changes"
  if git status --short 2>/dev/null; then
    echo ""
  else
    warn "not a git repository — skipping uncommitted changes"
    echo ""
  fi

  # 3. Common issues scan
  hdr "3/3 Common issues scan"

  # Check for TODO comments
  if find "$WEBSITE" -name "*.js" -o -name "*.html" 2>/dev/null | xargs grep -l "TODO\|FIXME\|HACK" 2>/dev/null; then
    warn "TODO/FIXME/HACK comments found (may be intentional)"
    ((issues++))
  fi

  # Check for console.log in production code
  if find "$WEBSITE/api" -name "*.js" -exec grep -l "console\\.log" {} \; 2>/dev/null; then
    warn "console.log found in API code"
    ((issues++))
  fi

  # Check API files are executable
  if ls -l "$WEBSITE/api"/*.js 2>/dev/null | grep -q "^-rw"; then
    ok "API files have correct permissions (644)"
  fi

  echo ""
  hdr "Review complete"
  if [[ $issues -eq 0 ]]; then
    ok "No critical issues found"
    log_activity "review" "success" "Code review complete. No critical issues."
    return 0
  else
    warn "$issues potential issue(s) found — see details above"
    log_activity "review" "warning" "Found $issues potential issues"
    return 0
  fi
}

# ---- help -------------------------------------------------------------------
cmd_help() {
  cat <<EOF
${BOLD}sam${RST} — master coder agent dispatcher

${BOLD}Subcommands${RST}
  kai sam deploy       Git add, commit, push → Vercel deploy, verify live
  kai sam test         Run all tests (API endpoints, static files, JSON)
  kai sam build        Run build steps (npm install, npm run build, etc.)
  kai sam fix <issue>  Accept issue description, output fix command for Mini
  kai sam review       Scan recent changes, check for common issues

${BOLD}Running on the Mini${RST}
  Sam runs on Claude Code CLI where there is full network + filesystem access.
  To invoke Sam from the Mini:

    ${BOLD}claude -p "Read KAI_TASKS.md, pick the top [K] code task, implement it, test it, deploy it, update KAI_TASKS.md"${RST}

  This launches a full Claude Code session on the Mini where Sam can:
  - Read and understand the codebase
  - Implement changes
  - Run tests locally
  - Deploy to Vercel
  - Update task tracking

${BOLD}Activity logging${RST}
  All Sam operations are logged to: $LOGS/sam-YYYY-MM-DD.md

${BOLD}HQ state tracking${RST}
  Sam updates hq-state.json with deployment status and activity.

EOF
}

# ---- evolve: Sam self-evolution logging ----------------------------------------
cmd_evolve() {
  hdr "Sam: Self-evolution logging"

  # Agent gates: trigger validation, resolution pickup, recall
  local AGENT_GATES="$ROOT/kai/protocols/agent-gates.sh"
  if [[ -f "$AGENT_GATES" ]]; then
    source "$AGENT_GATES"
    run_trigger_validation "sam" || true
    run_resolution_pickup "sam" || true
    run_recall_check "sam" || true
  fi

  local EVOLUTION_FILE="$ROOT/agents/sam/evolution.jsonl"
  local PLAYBOOK="$ROOT/agents/sam/PLAYBOOK.md"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Collect Sam-specific metrics
  local tests_passed=0
  local tests_failed=0
  local deploy_status="not_run"
  local api_health="unknown"

  # Quick API health check
  if curl -sf "$API_BASE/api/health" > /dev/null 2>&1; then
    api_health="up"
  else
    api_health="down"
  fi

  # If we have recent test results in the log, parse them
  local latest_test_log="$LOGS/sam-$(date +%Y-%m-%d).md"
  if [[ -f "$latest_test_log" ]]; then
    # Try to extract test results if present
    if grep -q "Passed:" "$latest_test_log"; then
      tests_passed=$(grep "Passed:" "$latest_test_log" | tail -1 | grep -oP 'Passed: \K[0-9]+' | tail -1 || echo "0")
    fi
    if grep -q "Failed:" "$latest_test_log"; then
      tests_failed=$(grep "Failed:" "$latest_test_log" | tail -1 | grep -oP 'Failed: \K[0-9]+' | tail -1 || echo "0")
    fi
  fi

  # Get last evolution entry for comparison
  local last_evolution=""
  if [[ -f "$EVOLUTION_FILE" && -s "$EVOLUTION_FILE" ]]; then
    last_evolution=$(tail -1 "$EVOLUTION_FILE")
  fi

  # Extract last test pass rate
  local last_tests_passed=0
  if [[ -n "$last_evolution" ]]; then
    last_tests_passed=$(echo "$last_evolution" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('metrics', {}).get('tests_passed', 0))" 2>/dev/null || echo "0")
  fi

  # Determine assessment
  local assessment="routine engineering check"
  local improvements_proposed=0
  if [[ $tests_failed -gt 0 ]]; then
    assessment="$tests_failed test failures detected"
    improvements_proposed=$((improvements_proposed + 1))
  elif [[ $tests_passed -gt $last_tests_passed ]]; then
    assessment="test coverage improved: $last_tests_passed → $tests_passed"
    improvements_proposed=$((improvements_proposed + 1))
  fi

  if [[ "$api_health" == "down" ]]; then
    assessment="${assessment}; API health CRITICAL"
    improvements_proposed=$((improvements_proposed + 1))
  fi

  # Check if PLAYBOOK is stale (>7 days)
  local playbook_updated="False"
  local staleness_flag="False"
  if [[ -f "$PLAYBOOK" ]]; then
    local playbook_mtime=$(stat -c %Y "$PLAYBOOK" 2>/dev/null || stat -f %m "$PLAYBOOK" 2>/dev/null || echo "0")
    local playbook_age=$(( ($(date +%s) - playbook_mtime) / 86400 ))
    if [[ $playbook_age -lt 7 ]]; then
      playbook_updated="True"
    elif [[ $playbook_age -gt 7 ]]; then
      staleness_flag="True"
    fi
  fi

  # Build evolution entry
  local evolution_entry=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$timestamp",
  "version": "1.0",
  "metrics": {
    "tests_passed": $tests_passed,
    "tests_failed": $tests_failed,
    "deploy_status": "$deploy_status",
    "api_health": "$api_health"
  },
  "assessment": "$assessment",
  "improvements_proposed": $improvements_proposed,
  "playbook_updated": $playbook_updated,
  "staleness_flag": $staleness_flag
}

print(json.dumps(entry))
PYEOF
)

  # Append to evolution ledger
  echo "$evolution_entry" >> "$EVOLUTION_FILE"
  ok "Self-evolution logged: $assessment"

  if [[ "$staleness_flag" == "True" ]]; then
    warn "PLAYBOOK.md is stale — consider refreshing with latest operational procedures"
  fi
}

# ---- self-review: Sam pathway audit -----------------------------------------
cmd_self_review() {
  say "Self-review: Sam pathway audit..."
  local sr_issues=0

  # INPUT: Website dir exists and has files?
  if [[ ! -d "$WEBSITE" ]]; then
    err "Self-review: website dir missing: $WEBSITE"
    sr_issues=$((sr_issues + 1))
  fi
  if [[ ! -d "$WEBSITE/api" ]]; then
    err "Self-review: api dir missing: $WEBSITE/api"
    sr_issues=$((sr_issues + 1))
  fi

  # PROCESSING: Can we reach the live site?
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' "${API_BASE}/api/health" 2>/dev/null || echo "000")
  if [[ "$http_code" != "200" ]]; then
    err "Self-review: /api/health returned $http_code (expected 200)"
    sr_issues=$((sr_issues + 1))
  fi

  # OUTPUT: Are key HTML files present?
  for page in index.html hq.html research.html; do
    if [[ ! -f "$WEBSITE/$page" ]]; then
      err "Self-review: missing page: $WEBSITE/$page"
      sr_issues=$((sr_issues + 1))
    fi
  done

  # EXTERNAL: Is git status clean?
  local dirty
  dirty=$(cd "$ROOT" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [[ $dirty -gt 20 ]]; then
    warn "Self-review: $dirty uncommitted files in repo"
  fi

  # REPORTING: ACTIVE.md current?
  local sam_active="$ROOT/agents/sam/ledger/ACTIVE.md"
  if [[ -f "$sam_active" ]]; then
    local active_mtime active_age_h
    if [[ "$(uname)" == "Darwin" ]]; then
      active_mtime=$(stat -f %m "$sam_active" 2>/dev/null || echo 0)
    else
      active_mtime=$(stat -c %Y "$sam_active" 2>/dev/null || echo 0)
    fi
    active_age_h=$(( ($(date +%s) - active_mtime) / 3600 ))
    if [[ $active_age_h -gt 48 ]]; then
      warn "Self-review: ACTIVE.md stale (${active_age_h}h)"
      sr_issues=$((sr_issues + 1))
    fi
  fi

  if [[ $sr_issues -eq 0 ]]; then
    ok "Self-review: Sam pathway healthy"
  else
    err "Self-review: $sr_issues issues in Sam pathway"

    # Auto-dispatch if issues found
    local dispatch_bin="$ROOT/bin/dispatch.sh"
    if [[ -x "$dispatch_bin" ]]; then
      bash "$dispatch_bin" flag sam P2 "Sam self-review: $sr_issues pathway issues" 2>/dev/null || true
    fi
  fi
}

# ---- dispatch ---------------------------------------------------------------
sub="${1:-help}"
case "$sub" in
  help|-h|--help)  cmd_help "$@" ;;
  deploy)          cmd_deploy "$@" ;;
  test)            cmd_test "$@" ;;
  build)           cmd_build "$@" ;;
  fix)             shift; cmd_fix "$@" ;;
  review)          cmd_review "$@" ;;
  self-review)     cmd_self_review "$@" ;;
  evolve)          cmd_evolve "$@" ;;
  *)               err "unknown subcommand: $sub"; cmd_help; exit 1 ;;
esac
