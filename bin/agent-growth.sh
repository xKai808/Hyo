#!/usr/bin/env bash
# bin/agent-growth.sh — Growth execution phase for agent runners
#
# Every agent runner sources this and calls: run_growth_phase "$AGENT_NAME"
#
# What it does:
# 1. Reads the agent's GROWTH.md for the next improvement to work on
# 2. Reads improvement tickets (IMP-*) for that agent
# 3. Executes diagnostic steps to gather research findings
# 4. Writes aric-latest.json with status: researched
# 5. Calls agent-execute-improvement.sh to generate and commit real code
# 6. Updates the ticket status to SHIPPED after successful execution
#
# Agents have the RIGHT to build. They don't need Kai's permission.
# They report what they did. Kai can veto, but they execute first.
#
# AETHER EXCEPTION: Aether only identifies external macro/market weaknesses.
# No changes to AetherBot code are allowed outside the daily analysis protocol.
# Aether's growth phase runs diagnostics only — never calls the execution engine.
#
# Usage in a runner:
#   source "$HYO_ROOT/bin/agent-growth.sh"
#   run_growth_phase "nel"

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
GROWTH_LOG_TAG="[growth]"

growth_log() { echo "$GROWTH_LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) [$1] $2"; }

# ── ARIC research trigger ──────────────────────────────────────────────────────

check_aric_day() {
  local agent="$1"
  local aric_date
  aric_date=$(TZ="America/Denver" date +%Y-%m-%d)
  local aric_marker_dir="$HYO_ROOT/agents/$agent/research"
  mkdir -p "$aric_marker_dir"

  local marker="$aric_marker_dir/aric-trigger-$aric_date"
  local findings="$aric_marker_dir/findings-$aric_date.md"

  if [[ -f "$marker" && -f "$findings" ]]; then
    growth_log "$agent" "ARIC: research already complete for $aric_date — skipping"
    return 0
  fi

  growth_log "$agent" "ARIC trigger: daily full research cycle (Phases 1-7)"
  touch "$marker"

  local research_script="$HYO_ROOT/bin/agent-research.sh"
  if [[ -x "$research_script" ]]; then
    growth_log "$agent" "ARIC: invoking agent-research.sh for $agent"
    if HYO_ROOT="$HYO_ROOT" bash "$research_script" "$agent" 2>&1 | tail -3; then
      growth_log "$agent" "ARIC: research cycle complete"
    else
      growth_log "$agent" "ARIC: research cycle encountered errors — check research/raw/"
    fi
  else
    growth_log "$agent" "ARIC: agent-research.sh not found/executable — skipping"
  fi
}

# ── files_to_change mapping ────────────────────────────────────────────────────
# Every improvement ticket maps to a specific file to create/modify.
# This is the bridge between "ticket identified" and "Claude writes code."
#
# Rules:
# - New files are preferred over modifying existing runners
# - One file per improvement (Gate 2 in agent-execute-improvement.sh)
# - aether: always returns empty — no code execution for Aether
#
get_files_to_change() {
  local agent="$1"
  local weakness="$2"
  case "$agent-$weakness" in
    nel-W1) echo "agents/nel/adaptive-sentinel.sh" ;;
    nel-W2) echo "agents/nel/dependency-audit.sh" ;;
    nel-W3) echo "agents/nel/intelligence-cache.py" ;;
    ra-W1)  echo "agents/ra/pipeline/source-health.py" ;;
    ra-W2)  echo "agents/ra/pipeline/quality-score.py" ;;
    ra-W3)  echo "agents/ra/pipeline/topic-map.py" ;;
    sam-W1) echo "agents/sam/performance-check.sh" ;;
    sam-W2) echo "agents/sam/website/api/kv-store.js" ;;
    sam-W3) echo "agents/sam/error-audit.sh" ;;
    dex-W1) echo "agents/dex/jsonl-repair.py" ;;
    dex-W2) echo "agents/dex/root-cause-cluster.py" ;;
    dex-W3) echo "agents/dex/constitution-drift.py" ;;
    aether-*) echo "" ;;  # Aether: no code execution
    *) echo "" ;;
  esac
}

# ── improvement thesis mapping ─────────────────────────────────────────────────
# Expanded thesis fed to Claude as the improvement specification.
# This is what Claude API reads to understand what code to write.
#
get_improvement_thesis() {
  local agent="$1"
  local weakness="$2"
  case "$agent-$weakness" in
    nel-W1) echo "Build adaptive-sentinel.sh: detect checks that have failed 5+ consecutive times in sentinel.state.json and auto-escalate them — double check frequency, add deeper diagnostic step, write P1 ticket. Input: agents/nel/memory/sentinel.state.json. Output: JSONL to agents/nel/ledger/adaptive-sentinel.jsonl with check_name, consecutive_failures, escalation_action, timestamp." ;;
    nel-W2) echo "Build dependency-audit.sh: read package.json + run npm audit (or parse npm audit --json), cross-reference against OSV/GitHub Advisory API, output JSONL with package, severity, CVE, current_version, safe_version, upgrade_command. Write to agents/nel/ledger/dependency-audit.jsonl." ;;
    nel-W3) echo "Build intelligence-cache.py: SQLite-backed local cache for Nel research findings. Schema: (id, source, key_term, finding, severity, first_seen, last_seen, hit_count). Nel reads from cache before hitting live sources. On cache miss: fetch, store. On hit: return cached + update hit_count. Cache expires after 7 days. Write to agents/nel/ledger/intel-cache.db." ;;
    ra-W1)  echo "Build source-health.py: for each entry in agents/ra/pipeline/sources.json, HTTP HEAD the URL with 5s timeout, record status_code, latency_ms, last_ok, consecutive_failures. Disable sources with 3+ consecutive failures by setting 'disabled': true. Write health report to agents/ra/ledger/source-health.jsonl." ;;
    ra-W2)  echo "Build quality-score.py: score each newsletter section on 4 axes — source_diversity (0-25: unique domain count), recency (0-25: median article age in hours), specificity (0-25: named entities per 100 words), reader_value (0-25: contains price/data/actionable insight). Total score 0-100. Write to agents/ra/ledger/quality-scores.jsonl." ;;
    ra-W3)  echo "Build topic-map.py: maintain a required_topics config (DeFi protocols, L2s, MEV, regulatory, macro). For each newsletter run, scan content for topic mentions. Flag any required topic with 0 coverage in the past 7 days. Output agents/ra/ledger/topic-coverage.jsonl with topic, days_since_covered, coverage_count_7d, gap_flag." ;;
    sam-W1) echo "Build performance-check.sh: after every deploy, curl each HQ API endpoint 3 times, record min/mean/max response time in ms. Compare against 7-day baseline from agents/sam/ledger/performance-baseline.jsonl. If any endpoint regresses >20%, write P2 alert to kai/ledger/known-issues.jsonl. Use curl -w '%{time_total}' -o /dev/null -s." ;;
    sam-W2) echo "Build kv-store.js: Vercel KV wrapper module for website/api/. Exports get(key), set(key, value, ttl), del(key). Falls back to in-memory Map if KV_REST_API_URL env var not set. Logs all misses to stderr with [kv-miss] prefix. Use @vercel/kv if available, else implement REST client with fetch()." ;;
    sam-W3) echo "Build error-audit.sh: scan all files in agents/sam/website/api/*.js for catch blocks. For each catch block, check if it logs to stderr with structured fields (endpoint, error, timestamp). Count endpoints with bare 'catch(e) {}' or 'catch(e) { return }'. Write audit report to agents/sam/ledger/error-audit.jsonl with file, has_logging, bare_catch_count." ;;
    dex-W1) echo "Build jsonl-repair.py: auto-repair known JSONL corruption types. Scan all *.jsonl files in the repo. Patterns to fix: (1) double-encoded JSON (stringified JSON inside JSON), (2) missing closing brace, (3) concatenated objects (}}{{). For each corrupt line, attempt repair, write repaired version to .repaired temp, validate, then replace original atomically. Log repairs to agents/dex/ledger/jsonl-repairs.jsonl." ;;
    dex-W2) echo "Build root-cause-cluster.py: read kai/ledger/known-issues.jsonl and kai/ledger/session-errors.jsonl. Group by (source_agent, category, description_prefix). For each cluster >2 entries, compute: first_seen, last_seen, occurrence_count, unique_sessions. Rank by occurrence_count. Output top 15 clusters to agents/dex/ledger/root-cause-clusters.jsonl with cluster_id, title, count, recommended_systemic_fix." ;;
    dex-W3) echo "Build constitution-drift.py: parse CLAUDE.md operating rules section as a list of named rules. For each agent, read their last 7 days of runner logs (agents/<name>/logs/). Check if log lines reference protocol steps (e.g., 'ARIC', 'healthcheck', 'dispatch', 'verify'). Flag any rule with 0 log references in 7 days as 'drift'. Output agents/dex/ledger/constitution-drift.jsonl." ;;
    *) echo "Implement the improvement described in the ticket title." ;;
  esac
}

# ── write aric-latest.json with status: researched ────────────────────────────
write_aric_for_ticket() {
  local agent="$1"
  local ticket_id="$2"
  local ticket_title="$3"
  local weakness="$4"
  local research_summary="$5"
  local aric_json="$HYO_ROOT/agents/$agent/research/aric-latest.json"
  local today
  today=$(TZ="America/Denver" date +%Y-%m-%d)

  local files_to_change
  files_to_change=$(get_files_to_change "$agent" "$weakness")

  if [[ -z "$files_to_change" ]]; then
    growth_log "$agent" "No files_to_change mapping for $agent/$weakness — cannot execute"
    return 1
  fi

  local thesis
  thesis=$(get_improvement_thesis "$agent" "$weakness")

  # Pass all strings as sys.argv — Python receives raw strings, json.dumps handles escaping.
  # Truncate research_summary to 2000 chars to avoid ARG_MAX limits.
  local safe_research
  safe_research=$(echo "$research_summary" | head -20 | cut -c1-2000)

  python3 - "$aric_json" "$today" "$agent" "$ticket_id" "$weakness" "$files_to_change" \
            "$ticket_title" "$thesis" "$safe_research" <<'PYEOF'
import json, sys, os

aric_json    = sys.argv[1]
today        = sys.argv[2]
agent        = sys.argv[3]
ticket_id    = sys.argv[4]
weakness     = sys.argv[5]
files_str    = sys.argv[6]
description  = sys.argv[7]
thesis       = sys.argv[8]
research     = sys.argv[9]

# files_to_change is a single path; wrap in list
files = [f.strip() for f in files_str.split(",") if f.strip()]

aric = {
  "cycle_date": today,
  "agent": agent,
  "improvement_built": {
    "ticket_id": ticket_id,
    "description": description,
    "weakness": weakness,
    "thesis": thesis,
    "research_summary": research,
    "files_to_change": files,
    "status": "researched",
    "success_metric": "New file exists, is executable or importable, produces structured JSONL output"
  }
}

os.makedirs(os.path.dirname(aric_json), exist_ok=True)
with open(aric_json, "w") as f:
    json.dump(aric, f, indent=2)
print(f"Wrote aric-latest.json for {ticket_id} → files: {files}")
PYEOF
}

# ── update ticket status in tickets.jsonl ─────────────────────────────────────
update_ticket_status() {
  local ticket_id="$1"
  local new_status="$2"
  local ticket_ledger="$HYO_ROOT/kai/tickets/tickets.jsonl"

  python3 - "$ticket_ledger" "$ticket_id" "$new_status" <<'PYEOF'
import json, os, sys

ledger     = sys.argv[1]
ticket_id  = sys.argv[2]
new_status = sys.argv[3]

if not os.path.exists(ledger):
    print(f"Ledger not found: {ledger}")
    sys.exit(1)

updated = []
changed = False
with open(ledger) as f:
    for line in f:
        stripped = line.rstrip("\n")
        if not stripped.strip():
            updated.append(stripped)
            continue
        try:
            t = json.loads(stripped)
            if t.get("id") == ticket_id and not changed:
                t["status"] = new_status
                changed = True
            updated.append(json.dumps(t))
        except Exception:
            updated.append(stripped)

tmp = ledger + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(updated) + "\n")
os.replace(tmp, ledger)
print(f"Ticket {ticket_id} → {new_status} ({'updated' if changed else 'not found'})")
PYEOF
}

# ── execute the next improvement via Claude API ────────────────────────────────
execute_next_improvement() {
  local agent="$1"
  local ticket_id="$2"
  local ticket_title="$3"
  local weakness="$4"
  local research_summary="$5"

  # Gate: Aether never runs the code execution engine
  if [[ "$agent" == "aether" ]]; then
    growth_log "$agent" "Aether: execution engine skipped (market analysis only — AetherBot code is protected)"
    return 0
  fi

  # Gate: must have a files_to_change mapping
  local files_to_change
  files_to_change=$(get_files_to_change "$agent" "$weakness")
  if [[ -z "$files_to_change" ]]; then
    growth_log "$agent" "No files_to_change mapping for $agent/$weakness — skipping execution"
    return 1
  fi

  growth_log "$agent" "Writing aric-latest.json for $ticket_id (files: $files_to_change)"
  if ! write_aric_for_ticket "$agent" "$ticket_id" "$ticket_title" "$weakness" "$research_summary"; then
    growth_log "$agent" "Failed to write aric-latest.json — aborting execution"
    return 1
  fi

  # ── ARIC Phase 7.5: Adversarial Verifier Gate ──────────────────────────────
  # Before the execution engine runs, challenge the improvement plan with
  # 5 adversarial questions. Block execution if score < 70/100.
  # Based on: arXiv:2212.08073 (Constitutional AI critique-revision loop),
  #           arXiv:2410.04663 (D3 Debate-Deliberate-Decide),
  #           arXiv:2512.02731 (GVU — Generator/Verifier separation).
  local aric_verifier="$HYO_ROOT/bin/aric-verifier.py"
  if [[ -f "$aric_verifier" ]]; then
    growth_log "$agent" "ARIC Phase 7.5: running adversarial verifier..."
    local verifier_exit=0
    local verifier_output
    verifier_output=$(python3 "$aric_verifier" --agent "$agent" --mode heuristic 2>&1) || verifier_exit=$?
    if [[ "$verifier_exit" -eq 1 ]]; then
      growth_log "$agent" "ARIC Phase 7.5 REQUIRES_REVISION — execution blocked. Verifier output:"
      echo "$verifier_output" | tail -5 | while read -r line; do
        growth_log "$agent" "  [verifier] $line"
      done
      # Update ticket to flag the revision requirement
      update_ticket_status "$ticket_id" "OPEN" >/dev/null 2>&1 || true
      "$HYO_ROOT/bin/ticket.sh" update "$ticket_id" \
        --note "ARIC Phase 7.5 BLOCKED: adversarial verifier score < 70 — revision required before execution" \
        2>/dev/null || true
      return 1
    elif [[ "$verifier_exit" -eq 0 ]]; then
      growth_log "$agent" "ARIC Phase 7.5 APPROVED — proceeding to execution"
    else
      growth_log "$agent" "ARIC Phase 7.5 verifier error (exit $verifier_exit) — proceeding anyway (non-blocking)"
    fi
  fi

  local execute_script="$HYO_ROOT/bin/agent-execute-improvement.sh"
  if [[ ! -f "$execute_script" ]]; then
    growth_log "$agent" "agent-execute-improvement.sh not found at $execute_script"
    return 1
  fi
  if [[ ! -x "$execute_script" ]]; then
    chmod +x "$execute_script"
  fi

  # Mark ticket IN_PROGRESS before calling engine
  update_ticket_status "$ticket_id" "IN_PROGRESS" >/dev/null 2>&1 || true

  growth_log "$agent" "Calling execution engine for $ticket_id..."
  local exec_output
  if exec_output=$(HYO_ROOT="$HYO_ROOT" bash "$execute_script" "$agent" "$ticket_id" 2>&1); then
    local exec_status
    exec_status=$(echo "$exec_output" | grep -E "^Status:" | awk '{print $2}' | head -1)
    local commit_hash
    commit_hash=$(echo "$exec_output" | grep -E "^Commit:" | awk '{print $2}' | head -1)

    growth_log "$agent" "Execution engine output (last 5 lines):"
    echo "$exec_output" | tail -5 | while read -r line; do
      growth_log "$agent" "  $line"
    done

    if [[ "$exec_status" == "shipped" || -n "$commit_hash" ]]; then
      growth_log "$agent" "SUCCESS: $ticket_id shipped — commit $commit_hash"
      update_ticket_status "$ticket_id" "SHIPPED" | while read -r line; do
        growth_log "$agent" "$line"
      done
    else
      growth_log "$agent" "Execution completed but status unclear — check aric-latest.json"
      # Leave as IN_PROGRESS for retry next cycle
    fi
  else
    local exit_code=$?
    growth_log "$agent" "Execution engine failed (exit $exit_code) for $ticket_id"
    echo "$exec_output" | tail -8 | while read -r line; do
      growth_log "$agent" "  [exec-err] $line"
    done
    # Revert to OPEN so it retries next cycle
    update_ticket_status "$ticket_id" "OPEN" >/dev/null 2>&1 || true
    return 1
  fi
}

# ── main growth phase ──────────────────────────────────────────────────────────

run_growth_phase() {
  local agent="$1"
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
  local ticket_ledger="$HYO_ROOT/kai/tickets/tickets.jsonl"
  local timestamp
  timestamp=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)

  growth_log "$agent" "Starting growth phase"

  # Trigger ARIC research if not yet run today
  check_aric_day "$agent"

  if [[ ! -f "$growth_file" ]]; then
    growth_log "$agent" "No GROWTH.md found — skipping growth phase"
    return 0
  fi

  # Find the next OPEN improvement ticket (IMP-* type only, not TASK-*)
  local next_ticket=""
  local next_title=""
  local next_weakness=""
  if [[ -f "$ticket_ledger" ]]; then
    # Read all three fields in one pass — output as JSON for safe parsing
    local ticket_json
    ticket_json=$(python3 - "$ticket_ledger" "$agent" <<'PYEOF'
import json, sys

ledger = sys.argv[1]
agent  = sys.argv[2]

with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            t = json.loads(line)
            if (t.get("owner") == agent
                    and t.get("ticket_type") == "improvement"
                    and t.get("status") == "OPEN"
                    and t.get("id", "").startswith("IMP-")):
                print(json.dumps({
                    "id": t["id"],
                    "title": t.get("title", "")[:80],
                    "weakness": t.get("weakness", "")
                }))
                break
        except Exception:
            pass
PYEOF
)
    if [[ -n "$ticket_json" ]]; then
      next_ticket=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['id'])" "$ticket_json" 2>/dev/null)
      next_title=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['title'])" "$ticket_json" 2>/dev/null)
      next_weakness=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['weakness'])" "$ticket_json" 2>/dev/null)
    fi
  fi

  if [[ -z "$next_ticket" ]]; then
    growth_log "$agent" "No open IMP improvement tickets — growth phase idle"
    return 0
  fi

  growth_log "$agent" "Next improvement: $next_ticket — $next_title (addresses $next_weakness)"

  # ── Agent-specific diagnostic steps ───────────────────────────────────────
  # These gather research_summary data fed to the execution engine.
  # Result is ALWAYS piped into execute_next_improvement below.

  local executed=false
  local result=""

  case "$agent" in
    nel)
      if [[ "$next_weakness" == "W1" ]]; then
        local sentinel_state="$HYO_ROOT/agents/nel/memory/sentinel.state.json"
        if [[ -f "$sentinel_state" ]]; then
          result=$(python3 - "$sentinel_state" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    s = json.load(f)
chronic = []
for check, data in s.get("checks", {}).items():
    consec = data.get("consecutive_failures", 0)
    if consec >= 5:
        chronic.append(f"{check}: {consec} consecutive failures")
if chronic:
    print(f"Found {len(chronic)} chronic failures: " + "; ".join(chronic))
else:
    print("No chronic failures detected (all < 5 consecutive)")
PYEOF
) || result="Could not read sentinel state"
          executed=true
        else
          result="sentinel.state.json not found — sentinel likely not yet initialised"
          executed=true
        fi
      fi

      if [[ "$next_weakness" == "W2" ]]; then
        local pkg_json="$HYO_ROOT/package.json"
        if [[ -f "$pkg_json" ]]; then
          result=$(python3 - "$pkg_json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    pkg = json.load(f)
deps = {}
deps.update(pkg.get("dependencies", {}))
deps.update(pkg.get("devDependencies", {}))
print(f"Found {len(deps)} dependencies in package.json")
print("Cross-reference against GitHub Advisory Database is the next step")
for name, ver in sorted(deps.items()):
    print(f"  {name}: {ver}")
PYEOF
) || result="Could not parse package.json"
          executed=true
        else
          result="No package.json at project root — website/package.json may exist"
          executed=true
        fi
      fi

      if [[ "$next_weakness" == "W3" ]]; then
        local cache_db="$HYO_ROOT/agents/nel/ledger/intel-cache.db"
        if [[ -f "$cache_db" ]]; then
          result="Intel cache exists at agents/nel/ledger/intel-cache.db — check hit rate"
        else
          result="No intel cache found — first run will create agents/nel/ledger/intel-cache.db SQLite database"
        fi
        executed=true
      fi
      ;;

    ra)
      if [[ "$next_weakness" == "W1" ]]; then
        local sources_json="$HYO_ROOT/agents/ra/pipeline/sources.json"
        if [[ -f "$sources_json" ]]; then
          result=$(python3 - "$sources_json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    sources = json.load(f)
if isinstance(sources, list):
    print(f"Found {len(sources)} sources in pipeline config")
    print("Next: add per-source health score field and track consecutive_failures")
elif isinstance(sources, dict):
    total = sum(len(v) if isinstance(v, list) else 1 for v in sources.values())
    print(f"Found {total} sources across {len(sources)} categories")
    print("Next: source-health.py Phase 0 — HEAD each URL before gather")
PYEOF
) || result="Could not parse sources.json"
          executed=true
        fi
      fi

      if [[ "$next_weakness" == "W2" ]]; then
        result="Content quality scoring not yet implemented — quality-score.py will add 4-axis scoring to newsletter sections"
        executed=true
      fi

      if [[ "$next_weakness" == "W3" ]]; then
        result="Topic coverage map not yet implemented — topic-map.py will track required DeFi/crypto topics vs actual coverage"
        executed=true
      fi
      ;;

    sam)
      if [[ "$next_weakness" == "W1" ]]; then
        local baseline_file="$HYO_ROOT/agents/sam/ledger/performance-baseline.jsonl"
        if [[ -f "$baseline_file" ]]; then
          local entry_count
          entry_count=$(wc -l < "$baseline_file" | tr -d ' ')
          result="Performance baseline exists with $entry_count entries — regression detection script needed"
        else
          result="No performance baseline found — performance-check.sh will establish baseline on first run"
        fi
        executed=true
      fi

      if [[ "$next_weakness" == "W2" ]]; then
        local vercel_json="$HYO_ROOT/website/vercel.json"
        if [[ -f "$vercel_json" ]]; then
          result=$(python3 - "$vercel_json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    v = json.load(f)
has_kv = "stores" in str(v) or "kv" in str(v).lower()
if has_kv:
    print("Vercel KV already appears configured in vercel.json")
else:
    print("No KV configuration in vercel.json — kv-store.js will add KV wrapper with in-memory fallback")
PYEOF
) || result="Could not parse vercel.json"
          executed=true
        else
          result="vercel.json not found — kv-store.js will add KV wrapper with in-memory fallback"
          executed=true
        fi
      fi

      if [[ "$next_weakness" == "W3" ]]; then
        local api_dir="$HYO_ROOT/website/api"
        if [[ -d "$api_dir" ]]; then
          result=$(python3 - "$api_dir" <<'PYEOF'
import os, glob, sys
api_dir = sys.argv[1]
files = glob.glob(os.path.join(api_dir, "**", "*.js"), recursive=True)
no_trycatch = [os.path.basename(f) for f in files
               if "try" not in open(f).read() and "catch" not in open(f).read()]
if no_trycatch:
    print(f"{len(no_trycatch)}/{len(files)} API files lack try/catch: {', '.join(no_trycatch[:5])}")
else:
    print(f"All {len(files)} API files have try/catch — audit will verify structured logging")
PYEOF
) || result="Could not scan API directory"
          executed=true
        fi
      fi
      ;;

    aether)
      # Diagnostic only — execution engine never called for Aether
      if [[ "$next_weakness" == "W1" ]]; then
        local log_dir="$HYO_ROOT/agents/aether/logs"
        if [[ -d "$log_dir" ]]; then
          result=$(python3 - "$log_dir" <<'PYEOF'
import glob, os, sys
log_dir = sys.argv[1]
logs = sorted(glob.glob(os.path.join(log_dir, "aether-*.log")))[-3:]
total_phantom = 0
for log in logs:
    try:
        with open(log) as f:
            phantoms = sum(1 for line in f if "POS WARNING" in line)
        total_phantom += phantoms
        if phantoms > 0:
            print(f"  {os.path.basename(log)}: {phantoms} phantom warnings")
    except Exception:
        pass
print(f"Total phantom warnings (last 3 days): {total_phantom}")
if total_phantom > 10:
    print("URGENT: Phantom rate is high")
PYEOF
) || result="Could not scan aether logs"
          executed=true
        fi
      fi
      ;;

    dex)
      if [[ "$next_weakness" == "W1" ]]; then
        result=$(python3 - "$HYO_ROOT" <<'PYEOF'
import glob, json, os, sys
root = sys.argv[1]
ledgers = glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)
corrupt = 0
fixable = 0
for ledger in ledgers[:50]:  # cap at 50 for speed
    try:
        with open(ledger) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    json.loads(line)
                except Exception:
                    corrupt += 1
                    if line.endswith("}{") or line.count("{") != line.count("}"):
                        fixable += 1
    except Exception:
        pass
print(f"Scanned {len(ledgers)} JSONL files (sampled 50).")
print(f"Found {corrupt} corrupt entries ({fixable} likely auto-fixable).")
PYEOF
) || result="Could not scan JSONL files"
        executed=true
      fi

      if [[ "$next_weakness" == "W2" ]]; then
        local ki_file="$HYO_ROOT/kai/ledger/known-issues.jsonl"
        if [[ -f "$ki_file" ]]; then
          result=$(python3 - "$ki_file" <<'PYEOF'
import json, sys
from collections import Counter
clusters = Counter()
with open(sys.argv[1]) as f:
    for line in f:
        try:
            e = json.loads(line.strip())
            src = e.get("source", e.get("agent", "unknown"))
            cat = e.get("category", e.get("type", "uncategorized"))
            clusters[f"{src}/{cat}"] += 1
        except Exception:
            pass
print(f"Root cause clusters ({sum(clusters.values())} total issues):")
for cluster, count in clusters.most_common(8):
    print(f"  {cluster}: {count}")
PYEOF
) || result="Could not cluster known issues"
          executed=true
        fi
      fi

      if [[ "$next_weakness" == "W3" ]]; then
        result="Constitution drift detector not yet built — constitution-drift.py will verify agent log compliance against CLAUDE.md rules"
        executed=true
      fi
      ;;
  esac

  # ── Report diagnostic results ──────────────────────────────────────────────
  if [[ "$executed" == true && -n "$result" ]]; then
    growth_log "$agent" "Diagnostic result:"
    echo "$result" | while read -r line; do
      growth_log "$agent" "  $line"
    done

    # Update GROWTH.md growth log
    local today_date
    today_date=$(TZ="America/Denver" date +%Y-%m-%d)
    local short_result
    short_result=$(echo "$result" | head -1 | cut -c1-80)
    if grep -q "## Growth Log" "$growth_file" 2>/dev/null; then
      echo "| $today_date | $next_ticket ($next_weakness): $short_result | Automated assessment → execution |" >> "$growth_file"
      growth_log "$agent" "Updated GROWTH.md growth log"
    fi

    # ── Dead-Loop Circuit Breaker (Phase 7.5 pre-check) ──────────────────
    # Before executing: record this cycle in the dead-loop detector ring buffer.
    # If we're producing the same fingerprint 3+ times without state change,
    # the agent is cognitively entrenched — inject probe or hard stop.
    # Based on: arXiv:2512.02731 (GVU Variance Inequality), TokenFence.dev circuit breaker.
    local dead_loop_script="$HYO_ROOT/bin/dead-loop-detector.py"
    if [[ -f "$dead_loop_script" ]]; then
      local content_hash
      content_hash=$(echo "$result" | md5sum | cut -c1-12 2>/dev/null || echo "nohash")
      local fp_json
      fp_json=$(python3 -c "import json; print(json.dumps({'weakness_id':'${next_weakness}','action_type':'execute_improvement','content_hash':'${content_hash}','improvement_status':'running','files_changed':[]}))")
      local dl_exit=0
      python3 "$dead_loop_script" record "$agent" "$fp_json" || dl_exit=$?
      if [[ "$dl_exit" -eq 3 ]]; then
        growth_log "$agent" "HARD STOP: dead-loop circuit breaker triggered — skipping execution. Agent must produce text summary before next tool use."
        return 1
      elif [[ "$dl_exit" -eq 4 ]]; then
        growth_log "$agent" "ESCALATE: $agent has had 3+ null-progress cycles — escalated to Hyo inbox. Halting."
        return 1
      elif [[ "$dl_exit" -eq 2 ]]; then
        growth_log "$agent" "WARN: dead-loop probe injected — same cycle pattern detected. Proceeding with caution."
        result="[DEAD-LOOP PROBE] What information is missing that would change the assessment? What external signal would confirm or refute the current plan? ORIGINAL RESULT: $result"
      fi
    fi

    # ── Execute the improvement via Claude API ─────────────────────────────
    # This is the critical step that converts "research theater" into real code.
    # Aether is excluded by design (handled inside execute_next_improvement).
    execute_next_improvement "$agent" "$next_ticket" "$next_title" "$next_weakness" "$result"

  else
    growth_log "$agent" "No executable steps for current ticket ($next_ticket) — needs mapping extension or Kai session"
  fi

  growth_log "$agent" "Growth phase complete"
}
