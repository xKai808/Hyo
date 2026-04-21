#!/usr/bin/env bash
# agents/nel/dependency-audit.sh
#
# Dependency Vulnerability Scanner for the Hyo system
# Cross-references installed packages against known CVEs and vulnerability
# databases. Outputs structured JSONL to the nel ledger for downstream
# processing and alerting.
#
# Usage: ./agents/nel/dependency-audit.sh [--full] [--silent]
#   --full    : Run all checks including slow remote CVE lookups
#   --silent  : Suppress stdout, write only to ledger
#
# Integrates with nel.sh pipeline via ledger output.
# Output: agents/nel/ledger/dependency-audit.jsonl

set -uo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LEDGER_DIR="${REPO_ROOT}/agents/nel/ledger"
AUDIT_LOG="${LEDGER_DIR}/dependency-audit.jsonl"
TOOL_NAME="dependency-audit"
LOG_PREFIX="[nel-${TOOL_NAME}]"

# OSV API endpoint (Google's Open Source Vulnerability database — free, no key)
OSV_API="https://api.osv.dev/v1/query"

# PyPI advisory database (via pip audit or manual check)
# npm audit built-in
# Bundler audit for Ruby

FULL_SCAN=false
SILENT=false
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ─── Argument Parsing ─────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --full)   FULL_SCAN=true ;;
    --silent) SILENT=true ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

log() {
  # Log to stderr (always) and stdout (unless --silent)
  local msg="${LOG_PREFIX} $*"
  echo "${msg}" >&2
  if [[ "${SILENT}" == "false" ]]; then
    echo "${msg}"
  fi
}

# Emit a JSONL record to the audit log
emit_record() {
  local json="$1"
  echo "${json}" >> "${AUDIT_LOG}"
}

# Escape a string for safe JSON embedding (handles quotes, backslashes, newlines)
json_escape() {
  local input="$1"
  # Use python3 for reliable JSON string escaping
  python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "${input}" 2>/dev/null \
    || echo "\"${input//\"/\\\"}\""
}

# Build a minimal JSONL summary record
emit_summary() {
  local ecosystem="$1"
  local package="$2"
  local version="$3"
  local vuln_id="$4"
  local severity="$5"
  local description="$6"
  local source="$7"

  local esc_pkg esc_ver esc_desc
  esc_pkg="$(json_escape "${package}")"
  esc_ver="$(json_escape "${version}")"
  esc_desc="$(json_escape "${description}")"

  emit_record "{\"run_id\":\"${RUN_ID}\",\"timestamp\":\"${TIMESTAMP}\",\"tool\":\"${TOOL_NAME}\",\"ecosystem\":\"${ecosystem}\",\"package\":${esc_pkg},\"version\":${esc_ver},\"vuln_id\":\"${vuln_id}\",\"severity\":\"${severity}\",\"description\":${esc_desc},\"source\":\"${source}\"}"
}

# Emit a scan-status record (one per ecosystem scanned)
emit_status() {
  local ecosystem="$1"
  local status="$2"  # ok | warn | error | skipped
  local count="$3"   # number of vulns found
  local detail="$4"

  local esc_detail
  esc_detail="$(json_escape "${detail}")"

  emit_record "{\"run_id\":\"${RUN_ID}\",\"timestamp\":\"${TIMESTAMP}\",\"tool\":\"${TOOL_NAME}\",\"record_type\":\"scan_status\",\"ecosystem\":\"${ecosystem}\",\"status\":\"${status}\",\"vuln_count\":${count},\"detail\":${esc_detail}}"
}

# Check if a command exists
have() { command -v "$1" &>/dev/null; }

# ─── Setup ────────────────────────────────────────────────────────────────────

mkdir -p "${LEDGER_DIR}"

log "Starting dependency vulnerability audit (run_id=${RUN_ID})"
log "Repo root: ${REPO_ROOT}"
log "Full scan: ${FULL_SCAN}"
log "Output: ${AUDIT_LOG}"

# Emit a run-start record
emit_record "{\"run_id\":\"${RUN_ID}\",\"timestamp\":\"${TIMESTAMP}\",\"tool\":\"${TOOL_NAME}\",\"record_type\":\"run_start\",\"full_scan\":${FULL_SCAN},\"repo_root\":\"${REPO_ROOT}\"}"

TOTAL_VULNS=0

# ─── Python / pip audit ───────────────────────────────────────────────────────

audit_python() {
  log "Scanning Python dependencies..."

  # Collect all requirements files in the repo
  local req_files=()
  while IFS= read -r -d '' f; do
    req_files+=("$f")
  done < <(find "${REPO_ROOT}" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/venv/*" \
    -not -path "*/.venv/*" \
    -not -path "*/vendor/*" \
    \( -name "requirements*.txt" -o -name "Pipfile.lock" -o -name "pyproject.toml" \) \
    -print0 2>/dev/null)

  if [[ ${#req_files[@]} -eq 0 ]]; then
    log "No Python dependency files found — skipping Python audit"
    emit_status "python" "skipped" 0 "No requirements files found"
    return 0
  fi

  log "Found Python dependency files: ${req_files[*]}"

  local py_vuln_count=0

  # ── Method 1: pip-audit (preferred) ──────────────────────────────────────
  if have pip-audit; then
    log "Using pip-audit for Python CVE scanning"
    for req_file in "${req_files[@]}"; do
      local audit_out
      # pip-audit outputs JSON; capture and parse
      if audit_out="$(pip-audit --requirement "${req_file}" \
                                --format=json \
                                --no-deps \
                                --progress-spinner=off 2>/dev/null)"; then
        log "pip-audit completed cleanly for ${req_file}"
      else
        # pip-audit exits non-zero when vulnerabilities are found — that's OK
        log "pip-audit found issues in ${req_file} (exit non-zero is expected)"
      fi

      # Parse JSON output if we got something
      if [[ -n "${audit_out}" ]]; then
        local vuln_count
        vuln_count="$(echo "${audit_out}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
vulns = data.get('vulnerabilities', [])
count = 0
for v in vulns:
    pkg  = v.get('name', 'unknown')
    ver  = v.get('version', 'unknown')
    for a in v.get('aliases', [v.get('id','unknown')]):
        desc = '; '.join(f.get('description','') for f in v.get('fix_versions',[]) if 'description' in f)
        if not desc:
            desc = v.get('description', 'No description available')
        print(f'{pkg}|||{ver}|||{a}|||{desc}')
        count += 1
print(f'__COUNT__:{count}')
" 2>/dev/null || echo "__COUNT__:0")"

        while IFS= read -r line; do
          if [[ "${line}" == __COUNT__:* ]]; then
            local c="${line#__COUNT__:}"
            py_vuln_count=$((py_vuln_count + c))
          elif [[ "${line}" == *"|||"* ]]; then
            IFS='|||' read -r pkg ver vid desc <<< "${line}"
            emit_summary "python" "${pkg}" "${ver}" "${vid}" "unknown" "${desc}" "pip-audit/osv"
          fi
        done <<< "${vuln_count}"
      fi
    done
  # ── Method 2: safety (fallback) ──────────────────────────────────────────
  elif have safety; then
    log "pip-audit not found — falling back to safety"
    for req_file in "${req_files[@]}"; do
      local safety_out
      safety_out="$(safety check --file="${req_file}" --json 2>/dev/null || true)"
      if [[ -n "${safety_out}" ]]; then
        local parsed
        parsed="$(echo "${safety_out}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    vulns = data if isinstance(data, list) else data.get('vulnerabilities', [])
    count = 0
    for v in vulns:
        pkg  = v[0] if isinstance(v, list) else v.get('package_name','unknown')
        ver  = v[2] if isinstance(v, list) else v.get('analyzed_version','unknown')
        vid  = v[4] if isinstance(v, list) else v.get('vulnerability_id','unknown')
        desc = v[3] if isinstance(v, list) else v.get('advisory','')
        print(f'{pkg}|||{ver}|||{vid}|||{desc}')
        count += 1
    print(f'__COUNT__:{count}')
except Exception as e:
    print(f'__COUNT__:0')
" 2>/dev/null || echo "__COUNT__:0")"

        while IFS= read -r line; do
          if [[ "${line}" == __COUNT__:* ]]; then
            py_vuln_count=$((py_vuln_count + ${line#__COUNT__:}))
          elif [[ "${line}" == *"|||"* ]]; then
            IFS='|||' read -r pkg ver vid desc <<< "${line}"
            emit_summary "python" "${pkg}" "${ver}" "${vid}" "unknown" "${desc}" "safety"
          fi
        done <<< "${parsed}"
      fi
    done
  # ── Method 3: OSV direct query (last resort, only in --full mode) ─────────
  elif [[ "${FULL_SCAN}" == "true" ]] && have curl && have python3; then
    log "No pip-audit or safety found — using OSV direct API (slow)"
    for req_file in "${req_files[@]}"; do
      if [[ ! -f "${req_file}" ]]; then continue; fi
      # Only handle simple requirements.txt format
      if [[ "${req_file}" == *"requirements"*".txt" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
          # Strip comments and empty lines
          line="${line%%#*}"
          line="${line//[[:space:]]/}"
          [[ -z "${line}" ]] && continue
          # Parse package==version
          if [[ "${line}" =~ ^([A-Za-z0-9_.-]+)==([0-9A-Za-z._-]+)$ ]]; then
            local pkg="${BASH_REMATCH[1]}"
            local ver="${BASH_REMATCH[2]}"
            _query_osv "PyPI" "${pkg}" "${ver}"
          fi
        done < "${req_file}"
      fi
    done
  else
    log "No Python vulnerability scanner available (install pip-audit: pip install pip-audit)"
    emit_status "python" "skipped" 0 "No scanner available. Install: pip install pip-audit"
    return 0
  fi

  log "Python audit complete: ${py_vuln_count} vulnerabilities found"
  TOTAL_VULNS=$((TOTAL_VULNS + py_vuln_count))

  local status="ok"
  [[ ${py_vuln_count} -gt 0 ]] && status="warn"
  emit_status "python" "${status}" "${py_vuln_count}" "Scanned ${#req_files[@]} requirement file(s)"
}

# ─── Node.js / npm audit ──────────────────────────────────────────────────────

audit_nodejs() {
  log "Scanning Node.js dependencies..."

  # Find all package-lock.json or yarn.lock files (excluding node_modules)
  local pkg_files=()
  while IFS= read -r -d '' f; do
    pkg_files+=("$f")
  done < <(find "${REPO_ROOT}" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    \( -name "package-lock.json" -o -name "yarn.lock" \) \
    -print0 2>/dev/null)

  if [[ ${#pkg_files[@]} -eq 0 ]]; then
    log "No Node.js lock files found — skipping Node audit"
    emit_status "nodejs" "skipped" 0 "No package-lock.json or yarn.lock found"
    return 0
  fi

  if ! have npm; then
    log "npm not found — skipping Node.js audit"
    emit_status "nodejs" "skipped" 0 "npm not installed"
    return 0
  fi

  local node_vuln_count=0

  for lock_file in "${pkg_files[@]}"; do
    local pkg_dir
    pkg_dir="$(dirname "${lock_file}")"
    local lock_base
    lock_base="$(basename "${lock_file}")"

    log "Running npm audit in ${pkg_dir} (${lock_base})"

    local audit_out
    # npm audit --json exits non-zero when vulns found
    audit_out="$(cd "${pkg_dir}" && npm audit --json 2>/dev/null || true)"

    if [[ -z "${audit_out}" ]]; then
      log "npm audit returned no output for ${pkg_dir}"
      continue
    fi

    local parsed
    parsed="$(echo "${audit_out}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    vulns = data.get('vulnerabilities', {})
    count = 0
    for pkg_name, info in vulns.items():
        version = info.get('version', 'unknown')
        severity = info.get('severity', 'unknown')
        for via in info.get('via', []):
            if isinstance(via, dict):
                vid  = via.get('source', str(via.get('cwe', ['unknown']))).replace(' ','')
                url  = via.get('url', '')
                desc = via.get('title', via.get('name', 'No description'))
                print(f'{pkg_name}|||{version}|||{vid}|||{severity}|||{desc}')
                count += 1
                break
        else:
            print(f'{pkg_name}|||{version}|||unknown|||{severity}|||Vulnerability via transitive dependency')
            count += 1
    print(f'__COUNT__:{count}')
except Exception as e:
    print(f'__ERROR__:{e}')
    print('__COUNT__:0')
" 2>/dev/null || echo "__COUNT__:0")"

    while IFS= read -r line; do
      if [[ "${line}" == __COUNT__:* ]]; then
        node_vuln_count=$((node
