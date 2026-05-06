#!/usr/bin/env bash
# bin/aether-publish-analysis.sh — Publish an aether-analysis entry to the HQ feed
#
# Reads an Analysis_YYYY-MM-DD.txt file, builds an aether-analysis feed entry
# (summary, trades, risk, balance, btc, readLink), and appends it to
# website/data/feed.json. Idempotent: if an entry with the same id already
# exists it is replaced.
#
# Usage:
#   bash bin/aether-publish-analysis.sh <date> <analysis-file>
#
# Example:
#   bash bin/aether-publish-analysis.sh 2026-04-15 \
#     /Users/kai/Documents/Projects/Hyo/agents/aether/analysis/Analysis_2026-04-15.txt

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FEED_LIVE="$ROOT/website/data/feed.json"
FEED_GIT="$ROOT/agents/sam/website/data/feed.json"

DATE="${1:?Usage: aether-publish-analysis.sh <YYYY-MM-DD> <analysis-file>}"
ANALYSIS_FILE="${2:?Missing analysis file path}"

if [[ ! -f "$ANALYSIS_FILE" ]]; then
  echo "ERROR: Analysis file not found: $ANALYSIS_FILE" >&2
  exit 1
fi

# ── PRE-PUBLISH GATE (hard block — no bypass) ─────────────────────────────
# Runs analysis-gate.py which enforces the 6 gates documented in PROTOCOL v2.5:
#   Gate 1: No bash/dollar corruption in title or balance
#   Gate 2: Trading log is the real AetherBot log (≥15 TICKER CLOSEs, ≥1000 lines)
#   Gate 3: All 3 required section markers present
#   Gate 4: GPT CRITIQUE is a synthesis, not a raw runner-log dump
#   Gate 5: Version references not stale
#   Gate 6: Trade breakdown has actual data
# If any gate fails: exit 1 and the publish script stops here.
GATE_SCRIPT="$ROOT/bin/analysis-gate.py"
if [[ -f "$GATE_SCRIPT" ]]; then
  echo "[gate] Running pre-publish gate..."
  python3 "$GATE_SCRIPT" "$DATE" "$ANALYSIS_FILE"
  GATE_RC=$?
  if [[ $GATE_RC -ne 0 ]]; then
    echo "[publish] BLOCKED by pre-publish gate (exit $GATE_RC). Fix the failures above." >&2
    exit $GATE_RC
  fi
else
  echo "[gate] WARN: analysis-gate.py not found at $GATE_SCRIPT — skipping gate" >&2
fi

NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
MONTH_KEY=$(echo "$DATE" | cut -c1-7)

# Generate entry via Python (reliable JSON handling + text extraction)
python3 - "$FEED_GIT" "$FEED_LIVE" "$DATE" "$NOW_MT" "$MONTH_KEY" "$ANALYSIS_FILE" <<'PYEOF'
import json, os, re, sys

feed_git, feed_live, date, now_mt, month_key, analysis_path = sys.argv[1:7]
entry_id = f"aether-analysis-{date}"

with open(analysis_path, "r", errors="replace") as f:
    text = f.read()

# Helper — extract a section between CLAUDE PRIMARY / GPT CRITIQUE / FINAL SYNTHESIS
def slice_section(t, start_markers, end_markers=None):
    start = -1
    for m in start_markers:
        i = t.find(m)
        if i >= 0:
            start = i + len(m)
            break
    if start < 0:
        return ""
    end = len(t)
    if end_markers:
        for m in end_markers:
            j = t.find(m, start)
            if j >= 0 and j < end:
                end = j
    return t[start:end].strip()

final = slice_section(text,
    ["=== FINAL SYNTHESIS ===", "FINAL SYNTHESIS", "Final Synthesis"],
    ["=== END", "END OF ANALYSIS"])
primary = slice_section(text,
    ["=== CLAUDE PRIMARY ANALYSIS ===", "CLAUDE PRIMARY ANALYSIS"],
    ["=== GPT CRITIQUE ===", "GPT CRITIQUE", "GPT Critique", "=== FINAL"])
if not primary:
    primary = text[:4000]

# Pick a summary — prefer the first 1-2 non-empty paragraphs of FINAL or PRIMARY
def first_para(t, limit=600):
    for p in re.split(r"\n\s*\n", t.strip()):
        p = p.strip()
        if len(p) > 60 and not p.startswith("==="):
            return p[:limit]
    return t[:limit].strip()

summary_src = final or primary

def clean_machine_headers(t):
    """Remove GPT pipeline machine headers (=====, Generated:, Tokens:, NOTE: independence).
    Keeps the substantive analytical content. Human-readable result."""
    lines = t.split('\n')
    cleaned = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        # Skip separator lines (=====, ------)
        if re.match(r'^[=\-]{10,}$', stripped):
            i += 1
            continue
        # Skip machine header lines at top of GPT sections
        if re.match(r'^(GPT-4o PHASE \d+|Generated:|Source:|Tokens:|Independence gate:|Kai analysis:|NOTE: This file was generated)', stripped):
            i += 1
            continue
        cleaned.append(line)
        i += 1
    return '\n'.join(cleaned).strip()

def first_meaningful_para(t, limit=900):
    """Extract first meaningful paragraph, skipping machine headers."""
    t = clean_machine_headers(t)
    for p in re.split(r"\n\s*\n", t.strip()):
        p = p.strip()
        if len(p) > 60 and not p.startswith("===") and not p.startswith("---"):
            return p[:limit]
    return t[:limit].strip()

summary = first_meaningful_para(summary_src, 900)

# Simple section extractors — scan known keywords in text
def grab_line(patterns, t, max_len=600):
    for pat in patterns:
        m = re.search(pat, t, re.IGNORECASE)
        if m:
            # capture from match start to end of paragraph
            start = m.start()
            end = t.find("\n\n", start)
            if end < 0:
                end = min(start + max_len, len(t))
            return t[start:end].strip()[:max_len]
    return ""

def grab_section(patterns, t, max_len=1500):
    """Like grab_line but captures multi-paragraph content: match to next === or PART header."""
    for pat in patterns:
        m = re.search(pat, t, re.IGNORECASE)
        if m:
            start = m.start()
            # find next section boundary (=== header or PART N: heading or CRITICAL RULES)
            end_m = re.search(r'\n={4,}|\nPART \d+[:\s]|\nCRITICAL RULES', t[start+len(m.group()):])
            if end_m:
                end = start + len(m.group()) + end_m.start()
            else:
                end = min(start + max_len, len(t))
            return t[start:end].strip()[:max_len]
    return ""

# Trades: look for both PART 2 (trade-by-trade ledger) AND PART 3 (strategy family performance)
# PART 2 is the per-trade log; PART 3 is the aggregated view — prefer whichever has more content
trades_p2 = grab_section([r"\*?\*?PART 2[:\s]+TRADE.BY.TRADE", r"TRADE.BY.TRADE LEDGER"], text)
trades_p3 = grab_section([r"\*?\*?PART 3[:\s]+(?:SESSION|STRATEGY)", r"STRATEGY FAMILY PERFORMANCE"], text)
# Pick the richer of the two; combine if both exist
if trades_p2 and trades_p3:
    trades = trades_p2[:800] + "\n\n" + trades_p3[:700]
else:
    trades = trades_p2 or trades_p3

# Risk: prefer FINAL SYNTHESIS risk section, fall back to primary text
risk_in_final = grab_section([r"RISK EXPOSURE", r"RISK ASSESSMENT"], final) if final else ""
risk = risk_in_final or grab_line([r"risk\b", r"phantom", r"harvest miss", r"stop(?:/harvest)? event"], text)

# Balance: prefer BALANCE LEDGER table at the end (FINAL SYNTHESIS), not the first raw mention
# Look for the balance table (markdown table or key-value format) in FINAL SYNTHESIS first
balance_in_final = ""
if final:
    # Try to grab the full balance ledger section from FINAL SYNTHESIS
    balance_in_final = grab_section([r"BALANCE LEDGER", r"BALANCE:"], final)
if not balance_in_final:
    # Fall back to any balance line in text — prefer lines with actual $ numbers
    bal_lines = []
    for line in text.split('\n'):
        if re.search(r'(opening|closing|first|last|day net|net change|start|end).*\$[\d.,]+', line, re.IGNORECASE):
            bal_lines.append(line.strip())
    balance = '\n'.join(bal_lines[:6]) if bal_lines else ""
else:
    balance = balance_in_final

# Strip [Pipeline note: ...] from balance — these are operational runner notes, not data.
# Gate question: "Does balance contain [Pipeline note:"? YES → strip it.
if balance and '[Pipeline note:' in balance:
    balance = re.sub(r'\[Pipeline note:[^\]]*\]', '', balance, flags=re.DOTALL).strip()

btc     = grab_line([r"\bbtc\b", r"bitcoin"], text)

# Strategy verdict / recommendation (for the Risk section if it's empty)
if not risk:
    risk = grab_section([r"STRATEGY WATCH", r"VERDICT", r"RECOMMENDATION"], final or text)

# Derive title suffix from balance — use LAST match (most recent day for multi-day analyses).
# BUG FIX (SE-AETHER-001): re.search returns FIRST match. For 2-day analyses this picks Day 1's
# balance, producing wrong title. re.findall captures ALL matches; [-1] is the most recent.
# NEVER use bash string interpolation to patch dollar amounts — $0.97 becomes bash.97 ($0=script).
title_suffix = ""
bal_matches = re.findall(r"\$([\d\.,]+)\s*(?:→|->|to)\s*\$([\d\.,]+)", text)
if bal_matches:
    try:
        last = bal_matches[-1]  # most recent balance pair
        a = float(last[0].replace(",", ""))
        b = float(last[1].replace(",", ""))
        diff = b - a
        sign = "+" if diff >= 0 else "-"
        title_suffix = f" ({sign}${abs(diff):.2f})"
    except Exception:
        pass

# Day-of-week friendly title
import datetime
try:
    dt = datetime.datetime.strptime(date, "%Y-%m-%d")
    day_name = dt.strftime("%a %b %-d")
except Exception:
    day_name = date

title = f"AetherBot Daily Analysis — {day_name}{title_suffix}"

# SE-AETHER-003: VERSION REFERENCE GATE
# Published reports must state the current deployed version (v253).
# Reports that only reference old versions (e.g. v247) mislead readers into thinking
# old code is still in production. This gate: (1) detects any vNNN reference in the
# analysis, (2) warns if the highest referenced version is more than 5 builds behind
# the assumed current (v253). Does NOT block publishing — logs a warning only.
CURRENT_VERSION = 253  # update this when a new version is deployed
version_refs = [int(m) for m in re.findall(r'\bv(\d{3})\b', text) if 200 <= int(m) <= 999]
if version_refs:
    max_ref = max(version_refs)
    if max_ref < CURRENT_VERSION - 5:
        print(f"[publish] VERSION WARNING: highest version referenced is v{max_ref}, "
              f"but current deployed is v{CURRENT_VERSION}. "
              f"If this is historical context, ensure the report also states v{CURRENT_VERSION}.",
              file=sys.stderr)
    elif CURRENT_VERSION not in version_refs and max_ref < CURRENT_VERSION:
        print(f"[publish] VERSION NOTICE: v{CURRENT_VERSION} not mentioned in analysis. "
              f"Highest seen: v{max_ref}. Consider stating current deployed version.",
              file=sys.stderr)
else:
    print(f"[publish] VERSION NOTICE: No vNNN version references found in analysis.", file=sys.stderr)

# Read GPT phase files — clean machine headers, keep substantive content
def load_gpt(path, min_chars=200):
    """Load GPT file, strip machine headers (====, Generated:, Tokens:, NOTE:), return clean content."""
    try:
        with open(path, "r", errors="replace") as f:
            raw = f.read().strip()
        if len(raw) < min_chars or raw.startswith("PENDING"):
            return ""
        # Strip machine header block: everything before first real content line
        lines = raw.split('\n')
        cleaned = []
        header_done = False
        for line in lines:
            stripped = line.strip()
            if not header_done:
                # Skip separator lines and machine headers at top
                if re.match(r'^[=\-]{10,}$', stripped):
                    continue
                if re.match(r'^(GPT-4o PHASE \d+|Generated:|Source:|Tokens:|Independence gate:|Kai analysis:|NOTE: This file)', stripped):
                    continue
                # First real content line — header is done
                if stripped and not re.match(r'^[=\-]{10,}$', stripped):
                    header_done = True
            cleaned.append(line)
        return '\n'.join(cleaned).strip()
    except Exception:
        pass
    return ""

analysis_dir = os.path.dirname(analysis_path)
gpt_independent = load_gpt(os.path.join(analysis_dir, f"GPT_Independent_{date}.txt"))
# Try both filenames: gpt_crosscheck.py now writes GPT_Review_DATE.txt; older runs wrote GPT_CrossCheck_DATE.txt
gpt_review = load_gpt(os.path.join(analysis_dir, f"GPT_Review_{date}.txt"))
if not gpt_review:
    gpt_review = load_gpt(os.path.join(analysis_dir, f"GPT_CrossCheck_{date}.txt"))

# NO readLink — all content is rendered inline. Hyo should not have to navigate to another page.
# The aether-analysis.html page exists for historical lookups but is not the primary viewer.
# Gate question: "Did I set readLink to empty?" YES → good. NO → fix it.

sections = {
    "summary": summary or "(no summary extracted)",
    "trades":  trades  or "(trade data not extracted — check Analysis file for PART 2)",
    "risk":    risk    or "(risk section not extracted)",
    "balance": balance or "(balance data not extracted)",
}
if btc:
    sections["btc"] = btc
if gpt_independent:
    # gptIndependent: the 8-dimension independent review (human-readable, machine headers stripped)
    sections["gptIndependent"] = gpt_independent
if gpt_review:
    # gptReview: the cross-check verdict (human-readable)
    sections["gptReview"] = gpt_review

new_entry = {
    "id": entry_id,
    "type": "aether-analysis",
    "title": title,
    "author": "Aether",
    "authorIcon": "📈",
    "authorColor": "#e8c96a",
    "timestamp": now_mt,
    "date": date,
    # readLink intentionally omitted — all content renders inline on HQ.
    # Hyo should not need to navigate to a separate page to read the analysis.
    "sections": sections,
}

def upsert(path):
    if not os.path.exists(path):
        print(f"[publish] WARN feed missing at {path}", file=sys.stderr)
        return False
    with open(path) as f:
        data = json.load(f)
    reports = data.setdefault("reports", [])
    # Remove existing entry with same id (idempotent)
    reports[:] = [r for r in reports if r.get("id") != entry_id]
    # Insert near the front so it shows up on HQ
    reports.insert(0, new_entry)
    data["lastUpdated"] = now_mt
    data["today"] = now_mt[:10]  # always current system date, not analysis date (structural fix — S31c)
    # Also record in history if the structure exists
    hist = data.get("history")
    if isinstance(hist, dict):
        month = hist.setdefault(month_key, {})
        daylist = month.setdefault(date, [])
        daylist[:] = [r for r in daylist if r.get("id") != entry_id]
        daylist.insert(0, new_entry)
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return True

ok_git  = upsert(feed_git)
ok_live = upsert(feed_live)

print(f"[publish] feed_git={ok_git} feed_live={ok_live} id={entry_id}")
if not (ok_git or ok_live):
    sys.exit(1)
PYEOF
PUB_RC=$?

if [[ $PUB_RC -ne 0 ]]; then
  echo "[publish] ERROR: feed update failed" >&2
  exit $PUB_RC
fi

# Verify by re-reading feed.json and confirming the id exists
python3 - "$FEED_GIT" "$DATE" <<'VERIFY'
import json, sys
feed, date = sys.argv[1:3]
with open(feed) as f:
    d = json.load(f)
want = f"aether-analysis-{date}"
ids = [r.get("id") for r in d.get("reports", [])]
if want not in ids:
    print(f"[publish] VERIFY FAILED: {want} not in feed", file=sys.stderr)
    sys.exit(1)
print(f"[publish] VERIFY OK: {want} present in feed")
VERIFY
VERIFY_RC=$?

if [[ $VERIFY_RC -ne 0 ]]; then
  exit $VERIFY_RC
fi

# ── Write aether-daily-sections.json (binds the HQ dashboard panel) ────────
SECTIONS_GIT="$ROOT/agents/sam/website/data/aether-daily-sections.json"
SECTIONS_LIVE="$ROOT/website/data/aether-daily-sections.json"

python3 - "$SECTIONS_GIT" "$SECTIONS_LIVE" "$DATE" "$NOW_MT" "$ANALYSIS_FILE" <<'SECTIONS'
import json, os, re, sys

sections_git, sections_live, date, now_mt, analysis_path = sys.argv[1:6]

with open(analysis_path, "r", errors="replace") as f:
    text = f.read()

def slice_section(t, start_markers, end_markers=None):
    start = -1
    for m in start_markers:
        i = t.find(m)
        if i >= 0:
            start = i + len(m)
            break
    if start < 0:
        return ""
    end = len(t)
    if end_markers:
        for m in end_markers:
            j = t.find(m, start)
            if j >= 0 and j < end:
                end = j
    return t[start:end].strip()

def first_paragraphs(t, max_chars=800):
    for p in re.split(r"\n\s*\n", t.strip()):
        p = p.strip()
        if len(p) > 40 and not p.startswith("==="):
            return p[:max_chars]
    return t[:max_chars].strip()

final   = slice_section(text, ["=== FINAL SYNTHESIS ===", "FINAL SYNTHESIS"])
primary = slice_section(text,
    ["=== CLAUDE PRIMARY ANALYSIS ===", "CLAUDE PRIMARY ANALYSIS"],
    ["=== GPT CRITIQUE ===", "GPT CRITIQUE", "=== FINAL"])
if not primary:
    primary = text[:3000]

introspection = first_paragraphs(final or primary, 900)

# Research — look for a dedicated research section
research_raw = slice_section(text,
    ["RESEARCH:", "Research:", "=== RESEARCH ==="],
    ["\n\n"])
if not research_raw:
    # fallback: grab sentences mentioning analysis/research
    sentences = re.findall(r"[A-Z][^.!?\n]{40,200}[.!?]", text)
    research_raw = " ".join(s for s in sentences[:5] if any(w in s.lower() for w in ["research", "analyz", "investig", "backtest", "model"]))
research = research_raw[:600] if research_raw else ""

# Changes — look for changes/shipped section
changes_raw = slice_section(text,
    ["CHANGES:", "Changes:", "What Changed:", "shipped", "=== CHANGES"],
    ["\n\n"])
if not changes_raw:
    changes_raw = ""
changes = changes_raw[:500]

# Follow-ups — look for action items / P0/P1/P2 bullets
follow_ups = []
for line in text.split("\n"):
    line = line.strip()
    if re.match(r"^(P0|P1|P2|P3)[:\s]", line) or re.match(r"^[-*]\s+(P0|P1|P2|P3)", line):
        item = re.sub(r"^[-*]\s+", "", line).strip()
        if len(item) > 10:
            follow_ups.append(item)
if not follow_ups:
    # Fallback: any line starting with - or * that looks like an action item
    for line in text.split("\n"):
        line = line.strip()
        if re.match(r"^[-*]\s+[A-Z]", line) and len(line) > 20:
            follow_ups.append(re.sub(r"^[-*]\s+", "", line)[:200])
    follow_ups = follow_ups[:5]

# For Kai — look for "For Kai" section
for_kai = slice_section(text,
    ["For Kai:", "FOR KAI:", "=== FOR KAI", "Recommendations for Kai"],
    ["\n\n", "==="])
if not for_kai:
    # Look for recommendations / risk section
    for_kai = slice_section(text,
        ["RECOMMENDATION", "Key Takeaway", "ACTION REQUIRED"],
        ["\n\n"])
for_kai = for_kai[:700] if for_kai else ""

sections = {
    "date": date,
    "generated": now_mt,
    "introspection": introspection or "(analysis not yet extracted)",
    "research": research or "",
    "changes": changes or "",
    "followUps": follow_ups,
    "forKai": for_kai or "",
}

def write_sections(path):
    if not os.path.exists(os.path.dirname(path)):
        print(f"[sections] WARN dir missing: {os.path.dirname(path)}", file=sys.stderr)
        return False
    with open(path, "w") as f:
        json.dump(sections, f, ensure_ascii=False, indent=2)
    return True

ok_git  = write_sections(sections_git)
ok_live = write_sections(sections_live)
print(f"[sections] git={ok_git} live={ok_live} date={date}")
SECTIONS
SECTIONS_RC=$?

if [[ $SECTIONS_RC -eq 0 ]]; then
  echo "[publish] aether-daily-sections.json updated for $DATE"
else
  echo "[publish] WARN: aether-daily-sections.json update failed (rc=$SECTIONS_RC) — feed entry still published" >&2
fi

# ── Update issue progress notes in aether-metrics.json ─────────────────────
# Scans the analysis text for issue mentions and updates progress field.
# Also stamps updatedAt on every issue so HQ shows "last changed" date.
METRICS_GIT="$ROOT/agents/sam/website/data/aether-metrics.json"
METRICS_LIVE="$ROOT/website/data/aether-metrics.json"

if [[ -f "$ANALYSIS_FILE" ]]; then
  python3 - "$ANALYSIS_FILE" "$DATE" "$METRICS_GIT" "$METRICS_LIVE" <<'ISSUE_UPDATE'
import json, re, sys, os

analysis_path, date, *metric_paths = sys.argv[1:]
with open(analysis_path) as f:
    text = f.read()

now_cmd = __import__('re').sub(r'([+-]\d{2})(\d{2})$', r'\1:\2',
    __import__('subprocess').check_output(
    ["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"], text=True).strip())

# Detect resolved/in-progress mentions by issue ID or keyword
def infer_status(issue_id, title, text):
    t = text.lower()
    title_kw = title.lower()[:30]
    # Look for explicit RESOLVED mentions near the issue
    if re.search(rf'(issue {issue_id}|{re.escape(title_kw[:20])}).{{0,200}}(resolved|fixed|shipped|closed)', t, re.DOTALL):
        return "RESOLVED"
    if re.search(rf'(issue {issue_id}|{re.escape(title_kw[:20])}).{{0,200}}(in.progress|investigating|testing)', t, re.DOTALL):
        return "IN_PROGRESS"
    return None  # don't change if no evidence

# Extract 1-sentence progress snippet from nearby text
def extract_snippet(issue_id, title, text, max_chars=150):
    title_kw = title[:25].lower()
    m = re.search(rf'.{{0,60}}{re.escape(title_kw)}.{{0,200}}', text.lower())
    if m:
        snippet = text[m.start():m.end()].strip()
        # Clean up to first sentence
        snippet = re.split(r'[.\n]', snippet)[0][:max_chars].strip()
        return snippet if len(snippet) > 20 else ""
    return ""

for metrics_path in metric_paths:
    if not os.path.exists(metrics_path):
        continue
    with open(metrics_path) as f:
        d = json.load(f)
    changed = False
    for issue in d.get("openIssues", []):
        iid = issue.get("id", 0)
        title = issue.get("title", "")
        new_status = infer_status(iid, title, text)
        snippet = extract_snippet(iid, title, text)
        if new_status and new_status != issue.get("status"):
            issue["status"] = new_status
            changed = True
        if snippet:
            issue["progress"] = snippet
            changed = True
        issue["updatedAt"] = now_cmd  # always stamp analysis date
    d["lastUpdated"] = now_cmd
    d["updatedAt"] = now_cmd
    if changed:
        with open(metrics_path, "w") as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        print(f"[issues] Updated {metrics_path.split('/')[-3]}/aether-metrics.json")
    else:
        # Still write to update timestamps
        with open(metrics_path, "w") as f:
            json.dump(d, f, ensure_ascii=False, indent=2)
        print(f"[issues] Timestamps updated, no status changes detected")
ISSUE_UPDATE
  echo "[publish] issue status update complete"
fi

exit 0
