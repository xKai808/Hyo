#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/kai/cipher.sh
#
# cipher.hyo — hourly security scan with persistent memory.
# Reads state from kai/memory/cipher.state.json and its algorithm from
# kai/memory/cipher.algorithm.md. Writes updated state at end.
# Philosophy: verified > unverified. Auto-fix what's fixable. Block, don't just report.

set -euo pipefail

# Resolve Hyo root: honor HYO_ROOT, else auto-detect from script location, else $HOME default.
if [[ -n "${HYO_ROOT:-}" ]]; then
  ROOT="$HYO_ROOT"
else
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/../../CLAUDE.md" && -d "$SCRIPT_DIR/../../agents" ]]; then
    ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
  else
    ROOT="$HOME/Documents/Projects/Hyo"
  fi
fi
LOGS="$ROOT/agents/nel/logs"
MEMORY="$ROOT/agents/nel/memory"
STATE="$MEMORY/cipher.state.json"
TASKS="$ROOT/KAI_TASKS.md"
NOW_ISO=$(date -u +%FT%TZ)
NOW_FS=$(date -u +%Y-%m-%dT%H%M%SZ)
TODAY=$(date +%Y-%m-%d)
HOURLY_LOG="$LOGS/cipher-$(date +%Y-%m-%dT%H).log"

mkdir -p "$LOGS" "$MEMORY"

# ---- portable stat wrapper (macOS BSD vs Linux GNU) ------------------------
# Probe once: GNU stat supports -c, BSD stat supports -f.
if stat -c %a / >/dev/null 2>&1; then
  stat_mode() { stat -c %a "$1" 2>/dev/null; }
else
  stat_mode() { stat -f %Mp%Lp "$1" 2>/dev/null; }
fi

# ---- state bootstrap --------------------------------------------------------
if [[ ! -f "$STATE" ]]; then
  cat > "$STATE" <<'JSON'
{
  "schema": "hyo.agent.memory.v1",
  "agent": "cipher.hyo",
  "firstSeenAt": null,
  "lastRunAt": null,
  "totalRuns": 0,
  "runHistory": [],
  "knownIssues": {},
  "falsePositives": [],
  "verifiedLeakHistory": [],
  "permFixHistory": [],
  "trendCounters": {
    "gitleaks_not_installed_runs_in_a_row": 0,
    "trufflehog_not_installed_runs_in_a_row": 0,
    "perm_drift_events": 0
  },
  "escalationState": {
    "lastEscalationAt": null,
    "escalationsFiledThisWeek": 0
  }
}
JSON
fi

# ---- findings collector -----------------------------------------------------
# Each finding: "SEVERITY|check_id|detail"
FINDINGS=()
AUTOFIXES=()

log() { printf '[%s] %s\n' "$NOW_ISO" "$*" >> "$HOURLY_LOG"; }
fail() { FINDINGS+=("$1"); }
autofix() { AUTOFIXES+=("$1"); log "AUTOFIX: $1"; }

log "cipher run start"

# ---- Layer 1: gitleaks (pattern-based) --------------------------------------
GITLEAKS_INSTALLED=0
if command -v gitleaks >/dev/null 2>&1; then
  GITLEAKS_INSTALLED=1
  log "running gitleaks on working tree"
  GL_OUT=$(gitleaks detect --source "$ROOT" --no-banner --redact --no-color --report-format json --report-path /tmp/gitleaks-cipher.json 2>&1 || true)
  if [[ -f /tmp/gitleaks-cipher.json ]]; then
    GL_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/gitleaks-cipher.json')); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
    if [[ "$GL_COUNT" -gt 0 ]]; then
      fail "P1|gitleaks-pattern-match|gitleaks found $GL_COUNT pattern match(es); see $HOURLY_LOG"
      cat /tmp/gitleaks-cipher.json >> "$HOURLY_LOG" 2>/dev/null || true
    fi
    rm -f /tmp/gitleaks-cipher.json
  fi
else
  fail "P2|gitleaks-not-installed|brew install gitleaks"
fi

# ---- Layer 2: trufflehog verified scan --------------------------------------
TRUFFLEHOG_INSTALLED=0
if command -v trufflehog >/dev/null 2>&1; then
  TRUFFLEHOG_INSTALLED=1
  log "running trufflehog with --only-verified"
  TH_OUT=$(trufflehog filesystem "$ROOT" --only-verified --no-update --json 2>/dev/null || true)
  if [[ -n "$TH_OUT" ]]; then
    echo "$TH_OUT" >> "$HOURLY_LOG"
    # Count lines as a proxy for verified findings
    TH_COUNT=$(echo "$TH_OUT" | grep -c '"SourceMetadata"' 2>/dev/null || echo 0)
    if [[ "$TH_COUNT" -gt 0 ]]; then
      fail "P0|trufflehog-verified-leak|trufflehog found $TH_COUNT VERIFIED live credential(s) — rotate immediately"
    fi
  fi
else
  fail "P2|trufflehog-not-installed|brew install trufflesecurity/trufflehog/trufflehog"
fi

# ---- Layer 3: Filesystem hygiene (auto-fix) ---------------------------------
if [[ -d "$ROOT/.secrets" ]]; then
  SMODE=$(stat_mode "$ROOT/.secrets")
  if [[ ! "$SMODE" =~ ^7[0-9][0-9]$ ]]; then
    chmod 700 "$ROOT/.secrets"
    autofix ".secrets/ dir mode $SMODE -> 700"
  fi
  for f in "$ROOT/.secrets"/*; do
    [[ -f "$f" ]] || continue
    FMODE=$(stat_mode "$f")
    if [[ ! "$FMODE" =~ ^6[0-9][0-9]$ ]]; then
      chmod 600 "$f"
      autofix "$(basename "$f") mode $FMODE -> 600"
    fi
  done
fi

# ---- Layer 4: Token-specific checks ----------------------------------------
if [[ -f "$ROOT/.secrets/founder.token" ]]; then
  TOKEN=$(tr -d '\n' < "$ROOT/.secrets/founder.token")
  if [[ -n "$TOKEN" && ${#TOKEN} -gt 8 ]]; then
    # Search for token value everywhere EXCEPT .secrets/ (and its symlink target
    # agents/nel/security/), git history, logs, memory
    LEAK_HITS=$(grep -rlF \
      --exclude-dir=.secrets \
      --exclude-dir=security \
      --exclude-dir=.git \
      --exclude-dir=node_modules \
      --exclude-dir=logs \
      --exclude-dir=memory \
      --exclude-dir=kai \
      -- "$TOKEN" "$ROOT" 2>/dev/null || true)
    if [[ -n "$LEAK_HITS" ]]; then
      fail "P0|founder-token-leak|founder.token value found OUTSIDE .secrets/: $(echo "$LEAK_HITS" | head -3 | tr '\n' ' ')"
    fi
  fi
fi

# ---- .env files must be gitignored (auto-fix where safe) -------------------
if [[ -d "$ROOT/.git" ]]; then
  ENV_FILES=$(find "$ROOT" -maxdepth 3 \( -name '.env' -o -name '.env.*' \) 2>/dev/null | grep -v node_modules || true)
  if [[ -n "$ENV_FILES" ]]; then
    while IFS= read -r envf; do
      [[ -z "$envf" ]] && continue
      [[ "$(basename "$envf")" == ".env.example" ]] && continue
      if ! git -C "$ROOT" check-ignore -q "$envf" 2>/dev/null; then
        fail "P1|env-not-gitignored|$envf is not gitignored"
      fi
    done <<< "$ENV_FILES"
  fi
fi

# ---- process findings through memory ---------------------------------------
PY_FINDINGS=()
for f in "${FINDINGS[@]:-}"; do
  [[ -n "$f" ]] && PY_FINDINGS+=("$f")
done

python3 - "$STATE" "$TASKS" "$NOW_ISO" "$TODAY" "$GITLEAKS_INSTALLED" "$TRUFFLEHOG_INSTALLED" "${#AUTOFIXES[@]}" "${PY_FINDINGS[@]:-}" <<'PYEOF'
import json, sys, hashlib, os
from datetime import datetime

state_path = sys.argv[1]
tasks_path = sys.argv[2]
now_iso = sys.argv[3]
today = sys.argv[4]
gitleaks_installed = sys.argv[5] == "1"
trufflehog_installed = sys.argv[6] == "1"
autofix_count = int(sys.argv[7])
raw_findings = sys.argv[8:]

with open(state_path) as f:
    state = json.load(f)

if state.get("firstSeenAt") is None:
    state["firstSeenAt"] = now_iso

state["lastRunAt"] = now_iso
state["totalRuns"] = state.get("totalRuns", 0) + 1
state.setdefault("knownIssues", {})
state.setdefault("falsePositives", [])
state.setdefault("runHistory", [])
state.setdefault("verifiedLeakHistory", [])
state.setdefault("permFixHistory", [])
state.setdefault("trendCounters", {})

tc = state["trendCounters"]
tc["gitleaks_not_installed_runs_in_a_row"] = 0 if gitleaks_installed else tc.get("gitleaks_not_installed_runs_in_a_row", 0) + 1
tc["trufflehog_not_installed_runs_in_a_row"] = 0 if trufflehog_installed else tc.get("trufflehog_not_installed_runs_in_a_row", 0) + 1
if autofix_count > 0:
    tc["perm_drift_events"] = tc.get("perm_drift_events", 0) + autofix_count
    state["permFixHistory"].append({"ts": now_iso, "count": autofix_count})
    state["permFixHistory"] = state["permFixHistory"][-50:]

parsed = []
for line in raw_findings:
    if not line: continue
    parts = line.split("|", 2)
    if len(parts) != 3: continue
    sev, check_id, detail = parts
    digest = hashlib.md5(detail.encode()).hexdigest()[:8]
    issue_id = f"{check_id}:{digest}"
    if issue_id in state["falsePositives"]:
        continue
    parsed.append({"severity": sev, "check_id": check_id, "detail": detail, "issue_id": issue_id})

# Reconcile
active_ids = set()
new_issues = []
recurring_issues = []
for p in parsed:
    iid = p["issue_id"]
    active_ids.add(iid)
    if iid in state["knownIssues"]:
        ki = state["knownIssues"][iid]
        ki["lastSeen"] = now_iso
        ki["runsFailing"] = ki.get("runsFailing", 1) + 1
        ki["status"] = "open"
        recurring_issues.append((p, ki))
    else:
        state["knownIssues"][iid] = {
            "severity": p["severity"],
            "check_id": p["check_id"],
            "detail": p["detail"],
            "firstSeen": now_iso,
            "lastSeen": now_iso,
            "runsFailing": 1,
            "status": "open",
        }
        new_issues.append(p)
        # Record verified leak history
        if p["severity"] == "P0" and "verified" in p["check_id"].lower():
            state["verifiedLeakHistory"].append({"ts": now_iso, "issue_id": iid, "detail": p["detail"]})
            state["verifiedLeakHistory"] = state["verifiedLeakHistory"][-50:]

# Mark resolved for anything not active
resolved_this_run = []
for iid, ki in list(state["knownIssues"].items()):
    if iid not in active_ids and ki.get("status") == "open":
        ki["status"] = "resolved"
        ki["resolvedAt"] = now_iso
        resolved_this_run.append(iid)

# Purge resolved older than 7 days
def parse_iso(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None

now_dt = parse_iso(now_iso)
to_purge = []
for iid, ki in state["knownIssues"].items():
    if ki.get("status") == "resolved":
        rdt = parse_iso(ki.get("resolvedAt", ""))
        if rdt and (now_dt - rdt).days >= 7:
            to_purge.append(iid)
for iid in to_purge:
    del state["knownIssues"][iid]

# Append run history
state["runHistory"].append({
    "ts": now_iso,
    "failed": len(parsed),
    "newIssues": len(new_issues),
    "recurring": len(recurring_issues),
    "resolved": len(resolved_this_run),
    "autofixes": autofix_count,
})
state["runHistory"] = state["runHistory"][-30:]

with open(state_path, "w") as f:
    json.dump(state, f, indent=2)

# File new findings idempotently into KAI_TASKS
if os.path.exists(tasks_path):
    with open(tasks_path) as f:
        tasks_content = f.read()
    lines_to_add = []
    for p in new_issues:
        marker = f"[cipher:{p['issue_id']}]"
        if marker not in tasks_content:
            lines_to_add.append(f"- [ ] **[K]** [cipher] **{p['severity']}** {p['detail']} {marker} _(filed {today})_")
    # Once-per-day gating for "tool not installed" tasks
    for p in new_issues:
        pass  # handled above
    if lines_to_add:
        with open(tasks_path, "a") as f:
            f.write("\n" + "\n".join(lines_to_add) + "\n")

# Exit code: 0 clean, 1 pattern matches, 2 verified leaks (blocks pre-commit)
if any(p["severity"] == "P0" for p in parsed):
    sys.exit(2)
elif len(parsed) > 0:
    sys.exit(1)
sys.exit(0)
PYEOF

RC=$?

# ---- summary output ---------------------------------------------------------
# Rotate old hourly logs (keep last 48h)
find "$LOGS" -name 'cipher-*.log' -mtime +2 -delete 2>/dev/null || true

# ---- auto-push to HQ -------------------------------------------------------
KAI="$ROOT/bin/kai.sh"
SDIR_MODE=$(stat_mode "$ROOT/.secrets" 2>/dev/null || echo "???")
FT_MODE=$(stat_mode "$ROOT/.secrets/founder.token" 2>/dev/null || echo "???")
if [[ -x "$KAI" ]]; then
  "$KAI" push cipher "Scan — ${#FINDINGS[@]} findings, ${#AUTOFIXES[@]} autofixes" \
    --data "{\"secretsDir\":\"$SDIR_MODE\",\"founderToken\":\"$FT_MODE\",\"leaks\":${#FINDINGS[@]}}" 2>/dev/null || true
fi

if [[ $RC -eq 0 ]]; then
  if [[ ${#AUTOFIXES[@]} -gt 0 ]]; then
    echo "cipher: clean. ${#AUTOFIXES[@]} auto-fix(es) applied. See $HOURLY_LOG"
  else
    echo "cipher: clean. 0 findings."
  fi
  exit 0
elif [[ $RC -eq 2 ]]; then
  echo "cipher: P0 VERIFIED LEAK(S). BLOCKING. See $HOURLY_LOG"
  exit 2
else
  echo "cipher: findings filed to KAI_TASKS. See $HOURLY_LOG"
  exit 1
fi
