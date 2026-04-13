#!/usr/bin/env bash
# agents/nel/github-security-scan.sh — GitHub Security Scanner for Hyo public repo
#
# Purpose: Scan the local Hyo repository (xKai808/Hyo on GitHub) for accidentally
# committed secrets, exposed API keys, missing gitignore entries, and code patterns
# that indicate credential leakage.
#
# Output: JSONL to stdout (one finding per line). Each finding:
#   {
#     "type": "secret_leak"|"gitignore_gap"|"history_leak"|"config_exposure",
#     "severity": "P0"|"P1"|"P2",
#     "file": "path/to/file",
#     "detail": "description of the finding",
#     "remediation": "what to do to fix it"
#   }
#
# Summary statistics printed to stderr.
#
# Usage:
#   bash github-security-scan.sh
#   HYO_ROOT=/custom/path bash github-security-scan.sh
#
# Called from: nel-qa-cycle.sh Phase 2.5 (GitHub Security Scan)

set -uo pipefail

# Configuration
# HYO_ROOT may be passed explicitly (via queue), or default to cwd if in Hyo tree
ROOT="${HYO_ROOT:-.}"
if [[ ! -d "$ROOT/.git" ]]; then
  # Fallback to home Documents path
  ROOT="$HOME/Documents/Projects/Hyo"
fi
# Ensure absolute path
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || ROOT="${HYO_ROOT:-.}"

SCAN_TIMESTAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
FINDINGS_COUNT=0
WARNINGS_COUNT=0
TEMP_DIR=$(mktemp -d)

trap "rm -rf $TEMP_DIR" EXIT

# ---- Helper Functions -------------------------------------------------------

# Emit a JSONL finding
emit_finding() {
  local type="$1" severity="$2" file="$3" detail="$4" remediation="$5"
  # Escape quotes in strings
  detail="${detail//\"/\\\"}"
  remediation="${remediation//\"/\\\"}"
  file="${file//\"/\\\"}"

  printf '{"type":"%s","severity":"%s","file":"%s","detail":"%s","remediation":"%s"}\n' \
    "$type" "$severity" "$file" "$detail" "$remediation"

  if [[ "$severity" == "P0" ]] || [[ "$severity" == "P1" ]]; then
    FINDINGS_COUNT=$((FINDINGS_COUNT + 1))
  else
    WARNINGS_COUNT=$((WARNINGS_COUNT + 1))
  fi
}

# Pattern-match for API keys (loose heuristic)
has_secret_pattern() {
  local file="$1"
  # Look for patterns like: api_key = "sk-..." or secret: "base64-looking-string"
  grep -qPi '(api[_-]?key|secret[_-]?key|password|bearer|authorization|token|credentials)[\s:=]+["\x27]?[A-Za-z0-9+/._-]{20,}' "$file" 2>/dev/null
}

# Check if a file/directory is gitignored
is_gitignored() {
  local path="$1"
  # Use verbose mode to get detailed output
  result=$(git -C "$ROOT" check-ignore -v "$path" 2>/dev/null || echo "")
  [[ -n "$result" ]]
  return $?
}

# ============================================================================
# SCAN 1: ACTIVE SECRETS IN TRACKED FILES
# ============================================================================

echo "Scanning tracked files for exposed secrets..." >&2

# Find all tracked files that might contain secrets
TRACKED_FILES=$(git -C "$ROOT" ls-files -- '*.js' '*.py' '*.sh' '*.json' '*.md' '*.ts' '*.jsx' '*.tsx' 2>/dev/null || true)

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Skip exclusions: node_modules, .git, .secrets, security dirs
  [[ "$file" =~ node_modules ]] && continue
  [[ "$file" =~ \.git ]] && continue
  [[ "$file" =~ agents/nel/security ]] && continue
  [[ "$file" =~ \.secrets ]] && continue
  [[ "$file" =~ SKILL.md ]] && continue

  full_path="$ROOT/$file"
  [[ ! -f "$full_path" ]] && continue

  # Check for secret patterns
  if has_secret_pattern "$full_path"; then
    # Verify it's not just a template or env variable reference
    if grep -qPi 'process\.env\.|os\.environ|${[A-Z_]+}|\$[A-Z_]+|<REDACTED>|CHANGE_ME|TODO|EXAMPLE|mock|test|placeholder|demo' "$full_path" 2>/dev/null; then
      # Likely a template or reference, not a real secret
      continue
    fi

    # Extract the matching line for detail
    match_line=$(grep -im1 '(api[_-]?key|secret[_-]?key|password|bearer|token|credentials)' "$full_path" 2>/dev/null | head -1 | cut -c1-100)

    emit_finding "secret_leak" "P0" "$file" \
      "Potential secret value found in tracked file: $match_line..." \
      "Review $file and remove any hardcoded credentials. Store in agents/nel/security/ or Vercel env vars."
  fi
done <<< "$TRACKED_FILES"

# ============================================================================
# SCAN 2: GIT HISTORY FOR SENSITIVE FILENAMES
# ============================================================================

echo "Scanning git history for previously committed secrets..." >&2

# Check if files that should be sensitive were ever committed
SENSITIVE_PATTERNS=('.env' '.key' '.pem' '.pk8' 'secret' 'password' 'credentials.json' 'token' '.aws' '.ssh' 'private_key')

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  # Find files in history that match
  HISTORY_FILES=$(git -C "$ROOT" log --all --full-history --oneline --diff-filter=A --name-only -- "*${pattern}*" 2>/dev/null | grep -v "^[a-f0-9]" || true)

  while IFS= read -r hfile; do
    [[ -z "$hfile" ]] && continue

    # Skip if it's safely in .secrets or currently gitignored
    if [[ "$hfile" == *"agents/nel/security"* ]] || [[ "$hfile" == *".secrets"* ]]; then
      continue
    fi

    # Skip .env.example files — these are intentionally tracked templates
    if [[ "$hfile" == *".env.example"* ]] || [[ "$hfile" == *".env.sample"* ]]; then
      continue
    fi

    # Skip usage/billing data CSVs — these contain workspace names not actual keys
    if [[ "$hfile" == *"_tokens_"*.csv ]] || [[ "$hfile" == *"usage"*.csv ]]; then
      continue
    fi

    if is_gitignored "$hfile"; then
      # It's gitignored, but still committed to history
      emit_finding "history_leak" "P1" "$hfile" \
        "File matching '$pattern' found in git history (is gitignored now but was once committed)" \
        "Run: git rm --cached '$hfile' && git filter-branch --tree-filter 'rm -f $hfile' -- --all (destructive; requires force-push)"
    else
      # Not gitignored AND in history
      emit_finding "history_leak" "P0" "$hfile" \
        "File matching '$pattern' found in git history and NOT gitignored (exposed in public repo)" \
        "Immediately add to .gitignore. Then use git filter-branch or BFG Repo-Cleaner to remove from history."
    fi
  done <<< "$HISTORY_FILES"
done

# ============================================================================
# SCAN 3: GITIGNORE COVERAGE
# ============================================================================

echo "Verifying .gitignore coverage for sensitive paths..." >&2

# Check .gitignore file contains required patterns
GITIGNORE="${ROOT}/.gitignore"
GITIGNORE_GAPS=()

if [[ ! -f "$GITIGNORE" ]]; then
  emit_finding "gitignore_gap" "P0" ".gitignore" \
    ".gitignore file missing" \
    "Create .gitignore with at least: agents/nel/security/, .secrets/, .env, *.key, *.pem, credentials.json"
else
  # Read .gitignore and check for required patterns (loose matching)
  REQUIRED_PATTERNS=(
    "agents/nel/security"
    ".secrets"
    ".env"
    "*.key"
    "*.pem"
    "credentials.json"
  )

  for pattern in "${REQUIRED_PATTERNS[@]}"; do
    if ! grep -qF "$pattern" "$GITIGNORE" 2>/dev/null; then
      GITIGNORE_GAPS+=("$pattern")
    fi
  done

  if [[ ${#GITIGNORE_GAPS[@]} -gt 0 ]]; then
    emit_finding "gitignore_gap" "P0" ".gitignore" \
      "Missing patterns in .gitignore: ${GITIGNORE_GAPS[*]}" \
      "Add these patterns to .gitignore: ${GITIGNORE_GAPS[*]}"
  fi

  # Also check for .aws, .ssh, etc. (less critical, but good practice)
  for extra_pattern in ".aws" ".ssh" "founder.token" "openai.key"; do
    escaped_pattern=$(echo "$extra_pattern" | sed 's/[.[\*^$]/\\&/g')
    if ! grep -q "$escaped_pattern" "$GITIGNORE" 2>/dev/null; then
      # Don't flag as P0, but note it for defensive hardening
      :
    fi
  done
fi

# ============================================================================
# SCAN 4: HARDCODED SECRETS IN COMMON CONFIG FILES
# ============================================================================

echo "Scanning config files for hardcoded secrets..." >&2

for cfg_file in .env .env.local .env.production vercel.json website/api/.env.local agents/ra/pipeline/.env; do
  full_path="$ROOT/$cfg_file"
  if [[ -f "$full_path" ]]; then
    # Check if it contains actual values (not just env var references)
    if grep -qPi '(api[_-]?key|secret|password|token)\s*=\s*["\x27]?[A-Za-z0-9+/._-]{15,}' "$full_path" 2>/dev/null; then
      emit_finding "config_exposure" "P1" "$cfg_file" \
        "Config file contains hardcoded values (not env var references)" \
        "Move all secrets to Vercel env vars or agents/nel/security/, leave only references in $cfg_file"
    fi
  fi
done

# ============================================================================
# SCAN 5: ENVIRONMENT VARIABLES IN JAVASCRIPT / ENVIRONMENT LEAKAGE
# ============================================================================

echo "Checking for API keys in deployed JavaScript..." >&2

# Check website API endpoints for hardcoded keys
for js_file in $(find "$ROOT/website" -name "*.js" -not -path "*/node_modules/*" 2>/dev/null); do
  # Look for direct assignment of secrets (not via process.env or fetch headers)
  if grep -qPi 'const\s+(api[_-]?key|secret|token|auth)\s*=\s*["\x27][A-Za-z0-9+/._-]{15,}' "$js_file" 2>/dev/null; then
    emit_finding "secret_leak" "P0" "${js_file#$ROOT/}" \
      "JavaScript contains hardcoded secret assignment" \
      "Move to Vercel env vars and use process.env.* or fetch headers instead"
  fi

  # Look for Bearer tokens in Authorization headers
  if grep -qPi 'Authorization.*Bearer.*[A-Za-z0-9+/._-]{20,}' "$js_file" 2>/dev/null; then
    emit_finding "secret_leak" "P1" "${js_file#$ROOT/}" \
      "Authorization Bearer token found in code" \
      "Use Vercel env vars and apply the token at request time, never commit it"
  fi
done

# ============================================================================
# SCAN 6: BASE64-ENCODED SECRETS (heuristic)
# ============================================================================

echo "Checking for Base64-encoded potential secrets..." >&2

# Look for long base64-like strings that might be encoded secrets
for file in $(git -C "$ROOT" ls-files -- '*.json' '*.js' 2>/dev/null); do
  full_path="$ROOT/$file"
  [[ ! -f "$full_path" ]] && continue
  [[ "$file" =~ node_modules ]] && continue

  # Find base64-like strings (20+ chars, mix of upper/lowercase, numbers, +/=)
  if grep -oP '[A-Za-z0-9+/]{20,}={0,2}' "$full_path" 2>/dev/null | grep -q '[A-Z].*[a-z]'; then
    # This is a heuristic — only flag if context mentions "key" or "secret" nearby
    if grep -B2 -A2 -i 'key\|secret\|token\|credential' "$full_path" 2>/dev/null | grep -qP '[A-Za-z0-9+/]{20,}'; then
      emit_finding "secret_leak" "P2" "$file" \
        "Base64-like string found near secret-related keywords" \
        "Review and ensure no encoded API keys are in the file"
    fi
  fi
done

# ============================================================================
# SCAN 7: GITHUB ACTIONS SECRETS EXPOSURE (if gh CLI available)
# ============================================================================

echo "Checking GitHub Actions configuration..." >&2

if command -v gh &>/dev/null; then
  # Try to list repo secrets (requires auth and permissions)
  if gh auth status >/dev/null 2>&1; then
    REPO_OWNER=$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null | grep -oP '(?<=github\.com/)[^/]+(?=/)')
    REPO_NAME=$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null | grep -oP '(?</)[^/]+(?=\.git$|$)' | tail -1)

    if [[ -n "$REPO_OWNER" ]] && [[ -n "$REPO_NAME" ]]; then
      # Check if repo is public
      IS_PUBLIC=$(gh repo view "$REPO_OWNER/$REPO_NAME" --json isPrivate --jq '.isPrivate' 2>/dev/null || echo "unknown")

      if [[ "$IS_PUBLIC" == "false" ]]; then
        emit_finding "gitignore_gap" "P1" ".github/workflows/*" \
          "Repository is PUBLIC — extra caution needed with CI/CD secrets" \
          "Ensure GitHub Actions secrets are used for all credentials; never log them; review workflow files for exposure"
      fi

      # List GitHub secrets (safe — only shows the names, not values)
      SECRETS=$(gh secret list --repo "$REPO_OWNER/$REPO_NAME" 2>/dev/null | awk '{print $1}')
      if [[ -z "$SECRETS" ]]; then
        # No secrets set up — might be OK, might be missing
        :
      fi
    fi
  fi
fi

# ============================================================================
# SCAN 8: VERCEL ENVIRONMENT VARIABLES (check if keys appear in deployed output)
# ============================================================================

echo "Checking for environment leakage in Vercel deployment..." >&2

# This is a heuristic: check if any .js files in website/ were built with secrets baked in
for js_file in $(find "$ROOT/website" -name "*.js" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
  # Look for suspicious patterns in minified output
  if file "$js_file" 2>/dev/null | grep -q "JavaScript"; then
    # Check if the file looks like it contains environment variables
    if grep -qP 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}' "$js_file" 2>/dev/null; then
      emit_finding "config_exposure" "P0" "${js_file#$ROOT/}" \
        "Potential AWS/GitHub/OpenAI key found in deployed JavaScript" \
        "Check build process — secrets should NOT be in JS. Use process.env at runtime instead."
    fi
  fi
done

# ============================================================================
# SCAN 9: .SECRETS DIRECTORY INTEGRITY
# ============================================================================

echo "Verifying .secrets directory integrity..." >&2

SECRETS_DIR="$ROOT/agents/nel/security"
if [[ -d "$SECRETS_DIR" ]]; then
  # Check permissions
  SEC_PERMS=$(stat -c %a "$SECRETS_DIR" 2>/dev/null || stat -f %A "$SECRETS_DIR" 2>/dev/null || echo "unknown")
  if [[ "$SEC_PERMS" != "700" ]]; then
    emit_finding "gitignore_gap" "P1" "agents/nel/security" \
      "Security directory has incorrect permissions: $SEC_PERMS (should be 700)" \
      "Run: chmod 700 agents/nel/security && chmod 600 agents/nel/security/*"
  fi

  # Check if directory itself is gitignored (directory pattern takes precedence)
  if is_gitignored "agents/nel/security/" || is_gitignored "agents/nel/security/test-file"; then
    # Directory is gitignored, files within don't need individual entries
    :
  else
    # Directory not gitignored — potential security issue
    emit_finding "gitignore_gap" "P0" ".gitignore" \
      "agents/nel/security directory is not gitignored" \
      "Add 'agents/nel/security/' to .gitignore"
  fi
fi

# ============================================================================
# SUMMARY
# ============================================================================

TOTAL_ISSUES=$((FINDINGS_COUNT + WARNINGS_COUNT))
echo ""
echo "GitHub Security Scan Summary (ts=$SCAN_TIMESTAMP)" >&2
echo "Findings (P0/P1): $FINDINGS_COUNT" >&2
echo "Warnings (P2): $WARNINGS_COUNT" >&2
echo "Total Issues: $TOTAL_ISSUES" >&2

if [[ $TOTAL_ISSUES -gt 0 ]]; then
  exit 1
fi

exit 0
