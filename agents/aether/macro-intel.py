#!/usr/bin/env python3
"""
agents/aether/macro-intel.py — Daily Macro Intelligence Phase for Aether
Version: 1.0 — 2026-04-30

Addresses GROWTH.md W1: Macro Data Coverage Inadequate.

Gathers structured macro intelligence and writes a daily report:
  1. FOMC calendar — upcoming meetings, rate decisions (within 14d window)
  2. CPI/PCE release schedule — upcoming inflation data releases
  3. DXY trend — dollar index direction (fetched from Yahoo Finance)
  4. Macro regime classification — risk-on / risk-off / neutral

Output: agents/aether/research/macro-YYYY-MM-DD.md
        agents/aether/ledger/macro-latest.json (machine-readable)

Usage:
  python3 agents/aether/macro-intel.py              # today's report
  python3 agents/aether/macro-intel.py --date 2026-05-01  # specific date
  python3 agents/aether/macro-intel.py --check       # idempotency check (exit 0 if today done)

Data sources:
  - FOMC dates: federalreserve.gov published schedule (hardcoded annually, verified)
  - CPI dates: BLS.gov published schedule (hardcoded annually, verified)
  - DXY: Yahoo Finance API (free, no key required)
"""

import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timedelta, date

# ─── Config ──────────────────────────────────────────────────────────────────
HYO_ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
RESEARCH_DIR = os.path.join(HYO_ROOT, "agents/aether/research")
LEDGER_DIR = os.path.join(HYO_ROOT, "agents/aether/ledger")
os.makedirs(RESEARCH_DIR, exist_ok=True)
os.makedirs(LEDGER_DIR, exist_ok=True)

# ─── 2026 FOMC Meeting Dates ────────────────────────────────────────────────
# Source: https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
# These are the STATEMENT release dates (rate decision announced).
# Updated annually when the Fed publishes the next year's calendar.
FOMC_DATES_2026 = [
    date(2026, 1, 28),   # Jan 27-28
    date(2026, 3, 18),   # Mar 17-18
    date(2026, 5, 6),    # May 5-6
    date(2026, 6, 17),   # Jun 16-17 (SEP + dot plot)
    date(2026, 7, 29),   # Jul 28-29
    date(2026, 9, 16),   # Sep 15-16 (SEP + dot plot)
    date(2026, 11, 4),   # Nov 3-4
    date(2026, 12, 16),  # Dec 15-16 (SEP + dot plot)
]

# Meetings with Summary of Economic Projections (dot plot) — extra significance
FOMC_SEP_DATES_2026 = {
    date(2026, 3, 18),
    date(2026, 6, 17),
    date(2026, 9, 16),
    date(2026, 12, 16),
}

# ─── 2026 CPI Release Dates ─────────────────────────────────────────────────
# Source: https://www.bls.gov/schedule/news_release/cpi.htm
# CPI is released at 8:30 AM ET on these dates.
CPI_DATES_2026 = [
    date(2026, 1, 14),   # Dec 2025 data
    date(2026, 2, 12),   # Jan 2026 data
    date(2026, 3, 11),   # Feb 2026 data
    date(2026, 4, 10),   # Mar 2026 data
    date(2026, 5, 13),   # Apr 2026 data
    date(2026, 6, 10),   # May 2026 data
    date(2026, 7, 15),   # Jun 2026 data
    date(2026, 8, 12),   # Jul 2026 data
    date(2026, 9, 10),   # Aug 2026 data
    date(2026, 10, 13),  # Sep 2026 data
    date(2026, 11, 12),  # Oct 2026 data
    date(2026, 12, 10),  # Nov 2026 data
]

# ─── 2026 PCE Release Dates ─────────────────────────────────────────────────
# Source: https://www.bea.gov/news/schedule
# PCE (Fed's preferred inflation gauge) released by BEA.
PCE_DATES_2026 = [
    date(2026, 1, 30),   # Dec 2025 data
    date(2026, 2, 27),   # Jan 2026 data
    date(2026, 3, 27),   # Feb 2026 data
    date(2026, 4, 30),   # Mar 2026 data
    date(2026, 5, 29),   # Apr 2026 data
    date(2026, 6, 26),   # May 2026 data
    date(2026, 7, 31),   # Jun 2026 data
    date(2026, 8, 28),   # Jul 2026 data
    date(2026, 9, 25),   # Aug 2026 data
    date(2026, 10, 30),  # Sep 2026 data
    date(2026, 11, 25),  # Oct 2026 data
    date(2026, 12, 23),  # Nov 2026 data
]


def get_upcoming_events(today: date, window_days: int = 14) -> list:
    """Find macro events within the lookahead window."""
    events = []
    cutoff = today + timedelta(days=window_days)

    for d in FOMC_DATES_2026:
        if today <= d <= cutoff:
            days_away = (d - today).days
            has_sep = d in FOMC_SEP_DATES_2026
            label = "FOMC + SEP/Dot Plot" if has_sep else "FOMC Rate Decision"
            events.append({
                "type": "FOMC",
                "date": d.isoformat(),
                "days_away": days_away,
                "label": label,
                "impact": "HIGH" if has_sep else "MEDIUM-HIGH",
                "note": f"{label} in {days_away} day{'s' if days_away != 1 else ''} — elevated volatility risk"
            })

    for d in CPI_DATES_2026:
        if today <= d <= cutoff:
            days_away = (d - today).days
            events.append({
                "type": "CPI",
                "date": d.isoformat(),
                "days_away": days_away,
                "label": "CPI Release (8:30 AM ET)",
                "impact": "HIGH",
                "note": f"CPI release in {days_away} day{'s' if days_away != 1 else ''} — historically ±2-3% BTC move"
            })

    for d in PCE_DATES_2026:
        if today <= d <= cutoff:
            days_away = (d - today).days
            events.append({
                "type": "PCE",
                "date": d.isoformat(),
                "days_away": days_away,
                "label": "PCE Price Index (Fed preferred)",
                "impact": "MEDIUM-HIGH",
                "note": f"PCE release in {days_away} day{'s' if days_away != 1 else ''} — Fed's preferred inflation gauge"
            })

    events.sort(key=lambda e: e["days_away"])
    return events


def fetch_dxy_data() -> dict:
    """Fetch DXY (US Dollar Index) data from Yahoo Finance."""
    result = {
        "available": False,
        "current": None,
        "prev_close": None,
        "change_pct": None,
        "trend": "unknown",
        "source": "Yahoo Finance (DX-Y.NYB)",
        "error": None,
    }

    try:
        url = "https://query1.finance.yahoo.com/v8/finance/chart/DX-Y.NYB?range=5d&interval=1d"
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
        })
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())

        chart = data["chart"]["result"][0]
        meta = chart["meta"]
        closes = chart["indicators"]["quote"][0]["close"]

        # Filter out None values
        valid_closes = [c for c in closes if c is not None]

        if len(valid_closes) >= 2:
            current = round(valid_closes[-1], 2)
            prev = round(valid_closes[-2], 2)
            change = round(current - prev, 2)
            change_pct = round((change / prev) * 100, 2)

            if change_pct > 0.15:
                trend = "rising"
            elif change_pct < -0.15:
                trend = "falling"
            else:
                trend = "flat"

            result.update({
                "available": True,
                "current": current,
                "prev_close": prev,
                "change": change,
                "change_pct": change_pct,
                "trend": trend,
            })
        elif len(valid_closes) == 1:
            result.update({
                "available": True,
                "current": round(valid_closes[-1], 2),
                "trend": "insufficient data (1 day only)",
            })
    except urllib.error.URLError as e:
        result["error"] = f"Network error: {e.reason}"
    except Exception as e:
        result["error"] = str(e)

    return result


def classify_macro_regime(dxy: dict, events: list) -> dict:
    """
    Classify the current macro environment:
      - risk-on: DXY falling (dollar weakness = risk appetite)
      - risk-off: DXY rising (dollar strength = risk aversion)
      - neutral: DXY flat or data unavailable
      - event-driven: major event within 3 days overrides
    """
    regime = {
        "classification": "neutral",
        "confidence": "low",
        "factors": [],
        "posture_implication": "No macro adjustment needed",
    }

    # Event proximity override
    imminent_events = [e for e in events if e["days_away"] <= 3]
    if imminent_events:
        event_labels = [e["label"] for e in imminent_events]
        regime["classification"] = "event-driven"
        regime["confidence"] = "high"
        regime["factors"].append(f"Imminent macro event(s): {', '.join(event_labels)}")
        regime["posture_implication"] = "REDUCE_EXPOSURE recommended — elevated volatility expected within 72h"
        return regime

    # DXY-based classification
    if not dxy.get("available"):
        regime["factors"].append("DXY data unavailable — cannot assess dollar trend")
        return regime

    trend = dxy.get("trend", "unknown")
    change_pct = dxy.get("change_pct", 0)

    if trend == "rising":
        regime["classification"] = "risk-off"
        regime["confidence"] = "medium" if abs(change_pct) > 0.3 else "low"
        regime["factors"].append(f"DXY rising (+{change_pct}%) — dollar strength signals risk aversion")
        regime["factors"].append("BTC historically correlates inversely with DXY — headwind")
        regime["posture_implication"] = "Caution advised — macro headwind for BTC"
    elif trend == "falling":
        regime["classification"] = "risk-on"
        regime["confidence"] = "medium" if abs(change_pct) > 0.3 else "low"
        regime["factors"].append(f"DXY falling ({change_pct}%) — dollar weakness signals risk appetite")
        regime["factors"].append("BTC historically correlates inversely with DXY — tailwind")
        regime["posture_implication"] = "Conditions favorable — macro tailwind for BTC"
    else:
        regime["factors"].append(f"DXY flat ({change_pct}%) — no clear macro signal")

    return regime


def generate_report(today: date) -> dict:
    """Generate the full macro intelligence report."""
    events = get_upcoming_events(today)
    dxy = fetch_dxy_data()
    regime = classify_macro_regime(dxy, events)

    report = {
        "date": today.isoformat(),
        "generated_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S-06:00"),
        "version": "1.0",
        "events_window_days": 14,
        "upcoming_events": events,
        "dxy": dxy,
        "macro_regime": regime,
        "summary": "",
    }

    # Build human-readable summary
    parts = []
    parts.append(f"Macro regime: {regime['classification']} ({regime['confidence']} confidence)")

    if dxy.get("available"):
        parts.append(f"DXY: {dxy['current']} ({dxy['trend']}, {dxy.get('change_pct', '?')}%)")
    else:
        parts.append(f"DXY: unavailable ({dxy.get('error', 'no data')})")

    if events:
        nearest = events[0]
        parts.append(f"Next event: {nearest['label']} in {nearest['days_away']}d ({nearest['date']})")
    else:
        parts.append("No macro events in next 14 days")

    parts.append(regime["posture_implication"])
    report["summary"] = " | ".join(parts)

    return report


def write_markdown_report(report: dict, filepath: str):
    """Write the human-readable macro report."""
    events = report["upcoming_events"]
    dxy = report["dxy"]
    regime = report["macro_regime"]

    lines = [
        f"# Macro Intelligence — {report['date']}",
        f"",
        f"**Generated:** {report['generated_at']}",
        f"**Macro Regime:** {regime['classification'].upper()} ({regime['confidence']} confidence)",
        f"**Posture Implication:** {regime['posture_implication']}",
        f"",
        f"## Summary",
        f"",
        f"{report['summary']}",
        f"",
        f"## DXY (US Dollar Index)",
        f"",
    ]

    if dxy.get("available"):
        lines.extend([
            f"- **Current:** {dxy['current']}",
            f"- **Previous Close:** {dxy.get('prev_close', 'N/A')}",
            f"- **Change:** {dxy.get('change', 'N/A')} ({dxy.get('change_pct', 'N/A')}%)",
            f"- **Trend:** {dxy['trend']}",
            f"- **BTC Correlation:** Historically inverse — DXY up = BTC headwind, DXY down = BTC tailwind",
        ])
    else:
        lines.extend([
            f"- **Status:** Data unavailable",
            f"- **Error:** {dxy.get('error', 'unknown')}",
        ])

    lines.extend([
        f"",
        f"## Upcoming Macro Events (14-day window)",
        f"",
    ])

    if events:
        for e in events:
            icon = "🔴" if e["impact"] == "HIGH" else "🟡"
            lines.append(f"- {icon} **{e['label']}** — {e['date']} ({e['days_away']}d away) [{e['impact']}]")
            lines.append(f"  - {e['note']}")
    else:
        lines.append("No significant macro events in the next 14 days.")

    lines.extend([
        f"",
        f"## Macro Regime Analysis",
        f"",
        f"**Classification:** {regime['classification']}",
        f"",
    ])

    for factor in regime["factors"]:
        lines.append(f"- {factor}")

    lines.extend([
        f"",
        f"---",
        f"*Source: FOMC calendar (federalreserve.gov), CPI schedule (bls.gov), DXY (Yahoo Finance)*",
    ])

    with open(filepath, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    # Parse args
    target_date = date.today()
    check_only = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--date" and i + 1 < len(args):
            target_date = date.fromisoformat(args[i + 1])
            i += 2
        elif args[i] == "--check":
            check_only = True
            i += 1
        else:
            i += 1

    md_path = os.path.join(RESEARCH_DIR, f"macro-{target_date.isoformat()}.md")
    json_path = os.path.join(LEDGER_DIR, "macro-latest.json")

    # Idempotency check
    if check_only:
        if os.path.exists(md_path):
            print(f"ALREADY_DONE: {md_path}")
            sys.exit(0)
        else:
            print(f"NOT_DONE: {md_path}")
            sys.exit(1)

    # Skip if already generated today (idempotent)
    if os.path.exists(md_path):
        # Check if it's more than 6 hours old — refresh if so
        age_hours = (datetime.now().timestamp() - os.path.getmtime(md_path)) / 3600
        if age_hours < 6:
            print(f"SKIP: macro report already generated today ({md_path}, {age_hours:.1f}h old)")
            sys.exit(0)
        print(f"REFRESH: macro report is {age_hours:.1f}h old, regenerating")

    # Generate report
    report = generate_report(target_date)

    # Write outputs
    write_markdown_report(report, md_path)
    with open(json_path, "w") as f:
        json.dump(report, f, indent=2)
        f.write("\n")

    print(f"OK: {report['summary']}")
    print(f"  → {md_path}")
    print(f"  → {json_path}")


if __name__ == "__main__":
    main()
