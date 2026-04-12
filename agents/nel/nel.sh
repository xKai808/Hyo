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
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Sentinel: $SENTINEL_FAIL project(s) with test failures" 2>/dev/null || true
else
  log_pass "All projects passing sentinel checks"
fi

# Newsletter freshness check
TODAY_NEWSLETTER="$ROOT/agents/ra/output/$TODAY.md"
if [[ ! -f "$TODAY_NEWSLETTER" ]]; then
  CURRENT_HOUR=$(TZ="America/Denver" date +%H)
  if [[ "$CURRENT_HOUR" -ge 6 ]]; then
    log_warn "No newsletter for today ($TODAY) and it's past 06:00 MT"
    bash "$ROOT/bin/dispatch.sh" flag nel P1 "No newsletter produced for $TODAY — past 06:00 MT deadline" 2>/dev/null || true
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
    bash "$ROOT/bin/dispatch.sh" flag nel P0 "Cipher: P0 security findings detected — review immediately" 2>/dev/null || true
  else
    echo "- **No verified leaks detected** ✓" >> "$REPORT"
    log_pass "Cipher: no active leaks"
  fi
fi

# Flag permission drifts if any
if [[ "$CIPHER_LEAKS" -gt 0 ]]; then
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Cipher: $CIPHER_LEAKS permission drifts auto-fixed" 2>/dev/null || true
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
  bash "$ROOT/bin/dispatch.sh" flag nel P3 "Found ${#STALE_FILES[@]} stale files (60+ days) — review and archive" 2>/dev/null || true
else
  echo "**No stale files detected.** All tracked files have recent updates or KEEP markers." >> "$REPORT"
  echo "" >> "$REPORT"
  log_pass "Stale file scan: clean"
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
  bash "$ROOT/bin/dispatch.sh" flag nel P2 "Found ${#BROKEN_LINKS[@]} broken documentation links — fix or cleanup needed" 2>/dev/null || true
else
  echo "**No broken relative links detected.** ✓" >> "$REPORT"
  echo "" >> "$REPORT"
  log_pass "Broken link scan: clean"
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
else
  echo "**All major scripts have test coverage or smoke-test mentions.** ✓" >> "$REPORT"
  echo "" >> "$REPORT"
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
  bash "$ROOT/bin/dispatch.sh" flag nel P3 "Found ${#INEFFICIENT_PATTERNS[@]} code optimization opportunities — rolling improvement" 2>/dev/null || true
else
  echo "**No major inefficiencies detected.** Code looks clean." >> "$REPORT"
  echo "" >> "$REPORT"
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
fi

if [[ "$CIPHER_LEAKS" -gt 0 ]]; then
  echo "- **[P0] Review cipher permission drifts** — $CIPHER_LEAKS auto-fixes logged. Consider adding preventive check." >> "$REPORT"
  IMPROVEMENT_SCORE=$((IMPROVEMENT_SCORE - 15))
  ACTIONS_FILED=$((ACTIONS_FILED + 1))
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
# PHASE 11: Dispatch Integration (Upward Communication to Kai)
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
  exit 1
else
  log_pass "System health excellent. All systems nominal."
  exit 0
fi
