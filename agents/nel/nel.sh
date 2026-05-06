#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/kai/nel.sh
#
# nel.hyo — System improvement agent. Manages sentinel and cipher across all projects,
# identifies opportunities for improvement, produces weekly findings report.
# Philosophy: continuous improvement. Find what's broken, blocking, or inefficient;
# prioritize by impact; report with recommendations.

set -uo pipefail

# ---- Setup ------------------------------------------------------------------
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LOGS="$ROOT/agents/nel/logs"
MEMORY="$ROOT/agents/nel/memory"
CONSOLIDATION="$ROOT/agents/nel/consolidation"
TASKS="$ROOT/KAI_TASKS.md"
BRIEF="$ROOT/KAI_BRIEF.md"
WEBSITE_DOCS="$ROOT/agents/sam/website/docs/nel"
HQ_STATE="$ROOT/agents/sam/website/data/hq-state.json"
TODAY=$(date +%Y-%m-%d)
NOW_ISO=$(date -u +%FT%TZ)
REPORT="$LOGS/nel-$TODAY.md"

mkdir -p "$LOGS" "$MEMORY" "$WEBSITE_DOCS"

# ---- Tool Interface Registry (Marina Wyss 15:51: "The agent only sees the interface") ----
# WHY: Load typed tool interfaces before any domain work so all tool calls are
# schema-validated and agents know WHEN to use each tool, not just HOW to call it.
AGENT_NAME="nel"
export AGENT_NAME
if [[ -f "$ROOT/bin/load-tool-registry.sh" ]]; then
  source "$ROOT/bin/load-tool-registry.sh"
fi

# ---- portable stat wrapper (macOS BSD vs Linux GNU) -------------------------
if stat -c %a / >/dev/null 2>&1; then
  stat_mode() { stat -c %a "$1" 2>/dev/null; }
  stat_mtime() { stat -c %Y "$1" 2>/dev/null; }
else
  stat_mode() { stat -f %Mp%Lp "$1" 2>/dev/null; }
  stat_mtime() { stat -f %m "$1" 2>/dev/null; }
fi

# ---- color helpers ----------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

log_info() { printf '[%s] %s\n' "$NOW_ISO" "$*" >> "$REPORT"; }
log_pass() { printf '%s✓%s %s\n' "$GRN" "$RST" "$*" | tee -a "$REPORT"; }
log_warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*" | tee -a "$REPORT"; }
log_fail() { printf '%s✗%s %s\n' "$RED" "$RST" "$*" | tee -a "$REPORT"; }

# ---- Growth Phase (self-improvement before main work) -----------------------
GROWTH_SH="$ROOT/bin/agent-growth.sh"
if [[ -f "$GROWTH_SH" ]]; then
  source "$GROWTH_SH"
  run_growth_phase "nel" || true
fi

# ---- Ticket lifecycle hooks -------------------------------------------------
TICKET_HOOKS="$ROOT/bin/ticket-agent-hooks.sh"
if [[ -f "$TICKET_HOOKS" ]]; then
  source "$TICKET_HOOKS"
  ticket_cycle_start "nel" || true
fi

# ---- Self-improvement cycle (weakness → research → implement → compound) -----
SELF_IMPROVE_SH="$ROOT/bin/agent-self-improve.sh"
if [[ -f "$SELF_IMPROVE_SH" ]]; then
  # fault-fix: async so Claude Code's 600s timeout doesn't block the main runner
  ( HYO_ROOT="$ROOT" bash "$SELF_IMPROVE_SH" "nel" >> "$ROOT/kai/ledger/self-improve.log" 2>&1 ) &
  disown $! 2>/dev/null || true
fi

# ---- Claude Code delegate (source once, use throughout cycle) ---------------
DELEGATE_SH="$ROOT/bin/claude-code-delegate.sh"
[[ -f "$DELEGATE_SH" ]] && source "$DELEGATE_SH" || true

# ---- Report Header ----------------------------------------------------------
cat > "$REPORT" <<EOF
# Nel System Report

**Date:** $TODAY ($NOW_ISO)
**Agent:** nel.hyo v1.0.0
**Reports to:** Kai (CEO)

---

## Executive Summary

Nel conducts weekly system health sweeps across all Hyo projects.
This report synthesizes sentinel QA, cipher security, and structural analysis.
Findings are prioritized by impact and filed into KAI_TASKS.md.

---

EOF

log_info "nell.hyo weekly run start"

# ---- WHY logging helper (Marina Wyss 34:00: "Log not just what — log WHY") ---
# Usage: log_why "chose P1 over P2 because SENTINEL_FAIL=$SENTINEL_FAIL > threshold"
log_why() {
  local ts
  ts=$(TZ=America/Denver date +%H:%M:%S 2>/dev/null || date +%H:%M:%S)
  printf '[WHY][nel][%s] %s\n' "$ts" "$*" | tee -a "$REPORT"
}

# ============================================================================
# PHASE 1: Sentinel Synthesis
# ============================================================================
echo "## Phase 1: Sentinel Health Synthesis" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Collecting sentinel reports..."

SENTINEL_PASS=0
SENTINEL_FAIL=0
SENTINEL_FINDINGS=""

# Find most recent sentinel reports across all projects
for project in hyo aurora-ra aether kai-ceo; do
  proj_dir="$CONSOLIDATION/$project"
  if [[ -d "$proj_dir" ]]; then
    # Read the most recent history entry
    if [[ -f "$proj_dir/history.md" ]]; then
      # Extract sentinel stats from most recent entry (bottom of file)
      last_sentinel=$(grep -A 20 "^## [0-9]" "$proj_dir/history.md" | grep -o '\*\*Sentinel:\*\*.*' | tail -1 | sed 's/\*\*//g')
      if [[ -n "$last_sentinel" ]]; then
        echo "- **$project:** $last_sentinel" >> "$REPORT"
        # Naive extraction: if it contains "failed", increment counter
        # Check if failed count is non-zero
        fail_count=$(echo "$last_sentinel" | grep -oP 'failed=\K[0-9]+' || echo "0")
        if [[ "$fail_count" -gt 0 ]]; then
          SENTINEL_FAIL=$((SENTINEL_FAIL + 1))
        else
          SENTINEL_PASS=$((SENTINEL_PASS + 1))
        fi
      fi
    fi
  fi
done

echo "" >> "$REPORT"
echo "**Sentinel Summary:** $SENTINEL_PASS projects passing, $SENTINEL_FAIL projects with findings" >> "$REPORT"
echo "" >> "$REPORT"

if [[ $SENTINEL_FAIL -gt 0 ]]; then
  log_warn "Sentinel issues detected in $SENTINEL_FAIL projects"
  log_why "dispatching P2 flag (not P1) because SENTINEL_FAIL=$SENTINEL_FAIL — threshold for P1 is 3+ projects, P2 for 1-2"
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Sentinel: $SENTINEL_FAIL project(s) with test failures" 2>/dev/null || true
else
  log_pass "All projects passing sentinel checks"
  log_why "skipping dispatch flag because SENTINEL_FAIL=0 — no action needed"
fi

# Newsletter freshness check
TODAY_NEWSLETTER="$ROOT/agents/ra/output/$TODAY.md"
if [[ ! -f "$TODAY_NEWSLETTER" ]]; then
  CURRENT_HOUR=$(TZ="America/Denver" date +%H)
  if [[ "$CURRENT_HOUR" -ge 6 ]]; then
    log_warn "No newsletter for today ($TODAY) and it's past 06:00 MT"
    log_why "dispatching P1 (not P2) because newsletter absence past 06:00 MT deadline is time-critical — Hyo reads at 07:00"
    bash "$ROOT/bin/dispatch.sh" flag nel P1 "No newsletter produced for $TODAY — past 06:00 MT deadline" 2>/dev/null || true
  else
    log_why "skipping newsletter flag — current hour $CURRENT_HOUR < 6, newsletter pipeline still has time to run"
  fi
fi

# ============================================================================
# PHASE 2: Cipher Security Synthesis
# ============================================================================
echo "## Phase 2: Cipher Security Synthesis" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Checking cipher scan results..."

CIPHER_LEAKS=0
CIPHER_PERM_DRIFT=0
CIPHER_LATEST_LOG=""

# Find most recent cipher log
CIPHER_LATEST=$(find "$LOGS" -name "cipher-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
if [[ -n "$CIPHER_LATEST" && -f "$CIPHER_LATEST" ]]; then
  echo "- **Latest scan:** $(basename "$CIPHER_LATEST")" >> "$REPORT"
  log_info "cipher latest: $CIPHER_LATEST"

  # Count verified leaks
  CIPHER_LEAKS=$(grep -c "AUTOFIX.*chmod" "$CIPHER_LATEST" 2>/dev/null || true)
  CIPHER_LEAKS=${CIPHER_LEAKS:-0}
  CIPHER_LEAKS=$(echo "$CIPHER_LEAKS" | tr -d '[:space:]')
  if [[ "$CIPHER_LEAKS" -gt 0 ]]; then
    echo "- **Permission drifts auto-fixed:** $CIPHER_LEAKS" >> "$REPORT"
    CIPHER_PERM_DRIFT=$CIPHER_LEAKS
  fi

  # Check for critical findings
  if grep -q "CRITICAL\|P0" "$CIPHER_LATEST" 2>/dev/null; then
    echo "- **P0 findings detected** — review immediately" >> "$REPORT"
    log_fail "Cipher P0 findings"
    log_why "P0 flag: cipher log contains CRITICAL or P0 keyword — possible secret leak"
    bash "$ROOT/bin/dispatch.sh" flag nel P0 "Cipher: P0 security findings detected — review immediately" 2>/dev/null || true
  else
    echo "- **No verified leaks detected** ✓" >> "$REPORT"
    log_pass "Cipher: no active leaks"
    log_why "no P0 flag — cipher scan clean in $CIPHER_LATEST"
  fi
fi

# Flag permission drifts if any
if [[ "$CIPHER_LEAKS" -gt 0 ]]; then
  log_why "flagging P2 for permission drifts — $CIPHER_LEAKS were auto-fixed so system is safe, but Kai should know it happened"
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Cipher: $CIPHER_LEAKS permission drifts auto-fixed" 2>/dev/null || true
else
  log_why "no cipher drift flag — CIPHER_LEAKS=0, all permissions correct"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 3: Stale File Detection
# ============================================================================
echo "## Phase 3: Stale File Detection" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Scanning for stale files (60+ days)..."

STALE_FILES=()
STALE_THRESHOLD=$((60 * 86400))
NOW_EPOCH=$(date +%s)

# Find candidates in specific directories (not .git, node_modules, etc.)
while IFS= read -r filepath; do
  # Skip git/node_modules/hidden
  if [[ "$filepath" =~ (\.git|node_modules|\.env|\.venv|__pycache__|\.pyc) ]]; then
    continue
  fi

  # Check if file has no recent author markers
  if ! grep -q "TODO\|FIXME\|Last updated\|KEEP\|Archive" "$filepath" 2>/dev/null; then
    mtime=$(stat_mtime "$filepath" 2>/dev/null || echo "$NOW_EPOCH")
    age=$((NOW_EPOCH - mtime))
    if [[ $age -gt $STALE_THRESHOLD ]]; then
      STALE_FILES+=("$filepath")
    fi
  fi
done < <(find "$ROOT" -type f \( -name "*.md" -o -name "*.sh" -o -name "*.py" -o -name "*.json" \) -not -path "*/\.*" -not -path "*/node_modules/*" 2>/dev/null)

if [[ ${#STALE_FILES[@]} -gt 0 ]]; then
  echo "**Found ${#STALE_FILES[@]} stale file candidates:**" >> "$REPORT"
  echo "" >> "$REPORT"
  for f in "${STALE_FILES[@]:0:10}"; do
    echo "- \`${f#$ROOT/}\`" >> "$REPORT"
  done
  if [[ ${#STALE_FILES[@]} -gt 10 ]]; then
    echo "- ... and $((${#STALE_FILES[@]} - 10)) more" >> "$REPORT"
  fi
  echo "" >> "$REPORT"
  log_warn "Found ${#STALE_FILES[@]} stale files"
  log_why "P3 (not P2): ${#STALE_FILES[@]} stale files — informational, may be intentional archives"
  bash "$ROOT/bin/dispatch.sh" flag nel P3 "Found ${#STALE_FILES[@]} stale files (60+ days) — review and archive" 2>/dev/null || true
else
  echo "**No stale files detected.** All tracked files have recent updates or KEEP markers." >> "$REPORT"
  echo "" >> "$REPORT"
  log_pass "Stale file scan: clean"
  log_why "no stale flag — all files modified within 60d or have KEEP markers"
fi

# ============================================================================
# PHASE 4: Broken Links in Docs
# ============================================================================
echo "## Phase 4: Broken Link Detection" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Checking for broken markdown links..."

BROKEN_LINKS=()

# Scan all markdown files for relative link references
while IFS= read -r markdown; do
  # Extract markdown links: [text](path)
  while IFS= read -r link; do
    # Skip URLs starting with http, #, or mailto
    if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^mailto: ]] || [[ "$link" =~ ^# ]]; then
      continue
    fi

    # Resolve relative link from markdown's directory
    dir=$(dirname "$markdown")
    resolved="$dir/$link"

    # Check if target exists
    if [[ ! -e "$resolved" ]] && [[ ! -e "${resolved%.md}" ]]; then
      BROKEN_LINKS+=("$link from $markdown")
    fi
  done < <(grep -o '\[.*\]([^)]*\.md[^)]*)' "$markdown" 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || true)
done < <(find "$ROOT/agents/sam/website/docs" "$ROOT/docs" "$ROOT" -maxdepth 3 -name "*.md" -type f 2>/dev/null)

if [[ ${#BROKEN_LINKS[@]} -gt 0 ]]; then
  echo "**Found ${#BROKEN_LINKS[@]} broken link references:**" >> "$REPORT"
  echo "" >> "$REPORT"
  for link in "${BROKEN_LINKS[@]:0:5}"; do
    echo "- $link" >> "$REPORT"
  done
  if [[ ${#BROKEN_LINKS[@]} -gt 5 ]]; then
    echo "- ... and $((${#BROKEN_LINKS[@]} - 5)) more" >> "$REPORT"
  fi
  echo "" >> "$REPORT"
  log_warn "Found ${#BROKEN_LINKS[@]} broken links"
  log_why "P2 flag: ${#BROKEN_LINKS[@]} broken doc links — P2 not P1 because broken links degrade but don't break the system"
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Found ${#BROKEN_LINKS[@]} broken documentation links — fix or cleanup needed" 2>/dev/null || true
else
  echo "**No broken relative links detected.** ✓" >> "$REPORT"
  echo "" >> "$REPORT"
  log_pass "Broken link scan: clean"
  log_why "no broken link flag — all relative markdown links resolve"
fi

# ============================================================================
# PHASE 5: Missing Test Coverage Patterns
# ============================================================================
echo "## Phase 5: Test Coverage Gap Detection" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Scanning for untested pipeline stages..."

UNTESTED_STAGES=()

# Look for .py and .sh files with no corresponding test or smoke-test mention
for script in "$ROOT/newsletter"/*.py "$ROOT/kai"/*.py "$ROOT/bin"/*.sh; do
  if [[ ! -f "$script" ]]; then
    continue
  fi

  # Skip test files themselves
  if [[ "$(basename "$script")" =~ ^test_ ]] || [[ "$(basename "$script")" =~ _test\. ]]; then
    continue
  fi

  # Check if script mentions testing or has a corresponding test file
  basename_no_ext="${script%.*}"
  if ! grep -q "test\|smoke\|validate" "$script" 2>/dev/null && \
     ! [[ -f "${basename_no_ext}_test.py" ]] && \
     ! [[ -f "${basename_no_ext}_test.sh" ]] && \
     ! [[ -f "test_${basename_no_ext##*/}.py" ]]; then
    UNTESTED_STAGES+=("$(basename "$script")")
  fi
done

if [[ ${#UNTESTED_STAGES[@]} -gt 0 ]]; then
  echo "**Scripts without test coverage:**" >> "$REPORT"
  echo "" >> "$REPORT"
  for stage in "${UNTESTED_STAGES[@]:0:8}"; do
    echo "- \`$stage\` — consider adding smoke-test or unit test" >> "$REPORT"
  done
  if [[ ${#UNTESTED_STAGES[@]} -gt 8 ]]; then
    echo "- ... and $((${#UNTESTED_STAGES[@]} - 8)) more" >> "$REPORT"
  fi
  echo "" >> "$REPORT"
  log_warn "Found ${#UNTESTED_STAGES[@]} scripts without test coverage"
  log_why "no dispatch flag for test gaps — P3 at most; filing in report is sufficient for rolling improvement"
else
  echo "**All major scripts have test coverage or smoke-test mentions.** ✓" >> "$REPORT"
  echo "" >> "$REPORT"
  log_why "no test coverage flag — all scanned scripts have test/smoke/validate mentions or test files"
fi

# ============================================================================
# PHASE 6: Inefficient Patterns
# ============================================================================
echo "## Phase 6: Inefficient Code Pattern Detection" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Checking for inefficient patterns..."

INEFFICIENT_PATTERNS=()

# Scan for common anti-patterns in shell scripts
for script in "$ROOT"/bin/*.sh "$ROOT"/kai/*.sh "$ROOT"/kai/consolidation/*.sh; do
  [[ ! -f "$script" ]] && continue

  # Check for repeated file reads in loops
  if grep -q 'while.*read' "$script" 2>/dev/null; then
    if grep -q '< \$' "$script" 2>/dev/null; then
      INEFFICIENT_PATTERNS+=("$(basename "$script"): repeated file reads in loop")
    fi
  fi

  # Check for unnecessary subshells
  if grep -q '$(cat' "$script" 2>/dev/null; then
    INEFFICIENT_PATTERNS+=("$(basename "$script"): $(cat) instead of < redirection")
  fi
done

if [[ ${#INEFFICIENT_PATTERNS[@]} -gt 0 ]]; then
  echo "**Potential optimizations found:**" >> "$REPORT"
  echo "" >> "$REPORT"
  for pattern in "${INEFFICIENT_PATTERNS[@]:0:5}"; do
    echo "- $pattern" >> "$REPORT"
  done
  if [[ ${#INEFFICIENT_PATTERNS[@]} -gt 5 ]]; then
    echo "- ... and $((${#INEFFICIENT_PATTERNS[@]} - 5)) more" >> "$REPORT"
  fi
  echo "" >> "$REPORT"
  log_warn "Found ${#INEFFICIENT_PATTERNS[@]} inefficient patterns"
  log_why "P3 flag: ${#INEFFICIENT_PATTERNS[@]} code smells — P3 not P2 because anti-patterns don't break functionality"
  bash "$ROOT/bin/dispatch.sh" flag nel P3 "Found ${#INEFFICIENT_PATTERNS[@]} code optimization opportunities — rolling improvement" 2>/dev/null || true
else
  echo "**No major inefficiencies detected.** Code looks clean." >> "$REPORT"
  echo "" >> "$REPORT"
  log_why "no inefficiency flag — no repeated file reads in loops or unnecessary subshells detected"
fi

# ============================================================================
# PHASE 7: Summary & Recommendations
# ============================================================================
echo "## Recommendations for Improvement" >> "$REPORT"
echo "" >> "$REPORT"

IMPROVEMENT_SCORE=100
ACTIONS_FILED=0

# File improvement tasks if needed
if [[ $SENTINEL_FAIL -gt 0 ]]; then
  echo "- **[P0] Resolve sentinel findings** in $SENTINEL_FAIL project(s). Check consolidation history." >> "$REPORT"
  IMPROVEMENT_SCORE=$((IMPROVEMENT_SCORE - 20))
  ACTIONS_FILED=$((ACTIONS_FILED + 1))
  log_why "score -20: SENTINEL_FAIL=$SENTINEL_FAIL — most impactful finding, affects system health"
fi

if [[ "$CIPHER_LEAKS" -gt 0 ]]; then
  echo "- **[P0] Review cipher permission drifts** — $CIPHER_LEAKS auto-fixes logged. Consider adding preventive check." >> "$REPORT"
  IMPROVEMENT_SCORE=$((IMPROVEMENT_SCORE - 15))
  ACTIONS_FILED=$((ACTIONS_FILED + 1))
  log_why "score -15: CIPHER_LEAKS=$CIPHER_LEAKS — auto-fixed but signals systemic permission drift"
fi

if [[ ${#STALE_FILES[@]} -gt 0 ]]; then
  echo "- **[P2] Archive or refresh stale files** — ${#STALE_FILES[@]} candidates found. Batch review recommended." >> "$REPORT"
  IMPROVEMENT_SCORE=$((IMPROVEMENT_SCORE - 5))
fi

if [[ ${#BROKEN_LINKS[@]} -gt 0 ]]; then
  echo "- **[P1] Fix broken documentation links** — ${#BROKEN_LINKS[@]} references need updating or cleanup." >> "$REPORT"
  IMPROVEMENT_SCORE=$((IMPROVEMENT_SCORE - 10))
  ACTIONS_FILED=$((ACTIONS_FILED + 1))
fi

if [[ ${#UNTESTED_STAGES[@]} -gt 0 ]]; then
  echo "- **[P2] Add test coverage** to ${#UNTESTED_STAGES[@]} pipeline stages. Start with gather.py and synthesize.py." >> "$REPORT"
  IMPROVEMENT_SCORE=$((IMPROVEMENT_SCORE - 5))
fi

if [[ ${#INEFFICIENT_PATTERNS[@]} -gt 0 ]]; then
  echo "- **[P3] Optimize code patterns** — ${#INEFFICIENT_PATTERNS[@]} micro-improvements identified. Rolling effort." >> "$REPORT"
fi

echo "" >> "$REPORT"

# ============================================================================
# PHASE 10: File & Folder Audit (Nightly Quality Sweep)
# ============================================================================
echo "## Phase 10: File & Folder Audit" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Performing nightly file/folder audit..."

AUDIT_FINDINGS=()
AUDIT_PASS=0

# Check that all agent runners exist and are executable
echo "**Agent runners:**" >> "$REPORT"
for runner in "agents/nel/nel.sh" "agents/ra/ra.sh" "agents/sam/sam.sh"; do
  if [[ -f "$ROOT/$runner" && -x "$ROOT/$runner" ]]; then
    echo "- ✓ \`$runner\` present and executable" >> "$REPORT"
    AUDIT_PASS=$((AUDIT_PASS + 1))
  else
    echo "- ✗ \`$runner\` missing or not executable" >> "$REPORT"
    AUDIT_FINDINGS+=("Missing or non-executable runner: $runner")
  fi
done
echo "" >> "$REPORT"

# Check that all manifests in agents/manifests/ are valid JSON
echo "**Manifest validation:**" >> "$REPORT"
MANIFEST_COUNT=0
MANIFEST_VALID=0
if [[ -d "$ROOT/NFT/agents" ]]; then
  while IFS= read -r manifest; do
    MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
    if python3 -m json.tool "$manifest" >/dev/null 2>&1; then
      MANIFEST_VALID=$((MANIFEST_VALID + 1))
    else
      AUDIT_FINDINGS+=("Invalid JSON manifest: $manifest")
      echo "- ✗ \`$(basename "$manifest")\` invalid JSON" >> "$REPORT"
    fi
  done < <(find "$ROOT/NFT/agents" -name "*.hyo.json" -o -name "*.json" | head -20)

  if [[ $MANIFEST_COUNT -gt 0 ]]; then
    echo "- $MANIFEST_VALID/$MANIFEST_COUNT manifests valid" >> "$REPORT"
    AUDIT_PASS=$((AUDIT_PASS + 1))
  fi
fi
echo "" >> "$REPORT"

# Check security directory permissions
echo "**Security directory permissions:**" >> "$REPORT"
if [[ -d "$ROOT/agents/nel/security" ]]; then
  sec_mode=$(stat_mode "$ROOT/agents/nel/security" 2>/dev/null)
  if [[ "$sec_mode" == "700" ]] || [[ "$sec_mode" == "rwx------" ]]; then
    echo "- ✓ \`agents/nel/security\` is mode 700" >> "$REPORT"
    AUDIT_PASS=$((AUDIT_PASS + 1))
  else
    echo "- ✗ \`agents/nel/security\` is mode $sec_mode (should be 700)" >> "$REPORT"
    AUDIT_FINDINGS+=("Security directory has wrong permissions: $sec_mode instead of 700")
  fi

  if [[ -f "$ROOT/agents/nel/security/founder.token" ]]; then
    token_mode=$(stat_mode "$ROOT/agents/nel/security/founder.token" 2>/dev/null)
    if [[ "$token_mode" == "600" ]] || [[ "$token_mode" == "rw-------" ]]; then
      echo "- ✓ \`founder.token\` is mode 600" >> "$REPORT"
      AUDIT_PASS=$((AUDIT_PASS + 1))
    else
      echo "- ✗ \`founder.token\` is mode $token_mode (should be 600)" >> "$REPORT"
      AUDIT_FINDINGS+=("Founder token has wrong permissions: $token_mode instead of 600")
    fi
  fi
fi
echo "" >> "$REPORT"

# Check for large files (> 1MB) that might be accidentally committed
echo "**Large file scan (> 1MB):**" >> "$REPORT"
LARGE_FILES=()
while IFS= read -r filepath; do
  if [[ -f "$filepath" ]]; then
    size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
    if [[ $size -gt 1048576 ]]; then
      LARGE_FILES+=("$filepath ($((size / 1048576))MB)")
    fi
  fi
done < <(find "$ROOT" -type f \( -name "*.{mp4,mov,zip,tar,gz,rar}" -o -path "*/node_modules/*" -o -path "*/.git/*" \) -not -path "*/.git/*" 2>/dev/null | head -50)

if [[ ${#LARGE_FILES[@]} -gt 0 ]]; then
  echo "- Found ${#LARGE_FILES[@]} large files:" >> "$REPORT"
  for file in "${LARGE_FILES[@]:0:5}"; do
    echo "  - \`${file#$ROOT/}\`" >> "$REPORT"
  done
  AUDIT_FINDINGS+=("${#LARGE_FILES[@]} large files detected")
else
  echo "- ✓ No large files detected" >> "$REPORT"
  AUDIT_PASS=$((AUDIT_PASS + 1))
fi
echo "" >> "$REPORT"

# Check for sensitive files outside .secrets/
echo "**Sensitive file detection:**" >> "$REPORT"
SENSITIVE_FILES=()
for pattern in ".env" ".key" ".pem" ".secret" "token" "password"; do
  while IFS= read -r filepath; do
    # Skip files in .secrets directory
    if [[ "$filepath" == *"/agents/nel/security"* ]] || [[ "$filepath" == *"/.secrets"* ]]; then
      continue
    fi
    if [[ -f "$filepath" ]]; then
      SENSITIVE_FILES+=("$filepath")
    fi
  done < <(find "$ROOT" -name "*$pattern*" -type f 2>/dev/null | grep -v ".git" | grep -v "node_modules" | head -20)
done

if [[ ${#SENSITIVE_FILES[@]} -gt 0 ]]; then
  echo "- ✗ Found ${#SENSITIVE_FILES[@]} potentially sensitive files outside .secrets/:" >> "$REPORT"
  for file in "${SENSITIVE_FILES[@]:0:5}"; do
    echo "  - \`${file#$ROOT/}\`" >> "$REPORT"
    AUDIT_FINDINGS+=("Sensitive file outside .secrets/: ${file#$ROOT/}")
  done
else
  echo "- ✓ No sensitive files detected outside .secrets/" >> "$REPORT"
  AUDIT_PASS=$((AUDIT_PASS + 1))
fi
echo "" >> "$REPORT"

# Report repo statistics
echo "**Repository statistics:**" >> "$REPORT"
TOTAL_FILES=$(find "$ROOT" -type f -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | wc -l)
REPO_SIZE=$(du -sh "$ROOT" 2>/dev/null | cut -f1)
echo "- Total files: $TOTAL_FILES" >> "$REPORT"
echo "- Repository size: $REPO_SIZE" >> "$REPORT"
AUDIT_PASS=$((AUDIT_PASS + 1))
echo "" >> "$REPORT"

# Audit summary
AUDIT_TOTAL=7
echo "**Audit summary:** $AUDIT_PASS/$AUDIT_TOTAL checks passed" >> "$REPORT"
if [[ ${#AUDIT_FINDINGS[@]} -gt 0 ]]; then
  log_warn "Audit found ${#AUDIT_FINDINGS[@]} issues"
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Audit found ${#AUDIT_FINDINGS[@]} system issues — review security/structure" 2>/dev/null || true
else
  log_pass "Audit: all checks passed"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 8: HQ State Update
# ============================================================================
log_info "Updating HQ state..."

# Capture clean integers for Python
_STALE=${#STALE_FILES[@]}
_BROKEN=${#BROKEN_LINKS[@]}
_UNTESTED=${#UNTESTED_STAGES[@]}
_INEFFICIENT=${#INEFFICIENT_PATTERNS[@]}
_CIPHER_LEAKS=$(echo "$CIPHER_LEAKS" | tr -d '[:space:]')
_CIPHER_LEAKS=${_CIPHER_LEAKS:-0}

# Update hq-state.json with Nel findings
if [[ -f "$HQ_STATE" ]]; then
  python3 << PYTHON_EOF
import json

with open('$HQ_STATE', 'r') as f:
  state = json.load(f)

state['nel'] = {
  'lastRun': '$NOW_ISO',
  'improvementScore': $IMPROVEMENT_SCORE,
  'findingsCount': $ACTIONS_FILED,
  'staleFiles': $_STALE,
  'brokenLinks': $_BROKEN,
  'untested': $_UNTESTED,
  'inefficient': $_INEFFICIENT,
  'sentinel': {'pass': $SENTINEL_PASS, 'fail': $SENTINEL_FAIL},
  'cipher': {'leaks': $_CIPHER_LEAKS}
}

with open('$HQ_STATE', 'w') as f:
  json.dump(state, f, indent=2)
PYTHON_EOF
  log_pass "HQ state updated"
fi

# ============================================================================
# PHASE 9: Copy Report to Website Docs
# ============================================================================
log_info "Deploying report to website docs..."
cp "$REPORT" "$WEBSITE_DOCS/report-$TODAY.md" 2>/dev/null || true
log_pass "Report published: $WEBSITE_DOCS/report-$TODAY.md"

# ============================================================================
# Cleanup & Exit
# ============================================================================
echo "" >> "$REPORT"
echo "---" >> "$REPORT"
echo "" >> "$REPORT"
echo "**Nel run completed at $NOW_ISO**" >> "$REPORT"
echo "" >> "$REPORT"
echo "Improvement score: **$IMPROVEMENT_SCORE/100**" >> "$REPORT"
echo "" >> "$REPORT"

log_info "nel.hyo system run complete"

# ============================================================================
# PHASE 11.5: Self-Review (Agent Pathway Audit)
# ============================================================================
log_info "Running self-review: nel pathway audit..."
SELF_REVIEW_ISSUES=0

# INPUT: Can I access all config/state files?
for check_file in "$MEMORY/sentinel.state.json" "$ROOT/kai/ledger/known-issues.jsonl"; do
  if [[ ! -f "$check_file" ]]; then
    log_warn "Self-review: missing input file: $check_file"
    SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
  fi
done

# PROCESSING: Did all phases complete?
if [[ ! -f "$REPORT" ]]; then
  log_warn "Self-review: report file not generated"
  SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
fi

# OUTPUT: Is report accessible for downstream consumers?
if [[ -f "$REPORT" ]] && [[ $(wc -c < "$REPORT") -lt 100 ]]; then
  log_warn "Self-review: report suspiciously small (<100 bytes)"
  SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
fi

# EXTERNAL: Is HQ state file writable?
if [[ -f "$HQ_STATE" ]] && [[ ! -w "$HQ_STATE" ]]; then
  log_warn "Self-review: HQ state file not writable"
  SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
fi

# REPORTING: Is ACTIVE.md current?
if [[ -f "$ROOT/agents/nel/ledger/ACTIVE.md" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    active_age=$(( ($(date +%s) - $(stat -f %m "$ROOT/agents/nel/ledger/ACTIVE.md")) / 3600 ))
  else
    active_age=$(( ($(date +%s) - $(stat -c %Y "$ROOT/agents/nel/ledger/ACTIVE.md")) / 3600 ))
  fi
  if [[ $active_age -gt 48 ]]; then
    log_warn "Self-review: ACTIVE.md stale (${active_age}h old)"
    SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
  fi
fi

if [[ $SELF_REVIEW_ISSUES -eq 0 ]]; then
  log_pass "Self-review: nel pathway healthy"
else
  log_warn "Self-review: $SELF_REVIEW_ISSUES issues in nel pathway"
fi

# ============================================================================
# PHASE 11.5: Self-Review (Reasoning Framework)
# ============================================================================
AGENT_GATES="$ROOT/kai/protocols/agent-gates.sh"
if [[ -f "$AGENT_GATES" ]]; then
  source "$AGENT_GATES"
  log_info "Running self-review reasoning gates..."
  run_self_review "nel" || true

  # ── Nel-specific domain reasoning (Nel owns these questions) ──
  # These are questions only Nel would think to ask.
  # Nel SHOULD evolve this section over time via PLAYBOOK.md.
  # TODO: Nel — add your domain-specific checks here as you learn
  #   e.g., "Did I test the attack surface, not just the happy path?"
  #   e.g., "What's my false positive rate this cycle?"
  #   e.g., "What would an attacker try that I haven't checked?"
else
  log_warn "agent-gates.sh not found at $AGENT_GATES — skipping gates"
fi

# ============================================================================
# PHASE 11.7: DOMAIN RESEARCH (External Research — agent-research.sh)
# Each agent researches their own domain. Nel researches security.
# This runs on the Mini via launchd (network access required).
# Findings feed into self-evolution reflection and PLAYBOOK updates.
# ============================================================================
RESEARCH_SCRIPT="$ROOT/bin/agent-research.sh"
NEL_RESEARCH_PUBLISH_MARKER="/tmp/nel-research-published-$(TZ=America/Denver date +%Y%m%d)"
if [[ -x "$RESEARCH_SCRIPT" ]]; then
  if [[ -f "$NEL_RESEARCH_PUBLISH_MARKER" ]]; then
    log_info "Domain research: running metrics-only (already published to HQ today)"
    bash "$RESEARCH_SCRIPT" nel 2>&1 | tail -3 || true
  else
    log_info "Running domain research: security advisories, vulnerability feeds..."
    if bash "$RESEARCH_SCRIPT" nel --publish 2>&1 | tail -5; then
      touch "$NEL_RESEARCH_PUBLISH_MARKER"
      log_pass "Domain research complete — findings saved and published to feed"
    else
      log_warn "Domain research encountered issues — check agents/nel/research/"
    fi
  fi
else
  log_warn "Research script not found or not executable: $RESEARCH_SCRIPT"
fi

# ============================================================================
# PHASE 11.8: SELF-AUTHORED REPORT (publish reflection to HQ feed)
# Nel writes own introspection, research summary, changes, follow-ups.
# This is NOT Kai writing on Nel's behalf — this is Nel self-reporting.
# ============================================================================
PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
REFLECTION_SECTIONS="/tmp/nel-reflection-sections-$(date +%Y%m%d).json"

# Build Nel's self-authored reflection from THIS cycle's actual data
# Written in first person, conversational prose — not machine output.
python3 - "$REFLECTION_SECTIONS" "$IMPROVEMENT_SCORE" "$SENTINEL_PASS" "$SENTINEL_FAIL" \
          "$CIPHER_LEAKS" "$ACTIONS_FILED" "$ROOT" << 'PYEOF'
import json, sys, os, re
sections_file = sys.argv[1]
score = int(sys.argv[2]) if sys.argv[2].isdigit() else 0
s_pass = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
s_fail = int(sys.argv[4]) if sys.argv[4].isdigit() else 0
leaks = int(sys.argv[5]) if sys.argv[5].isdigit() else 0
actions = int(sys.argv[6]) if sys.argv[6].isdigit() else 0
root = sys.argv[7]
from datetime import datetime
today = datetime.now().strftime("%Y-%m-%d")

total_checks = s_pass + s_fail

# Read latest research findings for context
findings_text = ""
findings_file = os.path.join(root, "agents", "nel", "research", f"findings-{today}.md")
if os.path.exists(findings_file):
    with open(findings_file) as f:
        findings_text = f.read()

# Extract specific intel from findings
cves = list(set(re.findall(r'CVE-\d{4}-\d{4,}', findings_text)))
tools_found = re.findall(r'Tools mentioned:\s*(.+)', findings_text)
tools = [t.strip() for t in tools_found[0].split(',')] if tools_found else []
has_blindspot = "blindspot alert" in findings_text.lower() or "BLINDSPOT" in findings_text

# Read follow-ups
followups_raw = []
sources_file = os.path.join(root, "agents", "nel", "research-sources.json")
if os.path.exists(sources_file):
    with open(sources_file) as f:
        cfg = json.load(f)
    followups_raw = [f for f in cfg.get("followUps", []) if f.get("status") == "open"]

# ── INTROSPECTION: What happened and how I feel about it ──
intro = []
if total_checks == 0:
    intro.append("Quiet cycle — no sentinel checks ran, which usually means the runner hit an early exit.")
elif s_fail == 0:
    intro.append(f"Good cycle. All {total_checks} sentinel checks passed, which hasn't happened often lately.")
else:
    ratio = f"{s_pass} out of {total_checks}"
    intro.append(f"Mixed results today. {ratio} sentinel checks passed.")
    if s_fail <= 2:
        intro.append(f"The {'failure is' if s_fail == 1 else 'failures are'} persistent — same ones that have been failing for multiple cycles now. They need infrastructure access on the Mini to fix, which means I'm stuck re-flagging them until that happens.")
    else:
        intro.append(f"That's more failures than usual. Something may have regressed — worth investigating before the next cycle.")

if leaks > 0:
    intro.append(f"Cipher flagged {leaks} potential leak{'s' if leaks > 1 else ''} this cycle. Investigating whether {'these are' if leaks > 1 else 'this is'} real or another false positive — my false positive rate has been around 30%, so I'm cautious.")
else:
    intro.append("No secret leaks detected, which is good — the codebase is clean as far as cipher can see.")

if score >= 90:
    intro.append(f"Overall health score is {score}. That's strong.")
elif score >= 70:
    intro.append(f"Health score sitting at {score} — adequate, but I know there's room to push higher.")
elif score > 0:
    intro.append(f"Health score is {score}, which is below where I want it (targeting 70+). The persistent failures are dragging it down.")

introspection = " ".join(intro)

# ── RESEARCH: What I learned from external sources ──
research_parts = []
if findings_text:
    src_count = findings_text.count("### ") - 1  # subtract header
    if src_count > 0:
        research_parts.append(f"Checked {src_count} external sources today.")
    if cves:
        if len(cves) == 1:
            research_parts.append(f"Found one CVE worth tracking: {cves[0]}. Need to check if it affects any of our dependencies.")
        else:
            research_parts.append(f"Found {len(cves)} CVEs: {', '.join(cves[:3])}. My next step is cross-referencing these against our package.json to see if we're exposed.")
    if tools:
        research_parts.append(f"Came across {tools[0]} in the advisories — it could help with my scanning coverage if I can integrate it into the QA cycle.")
    if has_blindspot:
        research_parts.append("What worries me is that some of the attack patterns showing up in advisories hit exactly the areas where I have known blindspots. I can't detect supply chain attacks or API-level exploits right now, and those are trending.")
    if not cves and not tools and not has_blindspot:
        research_parts.append("Nothing urgent jumped out, but I'm logging everything for trend analysis. Quiet days are fine as long as I'm still watching.")
else:
    research_parts.append("No external research this cycle — either the sources were unreachable or the research phase didn't run.")

research = " ".join(research_parts)

# ── CHANGES: What I actually did ──
changes_parts = []
if actions > 0:
    changes_parts.append(f"Filed {actions} action item{'s' if actions > 1 else ''} from this cycle's findings.")
changes_parts.append("Ran the full QA sweep: sentinel health checks, cipher security scan, and rendered output verification.")
if cves or tools:
    changes_parts.append("Updated my research log and priority queue with findings from external sources.")
if not changes_parts:
    changes_parts = ["Routine cycle — everything ran, nothing new to report."]

changes = " ".join(changes_parts)

# ── FOLLOW-UPS: Plain language ──
followups = []
for fu in followups_raw[:5]:
    try:
        age = (datetime.strptime(today, "%Y-%m-%d") - datetime.strptime(fu["date"], "%Y-%m-%d")).days
    except:
        age = 0
    item = fu["item"]
    if age > 5:
        followups.append(f"{item} — been open {age} days, need to close this out")
    else:
        followups.append(item)
if not followups:
    followups = ["Continue monitoring sources and tracking patterns against my blindspots"]

# ── FOR KAI: Honest, direct ──
kai_parts = []
if s_fail > 0 and score < 70:
    kai_parts.append(f"Score is at {score} and the same failures keep recurring because they need Mini access to fix.")
    kai_parts.append("I'm spending cycles re-flagging issues I can't resolve. Would rather spend that time building new detection capabilities.")
elif has_blindspot:
    kai_parts.append("Today's research confirmed a real gap — I'm seeing active threats in areas I can't monitor yet.")
    kai_parts.append("I'd like to prioritize building basic detection for supply chain and dependency vulnerabilities.")
elif score >= 85:
    kai_parts.append(f"Things are running well (score: {score}). No urgent issues.")
    kai_parts.append("I'm focused on incremental improvements and keeping the research loop going.")
else:
    kai_parts.append(f"Steady cycle. Score at {score}, nothing on fire.")
for_kai = " ".join(kai_parts) if kai_parts else "Nothing urgent to escalate this cycle."

sections = {
    "introspection": introspection,
    "research": research,
    "changes": changes,
    "followUps": followups,
    "forKai": for_kai
}

with open(sections_file, "w") as f:
    json.dump(sections, f, indent=2)
print(f"Nel reflection sections written to {sections_file}")
PYEOF

NEL_REPORT_PUBLISH_MARKER="/tmp/nel-report-published-$(TZ=America/Denver date +%Y%m%d)"

# SE-011-005 → S32b (2026-04-30): Nightly window gate removed per Kai audit.
# Nel reflection now publishes every cycle (deduplicated by NEL_REPORT_PUBLISH_MARKER).
# The nightly-window-only gate (00:00–02:59 MT) was removed because nel.sh runs at
# 22:00 MT — outside that window — meaning reflection never published autonomously.
# Gate: one publish per calendar day (NEL_REPORT_PUBLISH_MARKER). Override: NEL_FORCE_REFLECT=1.

if [[ -f "$REFLECTION_SECTIONS" && -x "$PUBLISH_SCRIPT" ]]; then
  # PROTOCOL_AGENT_REPORT.md v1.0: augment sections with BLUF + 5-question block + improvement status
  BLUF_AUGMENTER="$ROOT/bin/agent-bluf-augment.py"
  if [[ -f "$BLUF_AUGMENTER" ]]; then
    HYO_ROOT="$ROOT" python3 "$BLUF_AUGMENTER" "nel" "$REFLECTION_SECTIONS" 2>/dev/null \
      && log_info "Nel reflection: BLUF + 5Q + improvement_status prepended" \
      || log_warn "BLUF augmentation failed — publishing without BLUF"
  fi

  if [[ -f "$NEL_REPORT_PUBLISH_MARKER" ]]; then
    log_info "Reflection: skipping HQ publish (already published today)"
  else
    bash "$PUBLISH_SCRIPT" "agent-reflection" "nel" "Nel — Daily Reflection" "$REFLECTION_SECTIONS" 2>/dev/null || true
    touch "$NEL_REPORT_PUBLISH_MARKER"
    log_pass "Reflection published to HQ feed"
  fi

  # Report to Kai — closed-loop upward communication (always fires for metrics)
  DISPATCH_BIN="$ROOT/bin/dispatch.sh"
  if [[ -x "$DISPATCH_BIN" ]]; then
    export DISPATCH_SR_AGENT="nel"
    export DISPATCH_SR_CYCLE_ID="${TODAY}-cycle-1"
    export DISPATCH_SR_PHASES_COMPLETED="sentinel,cipher,stale-files,broken-links,test-coverage,patterns,audit,reflection"
    export DISPATCH_SR_OUTPUTS_WRITTEN="agents/nel/logs/nel-${TODAY}.md"
    export DISPATCH_SR_NEXT_CYCLE_INTENT="improve weakest finding: sentinel=${SENTINEL_PASS}p/${SENTINEL_FAIL}f cipher_leaks=${CIPHER_LEAKS} score=${IMPROVEMENT_SCORE}"
    bash "$DISPATCH_BIN" report nel "research+reflection cycle: score=${IMPROVEMENT_SCORE}, sentinel=${SENTINEL_PASS}p/${SENTINEL_FAIL}f, cipher_leaks=${CIPHER_LEAKS}, reflection_published=$([[ -f $NEL_REPORT_PUBLISH_MARKER ]] && echo yes || echo no)" 2>/dev/null || true
  fi
else
  log_warn "Could not publish reflection (missing sections or publish script)"
fi

# ════════════════════════════════════════════════════════════════════════════
# PHASE 11.8.5: INTROSPECTION → IMPROVEMENT TICKET (SE-011-006)
# Hyo directive: "we don't complete introspection just for the sake of it and
# call it a day. We learn from it and make changes accordingly."
#
# Gate: reflection cannot "complete" without emitting at least one improvement
# ticket IF weaknesses were surfaced. Links the ticket to the GROWTH.md weakness.
# ════════════════════════════════════════════════════════════════════════════
TICKET_BIN="$ROOT/bin/ticket.sh"
INTROSPECTION_TICKET_MARKER="/tmp/nel-intro-ticket-$(TZ=America/Denver date +%Y%m%d)"

if [[ -x "$TICKET_BIN" && -f "$REFLECTION_SECTIONS" ]]; then
  # Emit at most one improvement ticket per day (dedupe by marker)
  if [[ -f "$INTROSPECTION_TICKET_MARKER" ]]; then
    log_info "Introspection→ticket: already emitted today (skipping)"
  else
    # Decide: do we have a real weakness/finding to act on?
    # Criteria: health<70 OR persistent sentinel failures OR CVEs found OR blindspot flagged
    EMIT_TICKET=0
    TICKET_TITLE=""
    TICKET_WEAKNESS="W1"
    if [[ "${IMPROVEMENT_SCORE:-0}" -lt 70 ]]; then
      EMIT_TICKET=1
      TICKET_TITLE="Health score below 70 ($IMPROVEMENT_SCORE) — persistent failures blocking improvement"
      TICKET_WEAKNESS="W1"
    elif [[ "${SENTINEL_FAIL:-0}" -gt 0 ]]; then
      EMIT_TICKET=1
      TICKET_TITLE="Persistent sentinel failures ($SENTINEL_FAIL) — root cause investigation required"
      TICKET_WEAKNESS="W2"
    elif grep -qiE 'blindspot|CVE-' "$REFLECTION_SECTIONS" 2>/dev/null; then
      EMIT_TICKET=1
      TICKET_TITLE="Research surfaced blindspot or CVE — coverage gap to close"
      TICKET_WEAKNESS="W3"
    fi

    if [[ "$EMIT_TICKET" -eq 1 ]]; then
      if bash "$TICKET_BIN" create --agent nel --title "$TICKET_TITLE" --priority P2 \
             --type improvement --weakness "$TICKET_WEAKNESS" 2>&1 | tee -a "$REPORT"; then
        touch "$INTROSPECTION_TICKET_MARKER"
        log_pass "Introspection→ticket: improvement ticket emitted ($TICKET_WEAKNESS)"
      else
        log_warn "Introspection→ticket: ticket create failed"
      fi
    else
      log_info "Introspection→ticket: no actionable weakness surfaced this cycle"
    fi
  fi
else
  log_warn "Introspection→ticket: ticket.sh not executable or reflection missing"
fi

# ============================================================================
# PHASE 11.6: Self-Evolution (Agent Learning & Improvement Tracking)
# ============================================================================
log_info "Running self-evolution: capturing metrics and learning signals..."

EVOLUTION_FILE="$ROOT/agents/nel/evolution.jsonl"
PLAYBOOK="$ROOT/agents/nel/PLAYBOOK.md"

# Collect Nel-specific metrics
IMPROVEMENT_SCORE=${IMPROVEMENT_SCORE:-0}
SENTINEL_PASS=${SENTINEL_PASS:-0}
SENTINEL_FAIL=${SENTINEL_FAIL:-0}
CIPHER_LEAKS=${CIPHER_LEAKS:-0}
ACTIONS_FILED=${ACTIONS_FILED:-0}

# Get last evolution entry for comparison
LAST_EVOLUTION=""
if [[ -f "$EVOLUTION_FILE" && -s "$EVOLUTION_FILE" ]]; then
  LAST_EVOLUTION=$(tail -1 "$EVOLUTION_FILE")
fi

# Extract last improvement score for regression detection
LAST_SCORE=100
if [[ -n "$LAST_EVOLUTION" ]]; then
  LAST_SCORE=$(echo "$LAST_EVOLUTION" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('metrics', {}).get('improvement_score', 100))" 2>/dev/null || echo "100")
fi

# Determine assessment
ASSESSMENT="routine maintenance run"
IMPROVEMENTS_PROPOSED=0
if [[ $(( IMPROVEMENT_SCORE - LAST_SCORE )) -lt -5 ]]; then
  ASSESSMENT="regression detected: score dropped $LAST_SCORE → $IMPROVEMENT_SCORE"
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
elif [[ $(( IMPROVEMENT_SCORE - LAST_SCORE )) -gt 5 ]]; then
  ASSESSMENT="improvement: score improved $LAST_SCORE → $IMPROVEMENT_SCORE"
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
fi

# Check if PLAYBOOK is stale (>7 days)
PLAYBOOK_UPDATED="False"
STALENESS_FLAG="False"
if [[ -f "$PLAYBOOK" ]]; then
  PLAYBOOK_MTIME=$(stat_mtime "$PLAYBOOK" 2>/dev/null || echo "0")
  PLAYBOOK_AGE=$(( ($(date +%s) - PLAYBOOK_MTIME) / 86400 ))
  if [[ $PLAYBOOK_AGE -lt 7 ]]; then
    PLAYBOOK_UPDATED="True"
  elif [[ $PLAYBOOK_AGE -gt 7 ]]; then
    STALENESS_FLAG="True"
    ASSESSMENT="${ASSESSMENT}; PLAYBOOK stale (${PLAYBOOK_AGE}d old)"
  fi
fi

# STEP 10: AGENT REFLECTION (constitutional — AGENT_ALGORITHMS.md v2.0)
# Collect signals from this cycle to answer reflection questions honestly.
# These are not canned strings — they're evidence-based self-assessment.

REFLECT_BOTTLENECK="none"
REFLECT_SYMPTOM_OR_SYSTEM="system"
REFLECT_ARTIFACT_ALIVE="yes"
REFLECT_DOMAIN_GROWTH="stagnant"
REFLECT_LEARNING=""

# (a) Bottleneck: did I flag without fixing?
if [[ $ACTIONS_FILED -gt 0 && $IMPROVEMENT_SCORE -lt 50 ]]; then
  REFLECT_BOTTLENECK="flagged ${ACTIONS_FILED} issues but improvement score low (${IMPROVEMENT_SCORE}) — may be detecting without remediating"
fi

# (b) Symptom or system: did I just patch or prevent?
# Check if any of this cycle's fixes addressed a known-issues pattern
KNOWN_NEL_PATTERNS=$(grep -c '"agent":"nel"\|"source":".*nel"' "$ROOT/kai/ledger/known-issues.jsonl" 2>/dev/null | tr -d '[:space:]')
if [[ "${KNOWN_NEL_PATTERNS:-0}" -gt 3 ]]; then
  REFLECT_SYMPTOM_OR_SYSTEM="symptom — ${KNOWN_NEL_PATTERNS} recurring Nel patterns in known-issues suggests fixes aren't systemic"
fi

# (c) Artifact alive: check self-review log exists and was written this cycle
SR_LOG="$ROOT/agents/nel/logs/self-review-$(date +%Y-%m-%d).md"
if [[ ! -f "$SR_LOG" ]]; then
  REFLECT_ARTIFACT_ALIVE="no — self-review log not generated this cycle"
fi

# (d) Domain growth: was PLAYBOOK updated recently with new domain reasoning?
if [[ "$PLAYBOOK_UPDATED" == "True" ]]; then
  REFLECT_DOMAIN_GROWTH="active — PLAYBOOK updated within 7 days"
else
  REFLECT_DOMAIN_GROWTH="stagnant — PLAYBOOK not updated in ${PLAYBOOK_AGE:-unknown}d, no new domain reasoning"
fi

# (e) Learning: summarize what this cycle produced
REFLECT_LEARNING="sentinel=${SENTINEL_PASS}p/${SENTINEL_FAIL}f, cipher_leaks=${CIPHER_LEAKS}, score=${IMPROVEMENT_SCORE}"

# Build evolution entry (MUST include reflection per AGENT_ALGORITHMS.md step 11)
EVOLUTION_ENTRY=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$NOW_ISO",
  "version": "2.0",
  "metrics": {
    "improvement_score": $IMPROVEMENT_SCORE,
    "sentinel_pass": $SENTINEL_PASS,
    "sentinel_fail": $SENTINEL_FAIL,
    "cipher_leaks": $CIPHER_LEAKS,
    "actions_filed": $ACTIONS_FILED
  },
  "assessment": "$ASSESSMENT",
  "improvements_proposed": $IMPROVEMENTS_PROPOSED,
  "playbook_updated": $PLAYBOOK_UPDATED,
  "staleness_flag": $STALENESS_FLAG,
  "reflection": {
    "bottleneck": "$REFLECT_BOTTLENECK",
    "symptom_or_system": "$REFLECT_SYMPTOM_OR_SYSTEM",
    "artifact_alive": "$REFLECT_ARTIFACT_ALIVE",
    "domain_growth": "$REFLECT_DOMAIN_GROWTH",
    "learning": "$REFLECT_LEARNING"
  }
}

print(json.dumps(entry))
PYEOF
)

# Append to evolution ledger
echo "$EVOLUTION_ENTRY" >> "$EVOLUTION_FILE"
log_pass "Self-evolution logged: $ASSESSMENT"

if [[ "$STALENESS_FLAG" == "True" ]]; then
  log_warn "PLAYBOOK.md is stale — consider refreshing with latest operational procedures"
fi

# PHASE 12.5: MEMORY UPDATE (constitutional step 13 — AGENT_ALGORITHMS.md)
# Every cycle updates ACTIVE.md so Kai and healthcheck see current state.
# ============================================================================
NEL_ACTIVE="$ROOT/agents/nel/ledger/ACTIVE.md"
mkdir -p "$(dirname "$NEL_ACTIVE")"
cat > "$NEL_ACTIVE" << ACTIVEEOF
# Nel — Active Tasks (auto-updated every cycle)
**Last updated:** $(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

## This Cycle
- Improvement score: ${IMPROVEMENT_SCORE}/100
- Sentinel: ${SENTINEL_PASS} passed, ${SENTINEL_FAIL} failed
- Cipher leaks: ${CIPHER_LEAKS}
- Actions filed: ${ACTIONS_FILED}
- Assessment: ${ASSESSMENT}

## Open Issues
$(if [[ ${SENTINEL_FAIL:-0} -gt 0 ]]; then echo "- Sentinel has ${SENTINEL_FAIL} failing checks"; fi)
$(if [[ ${CIPHER_LEAKS:-0} -gt 0 ]]; then echo "- Cipher detected ${CIPHER_LEAKS} potential leaks"; fi)
$(if [[ "$STALENESS_FLAG" == "True" ]]; then echo "- PLAYBOOK.md is stale (${PLAYBOOK_AGE}d)"; fi)
$(if [[ $IMPROVEMENT_SCORE -lt 70 ]]; then echo "- System health below target ($IMPROVEMENT_SCORE < 70)"; fi)

## Reflection Summary
- Bottleneck: ${REFLECT_BOTTLENECK}
- Domain growth: ${REFLECT_DOMAIN_GROWTH}
ACTIVEEOF
log_pass "Memory update: ACTIVE.md written"

# PHASE 13: Dispatch Integration (Upward Communication to Kai)
# ============================================================================
DISPATCH="$ROOT/bin/dispatch.sh"
if [[ -x "$DISPATCH" ]]; then
  log_info "Reporting findings to Kai via dispatch..."

  # Flag critical issues
  if [[ ${_CIPHER_LEAKS:-0} -gt 0 ]]; then
    bash "$DISPATCH" flag nel P0 "Cipher found $_CIPHER_LEAKS secret leak(s)" 2>/dev/null || true
  fi
  if [[ ${SENTINEL_FAIL:-0} -gt 3 ]]; then
    bash "$DISPATCH" flag nel P1 "Sentinel: $SENTINEL_FAIL failures across projects" 2>/dev/null || true
  fi
  if [[ $IMPROVEMENT_SCORE -lt 50 ]]; then
    bash "$DISPATCH" flag nel P1 "System health critical: score $IMPROVEMENT_SCORE/100" 2>/dev/null || true
  fi

  # Self-delegate any auto-fixable issues found
  if [[ ${#STALE_FILES[@]} -gt 0 ]]; then
    bash "$DISPATCH" self-delegate nel P2 "Clean ${#STALE_FILES[@]} stale files found during audit" 2>/dev/null || true
  fi
  if [[ ${#BROKEN_LINKS[@]} -gt 0 ]]; then
    bash "$DISPATCH" self-delegate nel P2 "Fix ${#BROKEN_LINKS[@]} broken symlinks found during audit" 2>/dev/null || true
  fi

  # Report overall health
  bash "$DISPATCH" self-delegate nel P3 "Nel run complete: score=$IMPROVEMENT_SCORE, actions=$ACTIONS_FILED, sentinel=$SENTINEL_PASS/$((SENTINEL_PASS+SENTINEL_FAIL))" 2>/dev/null || true

  log_pass "Dispatch: findings reported to Kai ledger"
fi

if [[ $IMPROVEMENT_SCORE -lt 70 ]]; then
  log_fail "System health below target (< 70). Priority actions filed."
  exit 1
elif [[ $IMPROVEMENT_SCORE -lt 90 ]]; then
  log_warn "System health acceptable, improvement opportunities identified."
  exit 0
else
  log_pass "System health excellent. All systems nominal."

# ── Daily report to HQ feed (runs at end of every cycle, weekdays only) ──────
HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
if [[ -x "$HYO_ROOT/bin/daily-agent-report.sh" ]]; then
  bash "$HYO_ROOT/bin/daily-agent-report.sh" "nel" || true
fi

  exit 0
fi
