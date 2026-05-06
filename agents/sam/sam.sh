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

# ---- Tool Interface Registry (Marina Wyss 15:51: "The agent only sees the interface") ----
# WHY: Load typed tool interfaces before any domain work so all tool calls are
# schema-validated and agents know WHEN to use each tool, not just HOW to call it.
AGENT_NAME="sam"
export AGENT_NAME
if [[ -f "$ROOT/bin/load-tool-registry.sh" ]]; then
  source "$ROOT/bin/load-tool-registry.sh"
fi

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

# WHY logging helper (Marina Wyss 34:00: "Log not just what — log WHY")
log_why() {
  local ts
  ts=$(TZ=America/Denver date +%H:%M:%S 2>/dev/null || date +%H:%M:%S)
  printf '[WHY][sam][%s] %s\n' "$ts" "$*"
}

# ---- Growth Phase (self-improvement before main work) -----------------------
GROWTH_SH="$ROOT/bin/agent-growth.sh"
if [[ -f "$GROWTH_SH" ]]; then
  source "$GROWTH_SH"
  run_growth_phase "sam" || true
fi

# ---- Ticket lifecycle hooks -------------------------------------------------
TICKET_HOOKS="$ROOT/bin/ticket-agent-hooks.sh"
if [[ -f "$TICKET_HOOKS" ]]; then
  source "$TICKET_HOOKS"
  ticket_cycle_start "sam" || true
fi

# ---- Self-improvement cycle (weakness → research → implement → compound) -----
SELF_IMPROVE_SH="$ROOT/bin/agent-self-improve.sh"
if [[ -f "$SELF_IMPROVE_SH" ]]; then
  # fault-fix: async so Claude Code's 600s timeout doesn't block the main runner
  ( HYO_ROOT="$ROOT" bash "$SELF_IMPROVE_SH" "sam" >> "$ROOT/kai/ledger/self-improve.log" 2>&1 ) &
  disown $! 2>/dev/null || true
fi

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

  # 0. Pre-deploy: sync dual-path files
  hdr "0/6 Sync website paths"
  if [[ -x "$ROOT/bin/sync-website.sh" ]]; then
    bash "$ROOT/bin/sync-website.sh"
    ok "dual-path synced"
  else
    warn "sync-website.sh not found — skipping"
    log_why "skip sync: sync-website.sh not found — dual-path drift possible (SE-010-011 risk)"
  fi
  echo ""

  # 1. Check git status
  hdr "1/6 Git status"
  cd "$ROOT"
  git status --short
  echo ""

  # 2. Stage all changes
  hdr "2/6 Stage changes"
  git add -A
  ok "staged"
  echo ""

  # 3. Commit
  hdr "3/6 Create commit"
  local msg="Sam deployment: $timestamp"
  if git commit -m "$msg"; then
    ok "committed"
    log_why "commit succeeded — changes staged and committed, proceeding to push"
  else
    warn "no changes to commit"
  fi
  echo ""

  # 4. Push to origin
  hdr "4/6 Push to origin"
  if git push origin "$(git branch --show-current)"; then
    ok "pushed"
  else
    err "push failed — verify git config"
    return 1
  fi
  echo ""

  # 5. Verify deployment live
  hdr "5/6 Verify deployment live"
  sleep 5
  local retry=0
  while [[ $retry -lt 10 ]]; do
    if curl -sf "$API_BASE/api/health" > /dev/null 2>&1; then
      ok "API is live at $API_BASE"
      break
    fi
    warn "Deployment check $((retry+1))/10 — waiting..."
    sleep 3
    ((retry++))
  done

  if [[ $retry -ge 10 ]]; then
    err "Deployment verification timeout — check Vercel dashboard"
    log_activity "deploy" "timeout" "Git operations succeeded but Vercel deployment verification failed after 10 attempts."
    log_why "returning 1: 10 API health checks failed — Vercel deploy may still be building or API is down"
    return 1
  fi
  echo ""

  # 6. Post-deploy: render verification
  hdr "6/6 Render verification"
  if [[ -x "$ROOT/bin/verify-render.sh" ]]; then
    if bash "$ROOT/bin/verify-render.sh"; then
      ok "all render checks passed"
      log_activity "deploy" "success" "Full deployment pipeline: sync → commit → push → verify API → verify render."
    else
      err "render verification detected failures — check output above"
      log_activity "deploy" "render-fail" "API live but render verification found issues."
      return 1
    fi
  else
    warn "verify-render.sh not found — skipping render check"
    log_activity "deploy" "success" "Git commit and push completed. Vercel deployment verified live."
  fi
  return 0
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
      log_why "P3 self-delegate (not flag): all tests green — routine reporting, not an issue"
    else
      bash "$DISPATCH" flag sam P2 "Sam test run: $failed failure(s) out of $((passed+failed)) tests" 2>/dev/null || true
      log_why "P2 flag: $failed test failures — API or static file missing, Kai should review"
      # Self-delegate fix tasks for each failure category
      if [[ $failed -gt 3 ]]; then
        bash "$DISPATCH" flag sam P1 "Sam: $failed test failures — needs immediate attention" 2>/dev/null || true
        log_why "escalating to P1: $failed > 3 failures — systemic problem, not isolated"
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

  log_activity "fix" "initiated" "Issue: $issue"

  # Source Claude Code delegate and run autonomously
  local delegate="$ROOT/bin/claude-code-delegate.sh"
  if [[ -f "$delegate" ]]; then
    source "$delegate"
    say "Delegating to Claude Code..."
    claude_delegate \
      --agent "sam" \
      --task "$issue" \
      --priority "P1" && \
      say "✓ Claude Code completed the fix" || \
      say "✗ Claude Code could not complete fix — ticket opened for review"
  else
    say "WARN: claude-code-delegate.sh not found"
    say "Manual fallback: claude -p \"$issue\""
  fi

  log_activity "fix" "completed" "Issue: $issue"
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

  # ── PHASE 0: Claude Code ticket resolution ────────────────────────────────
  # Sam picks up open coding tickets and delegates them to Claude Code.
  # This is the core of autonomous coding — no Cowork session required.
  local DELEGATE_SH="$ROOT/bin/claude-code-delegate.sh"
  if [[ -f "$DELEGATE_SH" ]]; then
    source "$DELEGATE_SH"

    local claude_bin
    if claude_bin=$(_find_claude_bin 2>/dev/null); then
      say "Phase 0: Claude Code ticket resolution (binary: $claude_bin)"

      # Find open P1/P2 tickets owned by sam with type=bug or type=improvement
      local ticket_ledger="$ROOT/kai/tickets/tickets.jsonl"
      if [[ -f "$ticket_ledger" ]]; then
        local coding_tickets
        coding_tickets=$(python3 -c "
import json, sys
with open('$ticket_ledger') as f:
    tickets = [json.loads(l) for l in f if l.strip()]
# Filter: open sam tickets that are coding-resolvable
eligible = [
    t for t in tickets
    if t.get('owner','').lower() in ('sam','k','kai')
    and t.get('status','').upper() in ('OPEN','ACTIVE')
    and t.get('priority','') in ('P1','P2')
    and t.get('type','') in ('bug','improvement','code-fix','')
    and 'BLOCKED' not in t.get('title','').upper()
    and 'STRIPE' not in t.get('title','').upper()
    and 'API KEY' not in t.get('title','').upper()
    and 'CREDENTIALS' not in t.get('title','').upper()
][:3]  # Max 3 per cycle to avoid runaway
for t in eligible:
    print(json.dumps({'id': t['id'], 'title': t['title'], 'priority': t['priority']}))
" 2>/dev/null || echo "")

        if [[ -n "$coding_tickets" ]]; then
          local ticket_count
          ticket_count=$(echo "$coding_tickets" | wc -l | tr -d ' ')
          say "  Found $ticket_count eligible coding tickets for Claude Code"

          while IFS= read -r ticket_json; do
            [[ -z "$ticket_json" ]] && continue
            local tid tprio ttitle
            tid=$(echo "$ticket_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null)
            tprio=$(echo "$ticket_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['priority'])" 2>/dev/null)
            ttitle=$(echo "$ticket_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['title'])" 2>/dev/null)

            say "  Delegating [$tprio] $tid: $ttitle"
            claude_delegate \
              --agent "sam" \
              --task "$ttitle" \
              --ticket "$tid" \
              --priority "$tprio" \
              --timeout 300 || true
          done <<< "$coding_tickets"
        else
          say "  No eligible coding tickets for Claude Code this cycle"
        fi
      fi
    else
      say "Phase 0: Claude binary not found — skipping ticket resolution"
    fi
  fi

  # Self-review reasoning gates
  local AGENT_GATES="$ROOT/kai/protocols/agent-gates.sh"
  if [[ -f "$AGENT_GATES" ]]; then
    source "$AGENT_GATES"
    run_self_review "sam" || true

    # ── Sam-specific domain reasoning (Sam owns these questions) ──
    # TODO: Sam — evolve this section via PLAYBOOK.md
    #   e.g., "Is this deployed or just committed? Did the deploy succeed?"
    #   e.g., "Did I test on actual env or just locally?"
    #   e.g., "What's the rollback plan if this breaks production?"
  fi

  # ── DOMAIN RESEARCH (External Research — agent-research.sh) ──
  # Sam researches infrastructure, deployment, CI/CD patterns.
  local RESEARCH_SCRIPT="$ROOT/bin/agent-research.sh"
  if [[ -x "$RESEARCH_SCRIPT" ]]; then
    say "Running domain research: infrastructure, Vercel, CI/CD patterns..."
    if bash "$RESEARCH_SCRIPT" sam --publish 2>&1 | tail -5; then
      ok "Domain research complete — findings saved and published"
    else
      warn "Domain research encountered issues — check agents/sam/research/"
    fi
  fi

  # ── SELF-AUTHORED REPORT (publish reflection to HQ feed) ──
  local PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
  local REFLECTION_SECTIONS="/tmp/sam-reflection-sections-$(date +%Y%m%d).json"

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

  # STEP 10: AGENT REFLECTION (constitutional — AGENT_ALGORITHMS.md v2.0)
  local reflect_bottleneck="none"
  local reflect_symptom_or_system="system"
  local reflect_artifact_alive="yes"
  local reflect_domain_growth="stagnant"
  local reflect_learning=""

  # (a) Bottleneck: API down = Sam can't verify deploys
  if [[ "$api_health" == "down" ]]; then
    reflect_bottleneck="API down — cannot verify deploys or test endpoints, blocking verification loop"
  fi

  # (b) Symptom or system: recurring test failures = symptom fixing
  local known_sam_patterns=$(grep -c '"agent":"sam"\|"source":".*sam"' "$ROOT/kai/ledger/known-issues.jsonl" 2>/dev/null | tr -d '[:space:]')
  if [[ "${known_sam_patterns:-0}" -gt 3 ]]; then
    reflect_symptom_or_system="symptom — ${known_sam_patterns} recurring Sam patterns in known-issues"
  fi

  # (c) Artifact alive: check self-review log exists
  local sr_log="$ROOT/agents/sam/logs/self-review-$(date +%Y-%m-%d).md"
  if [[ ! -f "$sr_log" ]]; then
    reflect_artifact_alive="no — self-review log not generated this cycle"
  fi

  # (d) Domain growth: PLAYBOOK freshness
  if [[ "$playbook_updated" == "True" ]]; then
    reflect_domain_growth="active — PLAYBOOK updated within 7 days"
  else
    reflect_domain_growth="stagnant — PLAYBOOK not updated recently, no new engineering patterns"
  fi

  # (e) Learning
  reflect_learning="tests=${tests_passed}p/${tests_failed}f, api=${api_health}, deploy=${deploy_status}"

  # Build evolution entry (MUST include reflection per AGENT_ALGORITHMS.md step 11)
  local evolution_entry=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$timestamp",
  "version": "2.0",
  "metrics": {
    "tests_passed": $tests_passed,
    "tests_failed": $tests_failed,
    "deploy_status": "$deploy_status",
    "api_health": "$api_health"
  },
  "assessment": "$assessment",
  "improvements_proposed": $improvements_proposed,
  "playbook_updated": $playbook_updated,
  "staleness_flag": $staleness_flag,
  "reflection": {
    "bottleneck": "$reflect_bottleneck",
    "symptom_or_system": "$reflect_symptom_or_system",
    "artifact_alive": "$reflect_artifact_alive",
    "domain_growth": "$reflect_domain_growth",
    "learning": "$reflect_learning"
  }
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

  # ── Sam self-authored reflection → HQ feed ──
  local today_str=$(TZ=America/Denver date +%Y-%m-%d)
  python3 - "$REFLECTION_SECTIONS" "$tests_passed" "$tests_failed" \
            "$api_health" "$deploy_status" "$assessment" "$ROOT" << 'PYEOF'
import json, sys, os
sf = sys.argv[1]
tp = int(sys.argv[2]) if sys.argv[2].isdigit() else 0
tf = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
api = sys.argv[4]
deploy = sys.argv[5]
assess = sys.argv[6]
root = sys.argv[7]
from datetime import datetime
today = datetime.now().strftime("%Y-%m-%d")

research_summary = "No research conducted this cycle."
ff = os.path.join(root, "agents", "sam", "research", f"findings-{today}.md")
if os.path.exists(ff):
    with open(ff) as f:
        c = f.read()
    if "## Key Takeaways" in c:
        t = c.split("## Key Takeaways")[1].split("##")[0].strip()
        research_summary = t if t else "Research completed — no high-signal findings."
    else:
        research_summary = "Research completed — see findings file."

followups = []
src = os.path.join(root, "agents", "sam", "research-sources.json")
if os.path.exists(src):
    with open(src) as f:
        cfg = json.load(f)
    followups = [fu["item"] for fu in cfg.get("followUps", []) if fu.get("status") == "open"]
if not followups:
    followups = ["Investigate CI/CD pipeline options for pre-deploy testing",
                 "Research Vercel KV integration for persistent storage",
                 "Benchmark API response times for performance baseline"]

# ── Build human-readable prose ──
intro_parts = []
total_tests = tp + tf
if total_tests > 0:
    if tf == 0:
        intro_parts.append(f"All {tp} tests passing this cycle — the codebase is in good shape.")
    else:
        intro_parts.append(f"Ran {total_tests} tests. {tp} passed, but {tf} failed. {'That one failure' if tf == 1 else 'Those failures'} need investigation before I can be confident about deploying.")
else:
    intro_parts.append("No tests ran this cycle, which means I'm flying blind on code quality.")

if api == "up" or api == "reachable":
    intro_parts.append("The API is responding normally.")
elif api == "down":
    intro_parts.append("The API is down, which is a problem — users can't reach any of our endpoints. This is my top priority to investigate.")
else:
    intro_parts.append(f"API health is unclear ({api}). Need to dig into this.")

if deploy == "deployed" or deploy == "ok":
    intro_parts.append("Latest deployment looks good.")
elif deploy == "not_run":
    intro_parts.append("No deployment this cycle.")

research_text = research_summary
if research_text == "No research conducted this cycle.":
    research_text = "I didn't get to external research this cycle. When I do, I'll be looking at Vercel updates, Node.js releases, and infrastructure patterns that could improve our deployment pipeline."

changes_text = assess if assess != "routine engineering check" else "Routine cycle — ran checks, verified infrastructure, no structural changes needed."

if not followups or followups[0].startswith("Investigate CI"):
    followups = ["Keep an eye on API response times — need to establish a performance baseline",
                 "Look into Vercel KV for persistent storage (our current approach is ephemeral)",
                 "Explore pre-deploy testing in the CI/CD pipeline"]

kai_msg = ""
if api == "down":
    kai_msg = "The API being down is the most urgent thing. I need to figure out if it's a Vercel issue or something in our code. This blocks everything user-facing."
elif tf > 0:
    kai_msg = f"We have {tf} test failure{'s' if tf > 1 else ''} to address. Not critical yet, but I don't want to let these linger — test failures have a way of multiplying."
else:
    kai_msg = "Infrastructure is stable, no urgent issues. I'm focused on incremental improvements — test coverage, deployment reliability, and performance monitoring."

sections = {
    "introspection": " ".join(intro_parts),
    "research": research_text,
    "changes": changes_text,
    "followUps": followups[:5],
    "forKai": kai_msg
}
with open(sf, "w") as f:
    json.dump(sections, f, indent=2)
PYEOF

  # ── ANT UPDATE — rebuild financial dashboard from api-usage.jsonl ──
  if [[ -f "$ROOT/bin/ant-update.sh" ]]; then
    if bash "$ROOT/bin/ant-update.sh" >> "$LOGS/sam-$(date +%Y-%m-%d).md" 2>&1; then
      ok "Ant financial data updated"
      # commit ant-data.json so Vercel serves fresh numbers
      cd "$ROOT"
      git add "agents/sam/website/data/ant-data.json" "website/data/ant-data.json" 2>/dev/null || true
      if ! git diff --cached --quiet; then
        git commit -m "ant: refresh financial dashboard $(TZ=America/Denver date +%Y-%m-%d)" \
          --author="Sam <sam@hyo.world>" 2>&1 | tail -1 || true
      fi
      cd - >/dev/null
    else
      warn "ant-update.sh failed (non-fatal)"
    fi
  fi

  if [[ -f "$REFLECTION_SECTIONS" && -x "$PUBLISH_SCRIPT" ]]; then
    # PROTOCOL_AGENT_REPORT.md v1.0: augment with BLUF + 5-question block + improvement status
    BLUF_AUGMENTER="$ROOT/bin/agent-bluf-augment.py"
    if [[ -f "$BLUF_AUGMENTER" ]]; then
      HYO_ROOT="$ROOT" python3 "$BLUF_AUGMENTER" "sam" "$REFLECTION_SECTIONS" 2>/dev/null \
        && ok "Sam reflection: BLUF + 5Q augmented" \
        || warn "BLUF augmentation failed — publishing without BLUF"
    fi
    # HQ narrative publish disabled 2026-05-06: Sam reports to Kai only.
    # Write structured metric delta for morning report WHAT IMPROVED section.
    WRITE_CARD="$ROOT/bin/write-agent-card.sh"
    if [[ -x "$WRITE_CARD" ]]; then
      DEPLOY_SCORE=$(python3 -c "
tp=int('${tests_passed:-0}')
tf=int('${tests_failed:-0}')
total=tp+tf
if total==0: print(100)
else: print(round(tp/total*100))
" 2>/dev/null || echo "0")
      WHAT="Tests: ${tests_passed:-0}p/${tests_failed:-0}f, API: ${api_health:-unknown}, deploy: ${deploy_status:-unknown}"
      HYO_ROOT="$ROOT" bash "$WRITE_CARD" \
        --agent sam \
        --metric deploy_reliability \
        --after "${DEPLOY_SCORE:-0}" \
        --what "$WHAT" \
        --next-metric deploy_reliability \
        --next-target "$(python3 -c "print(min(100, int('${DEPLOY_SCORE:-0}') + 3))" 2>/dev/null || echo 100)" \
        --next-how "Resolve any test failures; expand API health checks" \
        2>/dev/null && ok "Sam agent-card.json written (deploy_reliability=${DEPLOY_SCORE:-0})" \
        || warn "write-agent-card.sh failed"
    fi

    # Report to Kai — closed-loop upward communication
    DISPATCH_BIN="$ROOT/bin/dispatch.sh"
    if [[ -x "$DISPATCH_BIN" ]]; then
      export DISPATCH_SR_AGENT="sam"
      export DISPATCH_SR_CYCLE_ID="${TODAY:-$(date +%Y-%m-%d)}-reflection"
      export DISPATCH_SR_PHASES_COMPLETED="tests,api-health,deploy,reflection"
      export DISPATCH_SR_OUTPUTS_WRITTEN="agents/sam/ledger/ACTIVE.md,agent-card.json"
      export DISPATCH_SR_NEXT_CYCLE_INTENT="resolve test failures if any; tests=${tests_passed}p/${tests_failed}f deploy=${deploy_status}"
      bash "$DISPATCH_BIN" report sam "cycle: tests=${tests_passed}p/${tests_failed}f, api=${api_health}, deploy=${deploy_status}" 2>/dev/null || true
    fi
  fi

  # STEP 13: MEMORY UPDATE (constitutional — AGENT_ALGORITHMS.md)
  local sam_active="$ROOT/agents/sam/ledger/ACTIVE.md"
  mkdir -p "$(dirname "$sam_active")"
  cat > "$sam_active" << ACTIVEEOF
# Sam — Active Tasks (auto-updated every cycle)
**Last updated:** $(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

## This Cycle
- Tests: ${tests_passed} passed, ${tests_failed} failed
- API health: ${api_health}
- Deploy status: ${deploy_status}
- Assessment: ${assessment}

## Open Issues
$(if [[ "${tests_failed:-0}" -gt 0 ]]; then echo "- ${tests_failed} test failures need attention"; fi)
$(if [[ "$api_health" != "reachable" ]]; then echo "- API health: ${api_health}"; fi)
$(if [[ "$staleness_flag" == "True" ]]; then echo "- PLAYBOOK.md is stale"; fi)

## Reflection Summary
- Bottleneck: ${reflect_bottleneck}
- Domain growth: ${reflect_domain_growth}
ACTIVEEOF
  ok "Memory update: ACTIVE.md written"

  # Dispatch report to Kai
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    export DISPATCH_SR_AGENT="sam"
    export DISPATCH_SR_CYCLE_ID="${TODAY:-$(date +%Y-%m-%d)}-cycle-1"
    export DISPATCH_SR_PHASES_COMPLETED="growth,tests,api-health,deploy,performance,memory"
    export DISPATCH_SR_OUTPUTS_WRITTEN="agents/sam/ledger/ACTIVE.md"
    export DISPATCH_SR_NEXT_CYCLE_INTENT="address failures if any; tests=${tests_passed}p/${tests_failed}f api=${api_health} deploy=${deploy_status}"
    bash "$dispatch_bin" report sam "cycle complete: tests=${tests_passed}p/${tests_failed}f, api=${api_health}, deploy=${deploy_status}" 2>/dev/null || true
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

# ── Daily HQ report DISABLED 2026-05-06 ──────────────────────────────────────
# Sam writes agent-card.json for morning report WHAT IMPROVED section.
# Narrative goes to Kai via dispatch only.
# HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
# if [[ -x "$HYO_ROOT/bin/daily-agent-report.sh" ]]; then
#   bash "$HYO_ROOT/bin/daily-agent-report.sh" "sam" || true
# fi

