#!/usr/bin/env bash
# bin/generate-morning-report-v7.sh — CEO Briefing (v7)
# Replaces v6-action-engine with a CEO-audience 5-section report.
#
# WHAT THIS REPORTS:
#   1. PULSE       — Health: Healthy / Degraded / Down (1 line)
#   2. IMPROVED    — Agents where a metric moved since last cycle (before → after)
#   3. BUILDING    — Active improvements in progress per agent
#   4. AETHER      — Top financial signal (Mon-Fri only)
#   5. ATTENTION   — P0 items needing Hyo's decision (zero most days)
#
# WHAT THIS DELIBERATELY OMITS:
#   - SICQ/OMP scores        (Kai's internal monitoring)
#   - Failed check details   (Kai resolves silently)
#   - Research phase logs    (research ≠ improvement)
#   - Simulation warnings    (Kai's problem)
#   - Stale data warnings    (Kai's problem)
#   - What agents "did"      (only what CHANGED)
#   - Kai daily report       (this IS Kai's report — no duplication)
#
# AUDIENCE: Hyo. CEO.
# PROTOCOL: kai/protocols/PROTOCOL_MORNING_REPORT.md v3.0
# CALLED BY: com.hyo.morning-report launchd plist (05:00 MT daily)

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
JSON_OUTPUT="$ROOT/website/data/morning-report.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
DOW=$(TZ="America/Denver" date +%u)  # 1=Mon … 7=Sun; 6=Sat, 7=Sun
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
LOG_TAG="[morning-report-v7]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

log "Generating CEO briefing v7 for $TODAY"

python3 - "$JSON_OUTPUT" "$TODAY" "$NOW_MT" "$ROOT" "$DOW" <<'PYEOF'
import json, sys, os, re, glob
from pathlib import Path
from datetime import datetime, timezone, timedelta

json_output_path = sys.argv[1]
today            = sys.argv[2]
now_mt           = sys.argv[3]
root             = sys.argv[4]
dow              = int(sys.argv[5])   # 1=Mon … 7=Sun

AGENTS = ["nel", "sam", "aether", "ra", "dex"]

# ── Helpers ────────────────────────────────────────────────────────────────────

def rj(path):
    try:
        with open(path) as f: return json.load(f)
    except: return None

def rt(path, max_chars=8000):
    try:
        with open(path) as f: return f.read(max_chars)
    except: return ""

# ── 1. PULSE — queue health ────────────────────────────────────────────────────

def get_pulse(root):
    now_epoch = datetime.now(timezone.utc).timestamp()

    # Check worker log freshness
    worker_log = os.path.join(root, "kai/queue/worker.log")
    if os.path.exists(worker_log):
        age_h = (now_epoch - os.path.getmtime(worker_log)) / 3600
        if age_h > 3:
            return "Down", f"Queue worker stalled {age_h:.1f}h — Kai is investigating."
    else:
        return "Down", "Queue worker log missing — Kai is investigating."

    # Check for stuck running tasks
    running_dir = os.path.join(root, "kai/queue/running")
    if os.path.isdir(running_dir):
        for fn in os.listdir(running_dir):
            if fn.endswith(".json"):
                age_h = (now_epoch - os.path.getmtime(os.path.join(running_dir, fn))) / 3600
                if age_h > 2:
                    return "Degraded", f"Task stuck in queue {age_h:.1f}h — Kai is resolving."

    return "Healthy", None

# ── 2. WHAT IMPROVED — shipped improvements with metric delta ──────────────────

def get_improved(root, agents):
    results = []
    for name in agents:
        card_path = os.path.join(root, f"agents/{name}/data/agent-card.json")
        aric_path = os.path.join(root, f"agents/{name}/research/aric-latest.json")

        # Prefer agent-card.json (nightly reflection output)
        card = rj(card_path)
        if card and card.get("date") == today:
            before = card.get("metric_before")
            after  = card.get("metric_after")
            if before is not None and after is not None and str(before) != str(after):
                results.append({
                    "agent":   name,
                    "metric":  card.get("metric_name", "metric"),
                    "before":  str(before),
                    "after":   str(after),
                    "what":    card.get("what_changed", ""),
                    "commit":  card.get("commit", ""),
                })
            continue

        # Fallback: ARIC aric-latest.json for shipped improvements
        aric = rj(aric_path)
        if not aric: continue
        imp = aric.get("improvement_built", {})
        if imp.get("status") != "shipped": continue
        mb = aric.get("metric_before", "")
        ma = aric.get("metric_after", "")
        if mb and ma and mb != ma and mb != "N/A":
            results.append({
                "agent":  name,
                "metric": "output metric",
                "before": mb,
                "after":  ma,
                "what":   imp.get("description", ""),
                "commit": imp.get("commit", ""),
            })

    return results

# ── 3. WHAT'S BEING BUILT — active improvements ────────────────────────────────

def get_building(root, agents):
    results = []
    for name in agents:
        aric_path = os.path.join(root, f"agents/{name}/research/aric-latest.json")
        growth_path = os.path.join(root, f"agents/{name}/GROWTH.md")
        card_path = os.path.join(root, f"agents/{name}/data/agent-card.json")

        # From agent-card next_target
        card = rj(card_path)
        if card and card.get("next_target"):
            nt = card["next_target"]
            if nt.get("how") or nt.get("metric"):
                results.append({
                    "agent": name,
                    "what":  nt.get("how", ""),
                    "target": f"{nt.get('metric','metric')}: → {nt.get('target','')}",
                })
                continue

        # From ARIC in-progress
        aric = rj(aric_path)
        if aric:
            imp = aric.get("improvement_built", {})
            status = imp.get("status", "")
            if status in ("in progress", "in_progress", "researched") and imp.get("description"):
                nt = aric.get("next_target", "")
                results.append({
                    "agent": name,
                    "what":  imp["description"],
                    "target": nt or "",
                })
                continue

        # From GROWTH.md active improvements
        growth = rt(growth_path, 6000)
        if growth:
            for m in re.finditer(r'### I\d: (.+)\n.*?(?:\*\*Status:\*\*\s*(\S+))?', growth, re.DOTALL):
                title  = m.group(1).strip()
                status = (m.group(2) or "").lower()
                if status in ("in progress", "building", "active", "researched"):
                    results.append({"agent": name, "what": title, "target": ""})
                    break

    return results

# ── 4. AETHER SIGNAL — top financial insight ──────────────────────────────────

def get_aether_signal(root, dow):
    # Mon-Fri only (dow 1-5)
    if dow > 5:
        return None

    # Find latest analysis file
    analysis_dir = os.path.join(root, "agents/aether/analysis")
    pattern = os.path.join(analysis_dir, f"Analysis_{today}.txt")
    if not os.path.exists(pattern):
        # Try yesterday
        yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
        pattern = os.path.join(analysis_dir, f"Analysis_{yesterday}.txt")
    if not os.path.exists(pattern):
        # Latest in directory
        files = sorted(glob.glob(os.path.join(analysis_dir, "Analysis_*.txt")), reverse=True)
        pattern = files[0] if files else None

    if not pattern or not os.path.exists(pattern):
        return None

    text = rt(pattern, 12000)
    if not text:
        return None

    # Extract the top signal — look for summary/conclusion sections
    signal = None
    for header in ["## Summary", "## Key Signal", "## Conclusion", "## Top Signal",
                   "**Summary**", "**Signal**", "**Key Finding**"]:
        idx = text.find(header)
        if idx >= 0:
            after = text[idx + len(header):idx + len(header) + 600].strip()
            lines = [l.strip() for l in after.split('\n') if l.strip() and not l.startswith('#')]
            signal = ' '.join(lines[:4])
            break

    if not signal:
        # Take first 3 non-empty lines after the header line
        lines = [l.strip() for l in text.split('\n') if l.strip() and not l.startswith('#')]
        signal = ' '.join(lines[:4]) if lines else None

    return signal[:600] if signal else None

# ── 5. YOUR ATTENTION — P0 items needing Hyo ─────────────────────────────────

def get_attention(root):
    results = []
    tickets_path = os.path.join(root, "kai/tickets/tickets.jsonl")
    if not os.path.exists(tickets_path):
        return results

    now_ts = datetime.now(timezone.utc).timestamp()
    with open(tickets_path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: t = json.loads(line)
            except: continue

            if t.get("status") not in ("ACTIVE", "OPEN"): continue

            # Only P0 tickets with hyo_action flag OR explicitly marked needs_hyo
            pri = t.get("priority", "")
            needs_hyo = t.get("needs_hyo", False) or t.get("hyo_action", False)

            if pri == "P0" and needs_hyo:
                results.append({
                    "what":     t.get("title", t.get("description", ""))[:120],
                    "why":      t.get("hyo_reason", "Requires Hyo authorization"),
                    "priority": "P0",
                    "ticket":   t.get("id", ""),
                })

    return results[:3]   # Cap at 3

# ── BUILD REPORT ──────────────────────────────────────────────────────────────

pulse_status, pulse_detail = get_pulse(root)
improved     = get_improved(root, AGENTS)
building     = get_building(root, AGENTS)
aether       = get_aether_signal(root, dow)
attention    = get_attention(root)

report = {
    "generated":   now_mt,
    "date":        today,
    "version":     "v7-ceo-briefing",
    "pulse": {
        "status": pulse_status,
        "detail": pulse_detail,
    },
    "improved":     improved,
    "building":     building,
    "aetherSignal": aether,
    "yourAttention": attention,
}

with open(json_output_path, "w") as f:
    json.dump(report, f, indent=2)

print(f"v7 report written: {json_output_path}")

# ── HUMAN-READABLE STDOUT ─────────────────────────────────────────────────────

print("\n" + "=" * 70)
print(f"MORNING BRIEFING — {today}")
print("=" * 70 + "\n")

# 1. PULSE
print(f"PULSE: {pulse_status}")
if pulse_detail:
    print(f"  {pulse_detail}")
print()

# 2. WHAT IMPROVED
print("WHAT IMPROVED")
if improved:
    for item in improved:
        label = item["agent"].capitalize()
        commit = f" (commit {item['commit']})" if item.get("commit") else ""
        print(f"  {label}: {item['before']} → {item['after']}.{commit}")
        if item.get("what"):
            print(f"    {item['what']}")
else:
    print("  No agents shipped an improvement overnight. All cycles in research phase.")
print()

# 3. WHAT'S BEING BUILT
in_progress = [b for b in building if b.get("what")]
if in_progress:
    print("WHAT'S BEING BUILT")
    for item in in_progress:
        label = item["agent"].capitalize()
        target = f" — {item['target']}" if item.get("target") else ""
        print(f"  {label}: {item['what']}{target}")
    print()

# 4. AETHER SIGNAL
if aether and dow <= 5:
    print("AETHER SIGNAL")
    # Wrap at ~70 chars
    words = aether.split()
    line = "  "
    for w in words:
        if len(line) + len(w) + 1 > 72:
            print(line)
            line = "  " + w + " "
        else:
            line += w + " "
    if line.strip():
        print(line)
    print()

# 5. YOUR ATTENTION
if attention:
    print("YOUR ATTENTION")
    for item in attention:
        print(f"  [{item['priority']}] {item['what']}")
        print(f"    Why Kai can't resolve: {item['why']}")
    print()

print("=" * 70)

PYEOF

if [[ $? -ne 0 ]]; then
  log "ERROR: report generation failed"
  exit 1
fi

# ── Sync to sam/website mirror ─────────────────────────────────────────────────
SAM_MIRROR="$ROOT/agents/sam/website/data/morning-report.json"
if [[ -d "$(dirname "$SAM_MIRROR")" ]]; then
  [[ ! "$JSON_OUTPUT" -ef "$SAM_MIRROR" ]] 2>/dev/null && cp "$JSON_OUTPUT" "$SAM_MIRROR" 2>/dev/null || true
  log "Mirror synced: $SAM_MIRROR"
fi

# ── Publish to feed.json ────────────────────────────────────────────────────────
FEED_JSON="$ROOT/website/data/feed.json"
if [[ -f "$FEED_JSON" ]] && [[ -f "$JSON_OUTPUT" ]]; then
  log "Publishing to feed.json..."
  python3 - "$FEED_JSON" "$JSON_OUTPUT" "$TODAY" "$NOW_MT" <<'FEED_PYEOF'
import json, sys, subprocess
from datetime import datetime

feed_path = sys.argv[1]
mr_path   = sys.argv[2]
today     = sys.argv[3]
now_mt    = sys.argv[4]

with open(feed_path)  as f: feed = json.load(f)
with open(mr_path)    as f: mr   = json.load(f)

reports = [r for r in feed.get("reports", [])
           if not (r.get("type") == "morning-report" and r.get("date") == today)]

pulse    = mr.get("pulse", {})
improved = mr.get("improved", [])
building = mr.get("building", [])
aether   = mr.get("aetherSignal")
attn     = mr.get("yourAttention", [])

# Build summary text (BLUF)
if pulse["status"] == "Down":
    summary = f"System down — {pulse.get('detail','')}."
elif pulse["status"] == "Degraded":
    summary = f"System degraded — {pulse.get('detail','')}."
elif improved:
    parts = [f"{i['agent'].capitalize()} improved ({i['before']} → {i['after']})" for i in improved[:2]]
    summary = " | ".join(parts) + "."
elif building:
    summary = f"{len(building)} agent(s) building — nothing shipped overnight."
else:
    summary = "No improvements shipped overnight."

sections = {
    "summary":       summary,
    "pulse":         pulse,
    "improved":      improved,
    "building":      building,
    "aetherSignal":  aether,
    "yourAttention": attn,
}

entry = {
    "id":          f"morning-report-kai-{today}-{datetime.now().strftime('%H%M%S')}",
    "type":        "morning-report",
    "title":       f"Morning Report — {today}",
    "author":      "Kai",
    "authorIcon":  "\U0001f454",
    "authorColor": "#d4a853",
    "timestamp":   now_mt,
    "date":        today,
    "sections":    sections,
}

reports.insert(0, entry)
feed["reports"]     = reports
feed["lastUpdated"] = now_mt

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)
    f.write("\n")

print(f"Published morning-report-kai-{today} to feed.json")
FEED_PYEOF

  SAM_FEED="$ROOT/agents/sam/website/data/feed.json"
  if [[ -d "$(dirname "$SAM_FEED")" ]]; then
    [[ ! "$FEED_JSON" -ef "$SAM_FEED" ]] 2>/dev/null && cp "$FEED_JSON" "$SAM_FEED" 2>/dev/null || true
    log "feed.json mirror synced"
  fi
fi

# ── Commit + push ──────────────────────────────────────────────────────────────
cd "$ROOT" || exit 1
rm -f .git/index.lock 2>/dev/null

SAM_FEED_JSON="$ROOT/agents/sam/website/data/feed.json"
if ! git diff --quiet HEAD -- "$JSON_OUTPUT" "$SAM_MIRROR" "$FEED_JSON" "$SAM_FEED_JSON" 2>/dev/null; then
  git add "$JSON_OUTPUT" "$SAM_MIRROR" "$FEED_JSON" "$SAM_FEED_JSON" 2>/dev/null || true
  if git commit -m "morning-report: $TODAY (v7 — CEO briefing)"; then
    git push origin main && log "Pushed."
  fi
fi

log "Done — v7 CEO briefing complete"
