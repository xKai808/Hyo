#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/kai/sentinel.sh
#
# sentinel.hyo — QA runner with persistent memory.
# Reads state from kai/memory/sentinel.state.json and its algorithm from
# kai/memory/sentinel.algorithm.md. Writes updated state at end.
# Philosophy: silence = success.

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LOGS="$ROOT/kai/logs"
MEMORY="$ROOT/kai/memory"
STATE="$MEMORY/sentinel.state.json"
TASKS="$ROOT/KAI_TASKS.md"
BRIEF="$ROOT/KAI_BRIEF.md"
TODAY=$(date +%Y-%m-%d)
NOW_ISO=$(date -u +%FT%TZ)
REPORT="$LOGS/sentinel-$TODAY.md"

mkdir -p "$LOGS" "$MEMORY"

# ---- state bootstrap --------------------------------------------------------
if [[ ! -f "$STATE" ]]; then
  cat > "$STATE" <<'JSON'
{
  "schema": "hyo.agent.memory.v1",
  "agent": "sentinel.hyo",
  "firstSeenAt": null,
  "lastRunAt": null,
  "totalRuns": 0,
  "runHistory": [],
  "knownIssues": {},
  "falsePositives": [],
  "trendCounters": {},
  "escalationState": {"lastEscalationAt": null, "escalationsFiledThisWeek": 0}
}
JSON
fi

# ---- findings collector -----------------------------------------------------
# Each finding: "SEVERITY|check_id|detail"
FINDINGS=()
PASSED=()

pass() { PASSED+=("$1"); }
fail() { FINDINGS+=("$1"); }

# ---- check battery ----------------------------------------------------------

# P0 aurora-ran-today
NEWSLETTER="$ROOT/newsletters/${TODAY}.md"
if [[ -s "$NEWSLETTER" ]] && [[ $(wc -c < "$NEWSLETTER" | tr -d ' ') -gt 500 ]]; then
  pass "P0 aurora-ran-today"
else
  fail "P0|aurora-ran-today|missing or empty $NEWSLETTER"
fi

# P0 api-health-green
HEALTH=$(curl -sf https://www.hyo.world/api/health 2>/dev/null || echo '{}')
if echo "$HEALTH" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get("ok") and d.get("founderTokenConfigured") else 1)' 2>/dev/null; then
  pass "P0 api-health-green"
else
  fail "P0|api-health-green|health endpoint not green or token unconfigured"
fi

# P0 founder-token-integrity
if [[ -f "$ROOT/.secrets/founder.token" ]]; then
  FTMODE=$(stat -f %Mp%Lp "$ROOT/.secrets/founder.token" 2>/dev/null || stat -c %a "$ROOT/.secrets/founder.token")
  if [[ "$FTMODE" =~ ^6[0-9][0-9]$ ]]; then
    pass "P0 founder-token-integrity"
  else
    fail "P0|founder-token-integrity|founder.token mode is $FTMODE, want 6xx"
  fi
else
  fail "P0|founder-token-integrity|.secrets/founder.token missing"
fi

# P1 scheduled-tasks-fired (proxy: recent aurora log)
LAST_AURORA_LOG=$(ls -1t "$LOGS"/aurora-*.log 2>/dev/null | head -n1 || true)
if [[ -n "$LAST_AURORA_LOG" ]]; then
  AGE_SEC=$(( $(date +%s) - $(stat -f %m "$LAST_AURORA_LOG" 2>/dev/null || stat -c %Y "$LAST_AURORA_LOG") ))
  if [[ $AGE_SEC -lt 90000 ]]; then
    pass "P1 scheduled-tasks-fired"
  else
    fail "P1|scheduled-tasks-fired|last aurora log is ${AGE_SEC}s old (>25h)"
  fi
else
  fail "P1|scheduled-tasks-fired|no aurora logs in $LOGS"
fi

# P1 manifest-valid-json
MANIFEST_ERR=""
for f in "$ROOT"/NFT/agents/*.hyo.json; do
  [[ -f "$f" ]] || continue
  if ! python3 -c "
import json, sys
with open('$f') as fh: d = json.load(fh)
for k in ['name','version','identity','credit','pricing']:
    if k not in d: sys.exit(1)
" 2>/dev/null; then
    MANIFEST_ERR="${MANIFEST_ERR}$(basename "$f") "
  fi
done
if [[ -z "$MANIFEST_ERR" ]]; then
  pass "P1 manifest-valid-json"
else
  fail "P1|manifest-valid-json|malformed: $MANIFEST_ERR"
fi

# P1 secrets-dir-permissions
if [[ -d "$ROOT/.secrets" ]]; then
  SMODE=$(stat -f %Mp%Lp "$ROOT/.secrets" 2>/dev/null || stat -c %a "$ROOT/.secrets")
  if [[ "$SMODE" =~ ^7[0-9][0-9]$ ]]; then
    pass "P1 secrets-dir-permissions"
  else
    fail "P1|secrets-dir-permissions|$SMODE (want 700) — run: chmod 700 $ROOT/.secrets"
  fi
else
  pass "P1 secrets-dir-permissions (no .secrets/)"
fi

# P1 repo-is-git
if [[ -d "$ROOT/.git" ]]; then
  pass "P1 repo-is-git"
else
  fail "P1|repo-is-git|no .git/ directory — uncommitted work at catastrophic loss risk"
fi

# P2 kai-dispatcher-present
if [[ -x "$ROOT/bin/kai.sh" ]]; then
  pass "P2 kai-dispatcher-present"
else
  fail "P2|kai-dispatcher-present|bin/kai.sh missing or not executable"
fi

# P2 task-queue-size (overload signal)
if [[ -f "$TASKS" ]]; then
  P0_COUNT=$(awk '/^## P0/,/^## P1/' "$TASKS" | grep -c '^- \[ \]' || true)
  if [[ $P0_COUNT -le 5 ]]; then
    pass "P2 task-queue-size (P0=$P0_COUNT)"
  else
    fail "P2|task-queue-size|$P0_COUNT P0 tasks (overload threshold 5)"
  fi
fi

# ---- process findings through memory ---------------------------------------
python3 - "$STATE" "$REPORT" "$TASKS" "$NOW_ISO" "$TODAY" "${#PASSED[@]}" "${FINDINGS[@]:-}" <<'PYEOF'
import json, sys, os, hashlib, re
from datetime import datetime

state_path = sys.argv[1]
report_path = sys.argv[2]
tasks_path = sys.argv[3]
now_iso = sys.argv[4]
today = sys.argv[5]
passed_count = int(sys.argv[6])
raw_findings = sys.argv[7:]

with open(state_path) as f:
    state = json.load(f)

if state.get("firstSeenAt") is None:
    state["firstSeenAt"] = now_iso

state["lastRunAt"] = now_iso
state["totalRuns"] = state.get("totalRuns", 0) + 1
state.setdefault("knownIssues", {})
state.setdefault("falsePositives", [])
state.setdefault("runHistory", [])
state.setdefault("trendCounters", {})

parsed = []
for f in raw_findings:
    if not f: continue
    parts = f.split("|", 2)
    if len(parts) != 3: continue
    sev, check_id, detail = parts
    # Hash detail to a short key so issue_id stays stable across runs for the same specific problem
    digest = hashlib.md5(detail.encode()).hexdigest()[:8]
    issue_id = f"{check_id}:{digest}"
    if issue_id in state["falsePositives"]:
        continue
    parsed.append({"severity": sev, "check_id": check_id, "detail": detail, "issue_id": issue_id})

# Reconcile with known issues
active_ids = set()
new_issues = []
recurring_issues = []
for p in parsed:
    iid = p["issue_id"]
    active_ids.add(iid)
    if iid in state["knownIssues"]:
        ki = state["knownIssues"][iid]
        ki["lastSeen"] = now_iso
        ki["daysFailing"] = ki.get("daysFailing", 1) + 1
        ki["status"] = "open"
        recurring_issues.append((p, ki))
    else:
        state["knownIssues"][iid] = {
            "severity": p["severity"],
            "check_id": p["check_id"],
            "detail": p["detail"],
            "firstSeen": now_iso,
            "lastSeen": now_iso,
            "daysFailing": 1,
            "status": "open",
        }
        new_issues.append(p)

# Mark resolved for anything not active
resolved_this_run = []
for iid, ki in list(state["knownIssues"].items()):
    if iid not in active_ids and ki.get("status") == "open":
        ki["status"] = "resolved"
        ki["resolvedAt"] = now_iso
        resolved_this_run.append(iid)

# Purge resolved issues older than 7 days
# (simple: anything marked resolved more than 7 days ago)
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

# Escalation evaluation
escalations = []
for p, ki in recurring_issues:
    sev = ki["severity"]
    days = ki["daysFailing"]
    if sev == "P0" and days >= 2:
        escalations.append((p, ki, "P0 escalated — failing {} runs in a row".format(days)))
    elif sev == "P1" and days >= 3:
        escalations.append((p, ki, "P1 elevated — failing {} runs in a row".format(days)))
    elif sev == "P2" and days >= 5:
        escalations.append((p, ki, "P2 elevated — failing {} runs in a row".format(days)))

# Append run history (keep last 30)
state["runHistory"].append({
    "ts": now_iso,
    "passed": passed_count,
    "failed": len(parsed),
    "newIssues": len(new_issues),
    "recurringIssues": len(recurring_issues),
    "resolved": len(resolved_this_run),
})
state["runHistory"] = state["runHistory"][-30:]

# Write state
with open(state_path, "w") as f:
    json.dump(state, f, indent=2)

# Compose report
report_lines = [
    f"# Sentinel QA report — {today}",
    "",
    f"**Total runs ever:** {state['totalRuns']}",
    f"**This run:** {passed_count} passed, {len(parsed)} failed",
    f"**New issues:** {len(new_issues)}",
    f"**Recurring:** {len(recurring_issues)}",
    f"**Resolved this run:** {len(resolved_this_run)}",
    "",
]
if new_issues:
    report_lines.append("## New findings")
    for p in new_issues:
        report_lines.append(f"- **{p['severity']}** `{p['check_id']}` — {p['detail']}")
    report_lines.append("")
if recurring_issues:
    report_lines.append("## Recurring")
    for p, ki in recurring_issues:
        report_lines.append(f"- **{p['severity']}** `{p['check_id']}` — {p['detail']} _(day {ki['daysFailing']})_")
    report_lines.append("")
if escalations:
    report_lines.append("## Escalations")
    for p, ki, msg in escalations:
        report_lines.append(f"- **{msg}**: {p['detail']}")
    report_lines.append("")
if resolved_this_run:
    report_lines.append("## Resolved this run")
    for iid in resolved_this_run:
        report_lines.append(f"- `{iid}`")
    report_lines.append("")
with open(report_path, "w") as f:
    f.write("\n".join(report_lines))

# File new findings into KAI_TASKS (idempotent by issue_id substring match)
if os.path.exists(tasks_path):
    with open(tasks_path) as f:
        tasks_content = f.read()
    lines_to_add = []
    for p in new_issues:
        marker = f"[sentinel:{p['issue_id']}]"
        if marker not in tasks_content:
            prio_tag = {"P0": "**[K]** [sentinel]", "P1": "**[K]** [sentinel]", "P2": "**[K]** [sentinel]"}.get(p["severity"], "**[K]** [sentinel]")
            lines_to_add.append(f"- [ ] {prio_tag} {p['detail']} {marker} _(filed {today})_")
    for p, ki, msg in escalations:
        marker = f"[sentinel:{p['issue_id']}:escalated]"
        if marker not in tasks_content:
            lines_to_add.append(f"- [ ] **[K]** [sentinel] **ESCALATED** {msg}: {p['detail']} {marker}")
    if lines_to_add:
        with open(tasks_path, "a") as f:
            f.write("\n" + "\n".join(lines_to_add) + "\n")

# Exit code logic
if len(parsed) == 0:
    sys.exit(0)
elif any(p["severity"] == "P0" for p in parsed):
    sys.exit(2)
else:
    sys.exit(1)
PYEOF

RC=$?

# ---- summary output ---------------------------------------------------------
if [[ $RC -eq 0 ]]; then
  echo "sentinel: ${#PASSED[@]} checks passed, 0 failed. Silence = success."
  exit 0
elif [[ $RC -eq 2 ]]; then
  echo "sentinel: P0 FAILURES. See $REPORT"
  cat "$REPORT"
  exit 2
else
  echo "sentinel: findings filed. See $REPORT"
  cat "$REPORT"
  exit 1
fi
