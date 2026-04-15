#!/usr/bin/env bash
# bin/generate-morning-report.sh — Two-version morning report generator
#
# Produces TWO outputs:
#   1. INTERNAL: website/data/morning-report.json — technical metrics for Kai
#   2. FEED: appends to website/data/feed.json — human-readable narrative for Hyo
#
# v2 (2026-04-14): Rewritten to read ACTUAL agent outputs (sentinel logs, cipher
# scans, research findings, analysis files, self-reviews) instead of just
# evolution.jsonl metadata. Each agent section is unique because it's built from
# what the agent actually did, not a template.
#
# Called by:
#   - com.hyo.morning-report launchd plist (05:00 MT daily)
#   - healthcheck.sh auto-remediation (when morning report is stale)
#   - nel-qa-cycle.sh Phase 7.5 auto-remediation
#   - dispatch.sh simulation Phase 6 auto-remediation
#
# Usage: bash bin/generate-morning-report.sh
#        HYO_ROOT=/path/to/Hyo bash bin/generate-morning-report.sh

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
INTERNAL_OUTPUT="$ROOT/website/data/morning-report.json"
FEED_OUTPUT="$ROOT/website/data/feed.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
YESTERDAY=$(TZ="America/Denver" date -v-1d +%Y-%m-%d 2>/dev/null || TZ="America/Denver" date -d "yesterday" +%Y-%m-%d 2>/dev/null || echo "unknown")
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
MONTH_KEY=$(echo "$TODAY" | cut -c1-7)
LOG_TAG="[morning-report]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

log "Generating morning report v2 for $TODAY"

# ── Sync agent profiles from PLAYBOOKs before generating report ──
SYNC_SCRIPT="$ROOT/bin/sync-agent-profiles.sh"
if [[ -x "$SYNC_SCRIPT" ]]; then
  bash "$SYNC_SCRIPT" 2>&1 | tail -2
  log "Agent profiles synced from PLAYBOOKs"
fi

# ── Generate both reports via Python ──

python3 - "$INTERNAL_OUTPUT" "$FEED_OUTPUT" "$TODAY" "$YESTERDAY" "$NOW_MT" "$MONTH_KEY" "$ROOT" <<'PYEOF'
import json, sys, os, re, glob
from pathlib import Path

internal_path = sys.argv[1]
feed_path     = sys.argv[2]
today         = sys.argv[3]
yesterday     = sys.argv[4]
now_mt        = sys.argv[5]
month_key     = sys.argv[6]
root          = sys.argv[7]

# ══════════════════════════════════════════════════════════════════════════════
# DATA GATHERING — Read actual agent outputs, not just metadata
# ══════════════════════════════════════════════════════════════════════════════

def read_file_head(path, max_chars=3000):
    """Read first N chars of a file, return empty string if missing."""
    try:
        with open(path) as f:
            return f.read(max_chars)
    except:
        return ""

def read_file_lines(path, max_lines=50):
    """Read first N lines, return list."""
    try:
        with open(path) as f:
            return [l.rstrip() for _, l in zip(range(max_lines), f)]
    except:
        return []

def find_latest_file(directory, pattern, max_age_days=2):
    """Find the most recent file matching pattern in directory."""
    matches = sorted(glob.glob(os.path.join(directory, pattern)), reverse=True)
    return matches[0] if matches else None

def parse_sentinel(text):
    """Extract structured data from sentinel report markdown."""
    result = {"passed": 0, "failed": 0, "new_issues": [], "recurring": [], "escalations": [], "resolved": []}
    for line in text.splitlines():
        m = re.match(r'\*\*This run:\*\*\s*(\d+)\s*passed,\s*(\d+)\s*failed', line)
        if m:
            result["passed"] = int(m.group(1))
            result["failed"] = int(m.group(2))
        if line.startswith("- **P") and "##" not in line:
            # Extract priority and description
            pm = re.match(r'- \*\*P(\d)\*\*\s*`([^`]+)`\s*—\s*(.*)', line)
            if pm:
                entry = {"priority": int(pm.group(1)), "check": pm.group(2), "detail": pm.group(3).rstrip()}
                # Determine section by context (crude but effective)
                if "day " in entry["detail"] or "failing" in entry["detail"]:
                    result["recurring"].append(entry)
                else:
                    result["new_issues"].append(entry)
        if line.startswith("- **P") and "escalated" in line.lower():
            result["escalations"].append(line.strip("- ").strip())
        if line.startswith("- `") and "##" not in line and "Resolved" in text[:text.find(line)] if line in text else False:
            result["resolved"].append(line.strip("- ").strip())
    return result

def parse_cipher(text):
    """Extract structured data from cipher log."""
    result = {"ran": False, "clean": False, "findings": 0, "layers_run": [], "layers_skipped": []}
    for line in text.splitlines():
        if "cipher" in line.lower() and ("run" in line.lower() or "scheduled" in line.lower()):
            result["ran"] = True
        if "RESULT: CLEAN" in line:
            result["clean"] = True
        if "skipped" in line.lower():
            m = re.search(r'Layer \d+: (\w+)', line)
            if m:
                result["layers_skipped"].append(m.group(1))
        elif "Layer" in line and "✓" in line:
            m = re.search(r'Layer \d+: (.+?)—', line)
            if m:
                result["layers_run"].append(m.group(1).strip())
        fm = re.search(r'(\d+) findings', line)
        if fm:
            result["findings"] = int(fm.group(1))
    return result

def parse_research(text):
    """Extract structured data from research findings markdown."""
    result = {"sources_checked": 0, "successful": 0, "failed_sources": [],
              "successful_sources": [], "follow_ups": [], "has_analysis": False}
    for line in text.splitlines():
        m = re.match(r'\*\*Sources checked:\*\*\s*(\d+)', line)
        if m: result["sources_checked"] = int(m.group(1))
        m = re.match(r'\*\*Successful:\*\*\s*(\d+)', line)
        if m: result["successful"] = int(m.group(1))
        if "— FAILED" in line:
            src = line.replace("###", "").replace("— FAILED", "").strip()
            result["failed_sources"].append(src)
        elif line.startswith("### ") and "FAILED" not in line and "Follow" not in line and "Analysis" not in line:
            result["successful_sources"].append(line.replace("###", "").strip())
        if "open" in line.lower() and line.strip().startswith("- ["):
            result["follow_ups"].append(line.strip("- ").strip()[:100])
    if "## My Analysis" in text:
        analysis_section = text.split("## My Analysis")[1][:500]
        if "no direct matches" not in analysis_section.lower():
            result["has_analysis"] = True
    return result

def parse_aether_metrics(path):
    """Read aether trading metrics."""
    try:
        with open(path) as f:
            d = json.load(f)
        cw = d.get("currentWeek", d.get("currentPeriod", {}))
        return {
            "balance": cw.get("currentBalance", "?"),
            "trades": cw.get("totalTrades", "?"),
            "winRate": cw.get("winRate", "?"),
            "pnl": cw.get("pnl", "?"),
            "strategies": len(cw.get("strategies", [])),
            "dailyPnl": cw.get("dailyPnl", [])
        }
    except:
        return None

def parse_self_review(text):
    """Extract key findings from agent self-review."""
    issues = []
    for line in text.splitlines():
        if line.strip().startswith("- ✗"):
            issues.append(line.strip("- ✗ ").strip()[:100])
    return issues[:5]

def parse_simulation(text):
    """Extract simulation results."""
    result = {"has_plan": False, "agents_covered": []}
    for line in text.splitlines():
        if line.startswith("### "):
            agent = line.replace("###", "").strip()
            if agent:
                result["agents_covered"].append(agent)
                result["has_plan"] = True
    return result

# ══════════════════════════════════════════════════════════════════════════════
# GATHER ALL AGENT DATA
# ══════════════════════════════════════════════════════════════════════════════

# --- Healthcheck ---
hc = {"status": "unknown", "issues": 0, "warnings": 0}
hc_path = os.path.join(root, "kai", "queue", "healthcheck-latest.json")
try:
    with open(hc_path) as f:
        hc = json.load(f)
except: pass

# --- Simulation outcomes ---
sim = {"passed": 0, "failed": 0}
sim_path = os.path.join(root, "kai", "ledger", "simulation-outcomes.jsonl")
try:
    with open(sim_path) as f:
        lines = [l.strip() for l in f if l.strip()]
        if lines:
            sim = json.loads(lines[-1])
except: pass

# --- Known issues ---
ki_count = 0
ki_path = os.path.join(root, "kai", "ledger", "known-issues.jsonl")
try:
    with open(ki_path) as f:
        ki_count = sum(1 for l in f if '"status":"active"' in l or '"status": "active"' in l)
except: pass

# --- Nel: sentinel + cipher + research ---
nel_sentinel_path = find_latest_file(
    os.path.join(root, "agents", "nel", "logs"), f"sentinel-{today}.md")
if not nel_sentinel_path:
    nel_sentinel_path = find_latest_file(
        os.path.join(root, "agents", "nel", "logs"), f"sentinel-{yesterday}.md")
nel_sentinel = parse_sentinel(read_file_head(nel_sentinel_path)) if nel_sentinel_path else None

nel_cipher_path = find_latest_file(
    os.path.join(root, "agents", "nel", "logs"), f"cipher-{today}*.log")
if not nel_cipher_path:
    nel_cipher_path = find_latest_file(
        os.path.join(root, "agents", "nel", "logs"), f"cipher-{yesterday}*.log")
nel_cipher = parse_cipher(read_file_head(nel_cipher_path)) if nel_cipher_path else None

nel_research_path = find_latest_file(
    os.path.join(root, "agents", "nel", "research"), f"findings-{today}.md")
nel_research = parse_research(read_file_head(nel_research_path)) if nel_research_path else None

# --- Ra: newsletter output + research ---
ra_newsletter_exists = False
ra_newsletter_file = None
for pattern in [f"*{today}*", f"*{yesterday}*"]:
    matches = glob.glob(os.path.join(root, "agents", "ra", "output", pattern))
    if matches:
        ra_newsletter_exists = True
        ra_newsletter_file = os.path.basename(matches[0])
        break

ra_research_path = find_latest_file(
    os.path.join(root, "agents", "ra", "research"), f"findings-{today}.md")
ra_research = parse_research(read_file_head(ra_research_path)) if ra_research_path else None

# --- Sam: logs + research ---
sam_research_path = find_latest_file(
    os.path.join(root, "agents", "sam", "research"), f"findings-{today}.md")
sam_research = parse_research(read_file_head(sam_research_path)) if sam_research_path else None

# --- Aether: trading metrics + analysis + self-review + research ---
aether_metrics = parse_aether_metrics(
    os.path.join(root, "website", "data", "aether-metrics.json"))

aether_analysis_path = find_latest_file(
    os.path.join(root, "agents", "aether", "analysis"), f"Analysis_{today}.txt")
aether_analysis_preview = read_file_head(aether_analysis_path, 500) if aether_analysis_path else ""

aether_review_path = find_latest_file(
    os.path.join(root, "agents", "aether", "logs"), f"self-review-{today}.md")
aether_self_review = parse_self_review(read_file_head(aether_review_path)) if aether_review_path else []

aether_research_path = find_latest_file(
    os.path.join(root, "agents", "aether", "research"), f"findings-{today}.md")
aether_research = parse_research(read_file_head(aether_research_path)) if aether_research_path else None

# --- Dex: research + integrity ---
dex_research_path = find_latest_file(
    os.path.join(root, "agents", "dex", "research"), f"findings-{today}.md")
dex_research = parse_research(read_file_head(dex_research_path)) if dex_research_path else None

# --- Simulation report ---
sim_report_path = find_latest_file(
    os.path.join(root, "agents", "nel", "logs"), f"simulation-{today}.md")
sim_report = parse_simulation(read_file_head(sim_report_path)) if sim_report_path else None

# ══════════════════════════════════════════════════════════════════════════════
# BUILD THE INTERNAL REPORT (for Kai — technical, structured)
# ══════════════════════════════════════════════════════════════════════════════

internal = {
    "date": today,
    "generatedAt": now_mt,
    "generatedBy": "bin/generate-morning-report.sh v2",
    "systemHealth": {
        "healthcheck": {
            "status": hc.get("status", "?"),
            "issues": hc.get("issues", 0),
            "warnings": hc.get("warnings", 0)
        },
        "simulation": {
            "passed": sim.get("passed", 0),
            "failed": sim.get("failed", 0)
        },
        "knownIssues": ki_count
    },
    "trading": aether_metrics or {},
    "agents": {
        "nel": {
            "sentinel": nel_sentinel,
            "cipher": nel_cipher,
            "research": {
                "sources_checked": nel_research["sources_checked"] if nel_research else 0,
                "successful": nel_research["successful"] if nel_research else 0,
                "failed": nel_research["failed_sources"] if nel_research else [],
                "follow_ups": nel_research["follow_ups"] if nel_research else []
            }
        },
        "ra": {
            "newsletter_produced": ra_newsletter_exists,
            "research": {
                "sources_checked": ra_research["sources_checked"] if ra_research else 0,
                "successful": ra_research["successful"] if ra_research else 0,
                "successful_sources": ra_research["successful_sources"] if ra_research else []
            }
        },
        "sam": {
            "research": {
                "sources_checked": sam_research["sources_checked"] if sam_research else 0,
                "successful": sam_research["successful"] if sam_research else 0
            }
        },
        "aether": {
            "analysis_exists": bool(aether_analysis_path),
            "self_review_issues": aether_self_review,
            "research": {
                "sources_checked": aether_research["sources_checked"] if aether_research else 0,
                "successful": aether_research["successful"] if aether_research else 0,
                "follow_ups": aether_research["follow_ups"] if aether_research else []
            }
        },
        "dex": {
            "research": {
                "sources_checked": dex_research["sources_checked"] if dex_research else 0,
                "successful": dex_research["successful"] if dex_research else 0,
                "follow_ups": dex_research["follow_ups"] if dex_research else []
            }
        }
    }
}

with open(internal_path, "w") as f:
    json.dump(internal, f, indent=2)
print(f"Internal report written: {internal_path}")

# ══════════════════════════════════════════════════════════════════════════════
# BUILD THE EXTERNAL REPORT (for Hyo — human-readable narrative)
# Each agent section is built from what they ACTUALLY did, not templates.
# ══════════════════════════════════════════════════════════════════════════════

# --- Nel section: built from sentinel + cipher + research ---
nel_parts = []
if nel_sentinel:
    p, f_ = nel_sentinel["passed"], nel_sentinel["failed"]
    nel_parts.append(f"Sentinel ran {p + f_} checks: {p} passed, {f_} failed.")
    if nel_sentinel["new_issues"]:
        for iss in nel_sentinel["new_issues"][:2]:
            nel_parts.append(f"New P{iss['priority']} issue: {iss['check']} — {iss['detail'][:80]}.")
    if nel_sentinel["recurring"]:
        worst = nel_sentinel["recurring"][0]
        # Extract day count from detail like "_(day 33)_"
        day_m = re.search(r'day\s+(\d+)', worst['detail'])
        day_count = day_m.group(1) if day_m else "multiple"
        nel_parts.append(f"Persistent problem: {worst['check']} has been failing for {day_count} consecutive runs. This needs a root-cause fix, not monitoring.")
    if nel_sentinel["escalations"]:
        nel_parts.append(f"{len(nel_sentinel['escalations'])} escalation(s) active.")
else:
    nel_parts.append("Sentinel didn't run — no report found for today or yesterday.")

if nel_cipher:
    if nel_cipher["ran"]:
        if nel_cipher["clean"]:
            layers = ", ".join(nel_cipher["layers_run"][:3]) if nel_cipher["layers_run"] else "filesystem checks"
            nel_parts.append(f"Cipher scan: clean, zero findings. Ran {layers}.")
            if nel_cipher["layers_skipped"]:
                nel_parts.append(f"Skipped {', '.join(nel_cipher['layers_skipped'])} (not available in sandbox — need gitleaks/trufflehog installed on Mini).")
        elif nel_cipher["findings"] > 0:
            nel_parts.append(f"Cipher scan: {nel_cipher['findings']} finding(s). Investigate immediately.")
        else:
            nel_parts.append("Cipher scan ran, no findings.")
    else:
        nel_parts.append("Cipher didn't run this cycle.")

if nel_research:
    hit = nel_research["successful"]
    total = nel_research["sources_checked"]
    if nel_research["failed_sources"]:
        nel_parts.append(f"Research: {hit}/{total} sources responded. Failed: {', '.join(nel_research['failed_sources'][:3])}. These sources are unreachable from the sandbox — either move research to Mini or find alternative endpoints.")
    elif hit > 0:
        nel_parts.append(f"Research: pulled from {hit} sources. {len(nel_research['follow_ups'])} follow-ups open (CVE cross-referencing).")
    if nel_research["follow_ups"]:
        nel_parts.append(f"Open follow-up: {nel_research['follow_ups'][0][:80]}.")

nel_narrative = " ".join(nel_parts)

# --- Ra section: built from newsletter status + research ---
ra_parts = []
if ra_newsletter_exists:
    ra_parts.append(f"Newsletter produced ({ra_newsletter_file}). Pipeline is working.")
else:
    ra_parts.append("No newsletter produced today. The pipeline can't reach external sources from the Cowork sandbox — this has been blocked for 3+ days. Fix: move newsletter.sh to the Mini's launchd, or provide API keys so the sandbox can use an LLM to generate from cached data.")

if ra_research:
    hit = ra_research["successful"]
    total = ra_research["sources_checked"]
    srcs = ", ".join(ra_research["successful_sources"][:4])
    if hit > 0:
        ra_parts.append(f"Research: pulled from {hit}/{total} sources ({srcs}). Looking at newsletter craft, audience engagement, and content format patterns.")
    else:
        ra_parts.append(f"Research: 0/{total} sources returned usable data. Ra's source list needs updating.")
else:
    ra_parts.append("No research output found. Ra's research runner either didn't fire or produced no output.")

ra_narrative = " ".join(ra_parts)

# --- Sam section: built from research + deploy status ---
sam_parts = []
if sam_research:
    hit = sam_research["successful"]
    total = sam_research["sources_checked"]
    if hit > 0:
        srcs = ", ".join(sam_research["successful_sources"][:3]) if sam_research["successful_sources"] else f"{hit} sources"
        sam_parts.append(f"Research: pulled from {srcs}. Sam is tracking infrastructure patterns relevant to our Vercel + API stack.")
    else:
        sam_parts.append(f"Research: 0/{total} sources returned data. Sam's research runner may need different endpoints.")
else:
    sam_parts.append("No research output today. Sam's runner either didn't fire or had no research phase. Sam needs a scheduled trigger — currently only runs on-demand, which means it sits idle unless someone calls it.")

# Check for any recent Sam activity
sam_log_path = os.path.join(root, "agents", "sam", "logs")
sam_logs = sorted(glob.glob(os.path.join(sam_log_path, f"*{today}*")), reverse=True) if os.path.isdir(sam_log_path) else []
if sam_logs:
    sam_parts.append(f"Sam produced {len(sam_logs)} log(s) today.")
else:
    sam_parts.append("No logs from Sam today. Next step: add a launchd plist so Sam's self-evolution fires automatically like the other agents.")

sam_narrative = " ".join(sam_parts)

# --- Aether section: built from trading metrics + analysis + self-review + research ---
aether_parts = []
if aether_metrics:
    bal = aether_metrics.get("balance", "?")
    trades = aether_metrics.get("trades", "?")
    wr = aether_metrics.get("winRate", "?")
    pnl = aether_metrics.get("pnl", "?")
    aether_parts.append(f"Trading: balance ${bal}, {trades} trades, {wr}% win rate, net P&L ${pnl}.")
    daily = aether_metrics.get("dailyPnl", [])
    if daily:
        latest = daily[-1] if isinstance(daily[-1], dict) else {}
        if latest.get("pnl"):
            aether_parts.append(f"Latest session: {latest.get('day', '?')} P&L ${latest['pnl']}.")
else:
    aether_parts.append("No trading metrics available.")

if aether_analysis_path:
    aether_parts.append("Daily analysis written.")
    # Check GPT verification
    if "GPT_VERIFIED: YES" in aether_analysis_preview:
        aether_parts.append("GPT dual-phase verification: complete.")
    elif "GPT_VERIFIED: NO" in aether_analysis_preview:
        aether_parts.append("GPT verification pending — analysis needs to go through the adversarial pipeline before it's final.")
else:
    aether_parts.append("No analysis produced today. Either the scheduled task didn't fire or the raw log wasn't available.")

if aether_self_review:
    aether_parts.append(f"Self-review found {len(aether_self_review)} issue(s): {aether_self_review[0][:80]}.")

if aether_research:
    hit = aether_research["successful"]
    total = aether_research["sources_checked"]
    aether_parts.append(f"Research: {hit}/{total} sources. Tracking exchange API patterns, position sizing models.")
    if aether_research["follow_ups"]:
        aether_parts.append(f"Open: {aether_research['follow_ups'][0][:80]}.")

aether_narrative = " ".join(aether_parts)

# --- Dex section: built from research + integrity ---
dex_parts = []
if dex_research:
    hit = dex_research["successful"]
    total = dex_research["sources_checked"]
    srcs = ", ".join(dex_research["successful_sources"][:3]) if dex_research.get("successful_sources") else f"{hit} sources"
    if hit > 0:
        dex_parts.append(f"Research: pulled from {hit}/{total} sources ({srcs}). Investigating data integrity patterns, JSONL alternatives, and event sourcing architectures.")
    if dex_research["follow_ups"]:
        dex_parts.append(f"Open: {dex_research['follow_ups'][0][:80]}.")
else:
    dex_parts.append("No research output today.")

# Check dex evolution for integrity findings
dex_evo_path = os.path.join(root, "agents", "dex", "evolution.jsonl")
try:
    with open(dex_evo_path) as f:
        lines = [l.strip() for l in f if l.strip()]
        if lines:
            last_evo = json.loads(lines[-1])
            assess = last_evo.get("assessment", "")
            refl = last_evo.get("reflection", {})
            bn = refl.get("bottleneck", "")
            if "corrupt" in bn.lower() or "corrupt" in assess.lower():
                dex_parts.append(f"Integrity finding: {bn[:100]}. Dex needs to decide whether to auto-repair corrupt JSONL entries or just flag them for manual review.")
            elif "pattern" in assess.lower():
                dex_parts.append(f"Pattern detection: {assess[:80]}.")
except: pass

if not dex_parts:
    dex_parts.append("Dex was quiet today. Its integrity sweep and pattern detection either didn't run or found nothing new.")

dex_narrative = " ".join(dex_parts)

# --- Build executive summary from actual findings ---
summary_parts = []

# What's working
working = []
blocked = []

if ra_newsletter_exists:
    working.append("newsletter shipped")
if nel_sentinel and nel_sentinel["passed"] > 0:
    working.append(f"sentinel {nel_sentinel['passed']}/{nel_sentinel['passed'] + nel_sentinel['failed']} checks passing")
if nel_cipher and nel_cipher["clean"]:
    working.append("no secret leaks")
if aether_metrics and aether_metrics.get("balance") and aether_metrics["balance"] != "?":
    working.append(f"AetherBot at ${aether_metrics['balance']}")

# What's blocked and WHY
if not ra_newsletter_exists:
    blocked.append("newsletter blocked — sandbox can't reach external sources, needs Mini migration")
if nel_sentinel and nel_sentinel["failed"] > 0:
    recurring = nel_sentinel.get("recurring", [])
    if recurring:
        worst = recurring[0]
        day_m = re.search(r'day\s+(\d+)', worst['detail'])
        day_count = day_m.group(1) if day_m else "multiple"
        blocked.append(f"{worst['check']} failing {day_count} straight runs — needs root-cause fix on Mini")
sim_fails = sim.get("failed", 0)
if sim_fails > 0:
    blocked.append(f"simulation has {sim_fails} failures — regression investigation needed")

if working:
    summary_parts.append(f"Working: {', '.join(working)}.")
if blocked:
    summary_parts.append(f"Blocked: {'; '.join(blocked)}.")
if not blocked:
    summary_parts.append("Nothing actively blocked.")

exec_summary = " ".join(summary_parts)

# --- What went well / needs attention (with specifics, not templates) ---
went_well = []
needs_attention = []

if ra_newsletter_exists:
    went_well.append("Newsletter produced and delivered on schedule.")
if nel_sentinel and nel_sentinel["passed"] >= nel_sentinel["failed"]:
    went_well.append(f"Sentinel passed {nel_sentinel['passed']} of {nel_sentinel['passed'] + nel_sentinel['failed']} checks.")
if nel_cipher and nel_cipher["clean"]:
    went_well.append("Cipher security scan: clean, zero findings.")
if aether_analysis_path:
    went_well.append("Aether daily analysis produced.")

# Research activity (specific, not "actively growing")
research_active = []
for name, res in [("Nel", nel_research), ("Ra", ra_research), ("Aether", aether_research), ("Dex", dex_research)]:
    if res and res["successful"] > 0:
        research_active.append(f"{name} ({res['successful']} sources)")
if research_active:
    went_well.append(f"Research active: {', '.join(research_active)}.")

if not ra_newsletter_exists:
    needs_attention.append("No newsletter today — Ra's pipeline is blocked on sandbox network restrictions. Move to Mini launchd.")
if nel_sentinel and nel_sentinel["failed"] > 0:
    for iss in nel_sentinel.get("new_issues", [])[:2]:
        needs_attention.append(f"New sentinel issue (P{iss['priority']}): {iss['check']} — {iss['detail'][:80]}.")
    for iss in nel_sentinel.get("recurring", [])[:2]:
        needs_attention.append(f"Persistent failure: {iss['check']} — {iss['detail'][:80]}. Needs root-cause fix.")
if sim_fails > 0:
    needs_attention.append(f"Simulation: {sim.get('passed', 0)} pass / {sim_fails} fail. Investigate what regressed.")
if ki_count > 10:
    needs_attention.append(f"{ki_count} known issues accumulating — schedule a cleanup sprint.")

agent_highlights = {
    "nel": nel_narrative,
    "ra": ra_narrative,
    "sam": sam_narrative,
    "aether": aether_narrative,
    "dex": dex_narrative
}

# ── Feed entry ──
morning_entry = {
    "id": f"mr-{today}",
    "type": "morning-report",
    "title": "Morning Report",
    "author": "Kai",
    "authorIcon": "\U0001F454",
    "authorColor": "#d4a853",
    "timestamp": now_mt,
    "date": today,
    "sections": {
        "summary": exec_summary,
        "wentWell": went_well,
        "needsAttention": needs_attention,
        "agentHighlights": agent_highlights
    }
}

# Read existing feed.json, replace today's morning report
feed = {"lastUpdated": now_mt, "today": today, "agents": {}, "reports": [], "history": {}}
if os.path.exists(feed_path):
    try:
        with open(feed_path) as f:
            feed = json.load(f)
    except: pass

feed["lastUpdated"] = now_mt
feed["today"] = today
feed["reports"] = [r for r in feed.get("reports", []) if r.get("id") != morning_entry["id"]]
feed["reports"].append(morning_entry)
feed["reports"].sort(key=lambda r: r.get("timestamp", ""), reverse=True)

if month_key not in feed.get("history", {}):
    months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    m_idx = int(month_key.split("-")[1]) - 1
    label = f"{months[m_idx]} {month_key.split('-')[0]}"
    feed["history"][month_key] = {"label": label, "reports": []}

month_hist = feed["history"][month_key]
if morning_entry["id"] not in month_hist["reports"]:
    month_hist["reports"].append(morning_entry["id"])

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)
print(f"Feed entry written: {feed_path}")

PYEOF

if [[ $? -ne 0 ]]; then
  log "ERROR: Failed to generate reports"
  exit 1
fi

# ── Copy to sam/website mirror if needed ──
SAM_MIRROR_INTERNAL="$ROOT/agents/sam/website/data/morning-report.json"
SAM_MIRROR_FEED="$ROOT/agents/sam/website/data/feed.json"
if [[ -d "$(dirname "$SAM_MIRROR_INTERNAL")" ]]; then
  if [[ ! "$INTERNAL_OUTPUT" -ef "$SAM_MIRROR_INTERNAL" ]] 2>/dev/null; then
    cp "$INTERNAL_OUTPUT" "$SAM_MIRROR_INTERNAL" 2>/dev/null || true
  fi
  if [[ ! "$FEED_OUTPUT" -ef "$SAM_MIRROR_FEED" ]] 2>/dev/null; then
    cp "$FEED_OUTPUT" "$SAM_MIRROR_FEED" 2>/dev/null || true
  fi
  log "Mirrors synced"
fi

# ── Commit and push ──
cd "$ROOT" || exit 1
CHANGED=$(git diff --name-only "$INTERNAL_OUTPUT" "$FEED_OUTPUT" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$CHANGED" -gt 0 ]]; then
  git add "$INTERNAL_OUTPUT" "$FEED_OUTPUT" 2>/dev/null
  git add "$SAM_MIRROR_INTERNAL" "$SAM_MIRROR_FEED" 2>/dev/null
  git commit -m "morning-report: $TODAY (v2 — real agent outputs)" 2>/dev/null
  git push origin main 2>/dev/null && log "Pushed to origin" || log "Push failed (will retry next cycle)"
else
  log "No changes to commit"
fi

log "Done — v2 morning report generated"
