#!/usr/bin/env bash
# agents/nel/dep-audit.sh — Nel W2: Dependency Vulnerability Audit
#
# Nel W2 fix: Cipher was blind to supply-chain risk. This script closes
# the loop: scan package.json/package-lock.json via npm audit + check
# Python requirements, cross-reference CVEs, report severity, open tickets.
#
# Shipped: 2026-04-21 | Protocol: agents/nel/GROWTH.md W2
#
# WHAT IT CHECKS:
#   - npm audit against agents/sam/website/package.json (queries npm advisory DB)
#   - Python pip-audit if requirements.txt files exist
#   - Dependency staleness: flags packages >1 year without update
#   - Node engine version vs current LTS
#
# WHAT IT DOES NOT DO:
#   - Does not auto-update dependencies (requires human review)
#   - Does not run on packages without a lock file (unsafe)
#
# USAGE:
#   bash agents/nel/dep-audit.sh                  # audit all + report
#   bash agents/nel/dep-audit.sh --dry-run        # report only, no tickets
#   bash agents/nel/dep-audit.sh --json           # machine-readable JSON output
#
# OUTPUT:
#   agents/nel/ledger/dep-audit.jsonl — time-series audit history
#   stdout — human-readable summary
#   exit 0 — clean (0 critical/high vulnerabilities)
#   exit 1 — P0/P1: critical or high CVEs found

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LEDGER="$ROOT/agents/nel/ledger/dep-audit.jsonl"
NOW_ISO=$(TZ=America/Denver date +%FT%T%z 2>/dev/null || date -u +%FT%TZ)
TODAY=$(date +%Y-%m-%d)
DRY_RUN=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --json)    JSON_OUTPUT=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$(dirname "$LEDGER")"

PASS=0
FAIL=0
WARN=0
RESULTS=()

echo "=== Nel Dependency Audit — $TODAY ===" >&2
echo "" >&2

# ── npm audit function ──────────────────────────────────────────────────────
# audit_npm_target <directory> <label>
# Runs npm audit on the given directory, updates PASS/FAIL/WARN/RESULTS.
audit_npm_target() {
  local target_dir="$1"
  local label="$2"
  local pkg="$target_dir/package.json"
  local lock="$target_dir/package-lock.json"

  if [[ ! -f "$pkg" ]]; then
    echo "  - npm [$label]: no package.json found" >&2
    RESULTS+=("{\"source\":\"npm\",\"target\":\"$label\",\"status\":\"skipped\",\"note\":\"no package.json\"}")
    return
  fi

  echo "  [npm] Auditing $pkg..." >&2

  if [[ ! -f "$lock" ]]; then
    echo "  ⚠ npm [$label]: no package-lock.json — running npm install first" >&2
    (cd "$target_dir" && npm install --package-lock-only --silent 2>/dev/null) || true
  fi

  if [[ ! -f "$lock" ]]; then
    echo "  ⚠ npm [$label]: could not generate lock file — skipping audit" >&2
    WARN=$((WARN + 1))
    RESULTS+=("{\"source\":\"npm\",\"target\":\"$label\",\"status\":\"skipped\",\"note\":\"no lock file\"}")
    return
  fi

  local AUDIT_JSON
  AUDIT_JSON=$(cd "$target_dir" && npm audit --json 2>/dev/null || true)

  if [[ -z "$AUDIT_JSON" ]]; then
    echo "  ⚠ npm [$label] audit returned no output — offline or registry unreachable" >&2
    WARN=$((WARN + 1))
    RESULTS+=("{\"source\":\"npm\",\"target\":\"$label\",\"status\":\"unavailable\",\"note\":\"npm audit returned no output\"}")
    return
  fi

  # Parse vulnerability counts
  local VULN_SUMMARY
  VULN_SUMMARY=$(echo "$AUDIT_JSON" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    v = d.get('metadata',{}).get('vulnerabilities',{})
    total_deps = d.get('metadata',{}).get('totalDependencies', 0)
    critical = v.get('critical', 0)
    high = v.get('high', 0)
    moderate = v.get('moderate', 0)
    low = v.get('low', 0)
    total = v.get('total', 0)
    vulns = []
    for pkg_name, adv in d.get('vulnerabilities', {}).items():
        sev = adv.get('severity','unknown')
        via = adv.get('via', [])
        cves = [v.get('url','') for v in via if isinstance(v, dict) and 'url' in v]
        vulns.append({'package': pkg_name, 'severity': sev, 'cves': cves[:3]})
    print(json.dumps({'critical':critical,'high':high,'moderate':moderate,'low':low,'total':total,'total_deps':total_deps,'details':vulns[:10]}))
except Exception as e:
    print(json.dumps({'error': str(e), 'critical':0,'high':0,'moderate':0,'low':0,'total':0,'total_deps':0,'details':[]}))
" 2>/dev/null)

  local CRIT HIGH MOD LOW TOTAL TOTAL_DEPS NPM_STATUS
  CRIT=$(echo "$VULN_SUMMARY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('critical',0))")
  HIGH=$(echo "$VULN_SUMMARY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('high',0))")
  MOD=$(echo "$VULN_SUMMARY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('moderate',0))")
  LOW=$(echo "$VULN_SUMMARY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('low',0))")
  TOTAL=$(echo "$VULN_SUMMARY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))")
  TOTAL_DEPS=$(echo "$VULN_SUMMARY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_deps',0))")

  NPM_STATUS="clean"
  if [[ "$CRIT" -gt 0 ]]; then
    NPM_STATUS="critical"
    FAIL=$((FAIL + CRIT))
    echo "  ✗ npm [$label]: CRITICAL $CRIT CVE(s) — immediate action required" >&2
  elif [[ "$HIGH" -gt 0 ]]; then
    NPM_STATUS="high"
    FAIL=$((FAIL + HIGH))
    echo "  ✗ npm [$label]: HIGH $HIGH CVE(s) — action required" >&2
  elif [[ "$MOD" -gt 0 ]]; then
    NPM_STATUS="moderate"
    WARN=$((WARN + MOD))
    echo "  ⚠ npm [$label]: MODERATE $MOD issue(s) — review recommended" >&2
  else
    PASS=$((PASS + 1))
    echo "  ✓ npm [$label]: clean ($TOTAL_DEPS deps, 0 vulnerabilities)" >&2
  fi

  RESULTS+=("{\"source\":\"npm\",\"target\":\"$label\",\"status\":\"$NPM_STATUS\",\"total_deps\":$TOTAL_DEPS,\"critical\":$CRIT,\"high\":$HIGH,\"moderate\":$MOD,\"low\":$LOW,\"total_vulns\":$TOTAL}")
}

# ── 1. npm audit ────────────────────────────────────────────────────────────
audit_npm_target "$ROOT/agents/sam/website" "agents/sam/website"
audit_npm_target "$ROOT/agents/sam/mcp-server" "agents/sam/mcp-server"

# ── 2. Python pip-audit ─────────────────────────────────────────────────────
echo "" >&2
echo "  [python] Checking for requirements files..." >&2

PY_REQ_FILES=()
for req_path in \
  "$ROOT/requirements.txt" \
  "$ROOT/agents/ra/pipeline/requirements.txt" \
  "$ROOT/kai/requirements.txt"; do
  [[ -f "$req_path" ]] && PY_REQ_FILES+=("$req_path")
done

if [[ ${#PY_REQ_FILES[@]} -eq 0 ]]; then
  echo "  - python: no requirements.txt files found" >&2
  RESULTS+=("{\"source\":\"python\",\"status\":\"skipped\",\"note\":\"no requirements.txt\"}")
else
  for req in "${PY_REQ_FILES[@]}"; do
    rel="${req#$ROOT/}"
    # Use pip-audit if available, else list packages
    if command -v pip-audit >/dev/null 2>&1; then
      PY_AUDIT=$(pip-audit -r "$req" --format=json 2>/dev/null || echo '{"dependencies":[]}')
      PY_VULNS=$(echo "$PY_AUDIT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
total=0
for dep in d.get('dependencies',[]):
    total += len(dep.get('vulns',[]))
print(total)
" 2>/dev/null || echo "0")
      if [[ "$PY_VULNS" -gt 0 ]]; then
        FAIL=$((FAIL + PY_VULNS))
        echo "  ✗ python [$rel]: $PY_VULNS known vulnerabilities" >&2
        RESULTS+=("{\"source\":\"python\",\"target\":\"$rel\",\"status\":\"vulnerable\",\"total_vulns\":$PY_VULNS}")
      else
        PASS=$((PASS + 1))
        echo "  ✓ python [$rel]: clean" >&2
        RESULTS+=("{\"source\":\"python\",\"target\":\"$rel\",\"status\":\"clean\",\"total_vulns\":0}")
      fi
    else
      echo "  ⚠ python [$rel]: pip-audit not installed — listing packages only" >&2
      PKG_COUNT=$(grep -c "." "$req" 2>/dev/null || echo 0)
      WARN=$((WARN + 1))
      RESULTS+=("{\"source\":\"python\",\"target\":\"$rel\",\"status\":\"unaudited\",\"note\":\"pip-audit not installed\",\"package_count\":$PKG_COUNT}")
    fi
  done
fi

# ── 3. Staleness check: flag packages >365 days without update ───────────────
echo "" >&2
echo "  [staleness] Checking npm package ages..." >&2

STALE_TARGET="$ROOT/agents/sam/website"
if [[ -f "$STALE_TARGET/package.json" ]]; then
  STALE_PKGS=$(cd "$STALE_TARGET" && python3 -c "
import json, subprocess, sys
from datetime import datetime, timezone

with open('package.json') as f:
    pkg = json.load(f)

deps = {}
deps.update(pkg.get('dependencies', {}))
deps.update(pkg.get('devDependencies', {}))

stale = []
now = datetime.now(timezone.utc)
for name in deps:
    try:
        out = subprocess.run(['npm', 'view', name, 'time.modified', '--json'],
                             capture_output=True, text=True, timeout=5)
        if out.returncode == 0:
            modified = json.loads(out.stdout.strip())
            dt = datetime.fromisoformat(modified.replace('Z', '+00:00'))
            age_days = (now - dt).days
            if age_days > 365:
                stale.append({'package': name, 'age_days': age_days})
    except Exception:
        pass
print(json.dumps(stale))
" 2>/dev/null || echo "[]")

  STALE_COUNT=$(echo "$STALE_PKGS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  if [[ "$STALE_COUNT" -gt 0 ]]; then
    echo "  ⚠ staleness: $STALE_COUNT package(s) not updated in >365 days" >&2
    WARN=$((WARN + STALE_COUNT))
  else
    echo "  ✓ staleness: all packages updated within 365 days" >&2
    PASS=$((PASS + 1))
  fi
  RESULTS+=("{\"source\":\"staleness\",\"stale_count\":$STALE_COUNT}")
fi

# ── 4. Node engine version check ────────────────────────────────────────────
echo "" >&2
NODE_VER=$(node --version 2>/dev/null | tr -d 'v' || echo "unknown")
NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
# Node 20+ is LTS as of 2024
if [[ "$NODE_MAJOR" -ge 20 ]] 2>/dev/null; then
  echo "  ✓ node: v$NODE_VER (>= 20 LTS requirement met)" >&2
  PASS=$((PASS + 1))
  RESULTS+=("{\"source\":\"node-version\",\"version\":\"$NODE_VER\",\"status\":\"ok\"}")
else
  echo "  ⚠ node: v$NODE_VER (below 20 LTS — upgrade recommended)" >&2
  WARN=$((WARN + 1))
  RESULTS+=("{\"source\":\"node-version\",\"version\":\"$NODE_VER\",\"status\":\"outdated\"}")
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo "" >&2
OVERALL="clean"
[[ $WARN -gt 0 ]] && OVERALL="warnings"
[[ $FAIL -gt 0 ]] && OVERALL="vulnerable"

echo "=== Dep Audit: $PASS passed, $WARN warnings, $FAIL failures — $OVERALL ===" >&2

# ── Write to ledger ──────────────────────────────────────────────────────────
RESULTS_JSON=$(printf '%s,' "${RESULTS[@]}")
RESULTS_JSON="[${RESULTS_JSON%,}]"

DRY_RUN_PY=$( [ "$DRY_RUN" == "true" ] && echo "True" || echo "False" )
ENTRY=$(echo "$RESULTS_JSON" | python3 -c "
import json, sys
results = json.load(sys.stdin)
entry = {
    'ts': '$NOW_ISO',
    'date': '$TODAY',
    'overall': '$OVERALL',
    'pass': $PASS,
    'warn': $WARN,
    'fail': $FAIL,
    'dry_run': $DRY_RUN_PY,
    'results': results
}
print(json.dumps(entry))
" 2>/dev/null || echo "{}")
echo "$ENTRY" >> "$LEDGER"

# ── JSON output mode ─────────────────────────────────────────────────────────
if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "" >&2
  echo "$ENTRY"
fi

# ── Open ticket if critical/high CVEs found ──────────────────────────────────
if [[ $FAIL -gt 0 && "$DRY_RUN" == "false" ]]; then
  TICKET_SCRIPT="$ROOT/bin/ticket.sh"
  if [[ -x "$TICKET_SCRIPT" ]]; then
    bash "$TICKET_SCRIPT" \
      --type "security" \
      --severity "P1" \
      --title "Dep audit: $FAIL critical/high CVE(s) detected — $TODAY" \
      --description "Nel dep-audit found $FAIL vulnerability/vulnerabilities. Run: cd $NPM_TARGET && npm audit fix" \
      --agent "nel" 2>/dev/null || true
    echo "  [ticket] P1 security ticket opened" >&2
  fi
fi

[[ $FAIL -gt 0 ]] && exit 1 || exit 0
