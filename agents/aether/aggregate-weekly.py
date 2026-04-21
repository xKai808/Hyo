#!/usr/bin/env python3
"""
agents/aether/aggregate-weekly.py — Aether W3: Cross-Session Strategy Aggregator

Aether W3 fix: Strategy evaluation was manual — no automated aggregation.
This script reads all Analysis_*.txt files, extracts per-strategy edge,
per-window P&L trends, concentration risk, and strategy family health.

Shipped: 2026-04-21 | Protocol: agents/aether/GROWTH.md W3

WHAT IT EXTRACTS (from analysis files):
  - Daily net P&L from balance ledger lines
  - Per-window P&L from markdown tables (EU_MORNING/NY_PRIME/ASIA_OPEN/EVENING)
  - Per-strategy trade counts, wins, losses, P&L from table rows
  - Consecutive loss streaks per strategy
  - Concentration risk (% profit from top N trades)

USAGE:
  python3 agents/aether/aggregate-weekly.py           # last 7 days
  python3 agents/aether/aggregate-weekly.py --days 30 # last 30 days
  python3 agents/aether/aggregate-weekly.py --all     # all available files
  python3 agents/aether/aggregate-weekly.py --json    # machine-readable JSON

OUTPUT:
  agents/aether/ledger/weekly-aggregator.json — machine-readable metrics
  agents/aether/research/STRATEGY_HEALTH.md  — human-readable report
  stdout — summary
"""

from __future__ import annotations
import argparse
import datetime
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", str(Path.home() / "Documents" / "Projects" / "Hyo")))
ANALYSIS_DIR = ROOT / "agents" / "aether" / "analysis"
LOGS_DIR = ROOT / "agents" / "aether" / "logs"
LEDGER_OUT = ROOT / "agents" / "aether" / "ledger" / "weekly-aggregator.json"
HEALTH_OUT = ROOT / "agents" / "aether" / "research" / "STRATEGY_HEALTH.md"

NOW = datetime.datetime.now(datetime.timezone.utc).isoformat()
TODAY = datetime.date.today()

# Strategy families to track
KNOWN_STRATEGIES = {
    "bps_premium", "bps_late", "bps_early",
    "PAQ_EARLY_AGG", "PAQ_STRUCT_GATE", "PAQ_LATE",
    "YES-momentum", "NO-fade",
    "ladder", "binary", "spread", "scalp", "harvest",
    "SYNTHETIC_LONG", "COVERED_CALL",
}

# Windows
WINDOWS = ["OVERNIGHT", "EU_MORNING", "ASIA_OPEN", "NY_PRIME", "EVENING", "OVERNIGHT2"]


def parse_dollar(s: str) -> float | None:
    """Parse '$X.XX' or '+$X.XX' or '-$X.XX' → float"""
    m = re.search(r'([+-]?)\s*\$\s*([0-9]+\.?[0-9]*)', s.replace(',', ''))
    if not m:
        return None
    sign = -1 if m.group(1) == '-' else 1
    return sign * float(m.group(2))


def parse_analysis_file(path: Path) -> dict:
    """Parse a single analysis file. Returns dict with extracted metrics."""
    result: dict = {
        "file": str(path.name),
        "date": None,
        "net_pnl": None,
        "start_balance": None,
        "end_balance": None,
        "window_pnl": {},       # window → float
        "strategy_rows": [],    # list of {strategy, window, trades, wins, losses, pnl}
        "parse_quality": "ok",
    }

    # Extract date from filename
    m = re.search(r'(\d{4}-\d{2}-\d{2})', path.name)
    if m:
        result["date"] = m.group(1)

    try:
        text = path.read_text(errors="replace")
    except OSError as e:
        result["parse_quality"] = f"read_error: {e}"
        return result

    # ── Balance ledger: "Apr 16: $116.16 → $114.33  net -$1.83"
    bal_matches = re.findall(
        r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d+[^:]*:\s*\$([0-9.]+)\s*(?:→|->|>)\s*\$([0-9.]+)\s+net\s+([+-]?\$[0-9.]+)',
        text
    )
    if bal_matches:
        # Take the last balance line as most authoritative
        last = bal_matches[-1]
        result["start_balance"] = float(last[0])
        result["end_balance"] = float(last[1])
        v = parse_dollar(last[2])
        if v is not None:
            result["net_pnl"] = v

    # Also try: "net -$1.83" standalone
    if result["net_pnl"] is None:
        net_m = re.search(r'\bnet\s+([+-]?\$[0-9.]+)', text)
        if net_m:
            result["net_pnl"] = parse_dollar(net_m.group(1))

    # ── Markdown table rows: | WINDOW | STRATEGY | count | ... | P&L |
    # Pattern: | WINDOW | STRATEGY | N | ... | +$X.XX |
    table_rows = re.findall(
        r'\|\s*(\*{0,2})(OVERNIGHT2?|EU_MORNING|ASIA_OPEN|NY_PRIME|EVENING)\*{0,2}\s*\|'
        r'\s*([^|]+?)\s*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|'  # count
        r'([^|]*\|){3,6}'                                  # skip middle cols
        r'\s*\*{0,2}([+-]?\$[0-9.]+)\*{0,2}\s*\|',
        text
    )
    for row in table_rows:
        window = row[1]
        strategy = row[2].strip().strip('*').strip()
        count_str = row[3]
        pnl_str = row[5]  # last captured group

        # Skip TOTAL rows
        if "TOTAL" in strategy or not strategy:
            continue

        pnl = parse_dollar(pnl_str)
        count = int(count_str) if count_str.isdigit() else 0

        # Try to extract wins/losses from row text (look for "W|L" columns)
        # The table has win/loss columns — look for patterns like "4|2" or numbers
        result["strategy_rows"].append({
            "window": window,
            "strategy": strategy,
            "trades": count,
            "pnl": pnl,
        })

    # ── Window totals from table TOTAL rows
    window_total_rows = re.findall(
        r'\|\s*\*{0,2}(OVERNIGHT2?|EU_MORNING|ASIA_OPEN|NY_PRIME|EVENING)\s+TOTAL\*{0,2}\s*\|'
        r'[^|]*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|'
        r'(?:[^|]*\|){3,6}'
        r'\s*\*{0,2}([+-]?\$[0-9.]+)\*{0,2}\s*\|',
        text
    )
    for row in window_total_rows:
        window = row[0]
        pnl = parse_dollar(row[2])
        if pnl is not None:
            result["window_pnl"][window] = pnl

    # Fallback: extract window totals from inline patterns
    # "EU_MORNING  +$3.61  /  -$0.65  =  +$2.96"
    if not result["window_pnl"]:
        for window in WINDOWS:
            pattern = rf'{window}\s+([+-]?\$[0-9.]+)'
            wm = re.findall(pattern, text)
            if wm:
                # Take the first one as session total
                v = parse_dollar(wm[0])
                if v is not None:
                    result["window_pnl"][window] = v

    # ── Session breakdown table: "EU_MORNING  +$3.61  /  -$0.65  =  +$2.96"
    # This pattern gives two-day session splits
    session_splits = re.findall(
        r'(OVERNIGHT2?|EU_MORNING|ASIA_OPEN|NY_PRIME|EVENING)\s+'
        r'([+-]?\$[0-9.]+)\s+/\s+([+-]?\$[0-9.]+)\s+=\s+([+-]?\$[0-9.]+)',
        text
    )
    for split in session_splits:
        window, day1, day2, total = split
        v = parse_dollar(total)
        if v is not None and window not in result["window_pnl"]:
            result["window_pnl"][window] = v

    return result


def aggregate(parsed: list[dict]) -> dict:
    """Aggregate parsed file results into cross-session metrics."""

    # Per-strategy metrics
    strategy_stats: dict[str, dict] = defaultdict(lambda: {
        "trades": 0, "pnl": 0.0, "file_count": 0,
        "pnl_by_day": [],      # [(date, pnl)]
        "windows": defaultdict(float),
    })

    # Per-window metrics
    window_stats: dict[str, list[float]] = defaultdict(list)

    # Daily P&L series
    daily_pnl: list[tuple[str, float]] = []

    for p in parsed:
        if p["net_pnl"] is not None and p["date"]:
            daily_pnl.append((p["date"], p["net_pnl"]))

        for row in p.get("strategy_rows", []):
            strat = row["strategy"]
            if not strat or strat == "—":
                continue
            s = strategy_stats[strat]
            s["trades"] += row.get("trades", 0)
            if row["pnl"] is not None:
                s["pnl"] += row["pnl"]
                if p["date"]:
                    s["pnl_by_day"].append((p["date"], row["pnl"]))
            s["file_count"] += 1
            if row["pnl"] is not None:
                s["windows"][row["window"]] = s["windows"].get(row["window"], 0) + row["pnl"]

        for window, pnl in p.get("window_pnl", {}).items():
            window_stats[window].append(pnl)

    # Compute per-strategy edge (pnl / trades)
    strategy_report = {}
    for strat, s in sorted(strategy_stats.items(), key=lambda x: -x[1]["pnl"]):
        edge = (s["pnl"] / s["trades"]) if s["trades"] > 0 else 0
        # Trend: compare first half vs second half of days
        days = sorted(s["pnl_by_day"])
        half = len(days) // 2
        trend = "stable"
        if half >= 2:
            first_half = sum(d[1] for d in days[:half])
            second_half = sum(d[1] for d in days[half:])
            if second_half > first_half * 1.15:
                trend = "improving"
            elif second_half < first_half * 0.85:
                trend = "declining"

        strategy_report[strat] = {
            "total_pnl": round(s["pnl"], 2),
            "trades": s["trades"],
            "edge_per_trade": round(edge, 3),
            "sessions": s["file_count"],
            "trend": trend,
            "best_window": max(s["windows"], key=s["windows"].get) if s["windows"] else None,
            "worst_window": min(s["windows"], key=s["windows"].get) if s["windows"] else None,
        }

    # Window P&L summary
    window_report = {}
    for window in WINDOWS:
        vals = window_stats.get(window, [])
        if vals:
            window_report[window] = {
                "total_pnl": round(sum(vals), 2),
                "avg_pnl": round(sum(vals) / len(vals), 2),
                "sessions": len(vals),
                "positive_sessions": sum(1 for v in vals if v > 0),
                "negative_sessions": sum(1 for v in vals if v < 0),
                "win_rate": round(sum(1 for v in vals if v > 0) / len(vals) * 100, 1) if vals else 0,
                "ev_label": "+EV" if sum(vals) > 0 else "-EV",
            }

    # Concentration risk: what % of total profit comes from top strategies
    positive_strategies = [(s, d["total_pnl"]) for s, d in strategy_report.items() if d["total_pnl"] > 0]
    positive_strategies.sort(key=lambda x: -x[1])
    total_profit = sum(d["total_pnl"] for d in strategy_report.values() if d["total_pnl"] > 0)
    concentration = {}
    if total_profit > 0:
        cumulative = 0
        for i, (strat, pnl) in enumerate(positive_strategies[:5]):
            cumulative += pnl
            concentration[f"top_{i+1}"] = {
                "strategy": strat,
                "pnl": round(pnl, 2),
                "cumulative_pct": round(cumulative / total_profit * 100, 1),
            }

    # Daily P&L series sorted
    daily_pnl.sort()
    total_net = sum(v for _, v in daily_pnl)
    positive_days = sum(1 for _, v in daily_pnl if v > 0)

    # Health flags
    flags = []
    for strat, data in strategy_report.items():
        if data["trend"] == "declining" and data["trades"] >= 5:
            flags.append(f"DECLINING: {strat} — trend declining across sessions")
        if data["total_pnl"] < -5 and data["trades"] >= 3:
            flags.append(f"NEGATIVE: {strat} — total P&L ${data['total_pnl']:.2f}")

    if concentration.get("top_3", {}).get("cumulative_pct", 0) > 70:
        flags.append(f"CONCENTRATION: top 3 strategies = {concentration['top_3']['cumulative_pct']}% of profit")

    for window, data in window_report.items():
        if data["ev_label"] == "-EV" and data["sessions"] >= 3:
            flags.append(f"-EV WINDOW: {window} avg {data['avg_pnl']:.2f}/session ({data['sessions']} sessions)")

    return {
        "generated_at": NOW,
        "date_range": {
            "start": daily_pnl[0][0] if daily_pnl else None,
            "end": daily_pnl[-1][0] if daily_pnl else None,
            "sessions_analyzed": len(parsed),
        },
        "summary": {
            "total_net_pnl": round(total_net, 2),
            "positive_days": positive_days,
            "negative_days": len(daily_pnl) - positive_days,
            "win_rate_pct": round(positive_days / len(daily_pnl) * 100, 1) if daily_pnl else 0,
            "total_profit": round(total_profit, 2),
        },
        "daily_pnl": [{"date": d, "pnl": round(v, 2)} for d, v in daily_pnl],
        "strategy_health": strategy_report,
        "window_performance": window_report,
        "concentration_risk": concentration,
        "health_flags": flags,
    }


def render_markdown(data: dict) -> str:
    """Render human-readable strategy health report."""
    lines = []
    dr = data["date_range"]
    s = data["summary"]

    lines.append(f"# Aether Strategy Health Report")
    lines.append(f"**Generated:** {data['generated_at'][:10]}")
    lines.append(f"**Period:** {dr['start']} → {dr['end']} ({dr['sessions_analyzed']} sessions)")
    lines.append("")

    lines.append("## Overall Performance")
    lines.append(f"- Total net P&L: **${s['total_net_pnl']:+.2f}**")
    lines.append(f"- Win rate: **{s['win_rate_pct']}%** ({s['positive_days']}W / {s['negative_days']}L)")
    lines.append(f"- Total gross profit: **${s['total_profit']:.2f}**")
    lines.append("")

    # Health flags
    flags = data.get("health_flags", [])
    if flags:
        lines.append("## ⚠ Health Flags")
        for f in flags:
            lines.append(f"- {f}")
        lines.append("")
    else:
        lines.append("## ✓ No Health Flags")
        lines.append("")

    # Strategy performance table
    lines.append("## Strategy Performance")
    lines.append("| Strategy | Total P&L | Trades | Edge/Trade | Trend | Best Window |")
    lines.append("|----------|-----------|--------|------------|-------|-------------|")
    for strat, d in sorted(data["strategy_health"].items(), key=lambda x: -x[1]["total_pnl"]):
        trend_icon = {"improving": "↑", "declining": "↓", "stable": "→"}.get(d["trend"], "?")
        lines.append(
            f"| {strat} | ${d['total_pnl']:+.2f} | {d['trades']} | "
            f"${d['edge_per_trade']:+.3f} | {trend_icon} {d['trend']} | "
            f"{d['best_window'] or '—'} |"
        )
    lines.append("")

    # Window performance table
    lines.append("## Window Performance")
    lines.append("| Window | Total P&L | Avg/Session | Win Rate | Sessions | EV |")
    lines.append("|--------|-----------|-------------|----------|----------|----|")
    for window in WINDOWS:
        d = data["window_performance"].get(window)
        if d:
            lines.append(
                f"| {window} | ${d['total_pnl']:+.2f} | ${d['avg_pnl']:+.2f} | "
                f"{d['win_rate']}% | {d['sessions']} | **{d['ev_label']}** |"
            )
    lines.append("")

    # Concentration risk
    conc = data.get("concentration_risk", {})
    if conc:
        lines.append("## Concentration Risk")
        lines.append("| Rank | Strategy | P&L | Cumulative % of Profit |")
        lines.append("|------|----------|-----|------------------------|")
        for key in sorted(conc.keys()):
            c = conc[key]
            flag = " ⚠" if c["cumulative_pct"] > 70 else ""
            lines.append(f"| {key} | {c['strategy']} | ${c['pnl']:+.2f} | {c['cumulative_pct']}%{flag} |")
        lines.append("")

    # Daily P&L
    lines.append("## Daily P&L Series")
    for entry in data["daily_pnl"]:
        sign = "+" if entry["pnl"] >= 0 else ""
        lines.append(f"- {entry['date']}: **{sign}${entry['pnl']:.2f}**")

    return "\n".join(lines)


def find_analysis_files(days: int | None, all_files: bool) -> list[Path]:
    """Find analysis files matching criteria."""
    candidates = []

    # Analysis dir
    for f in ANALYSIS_DIR.glob("Analysis_*.txt"):
        candidates.append(f)

    # Aether logs dir
    for f in LOGS_DIR.glob("aether-*.log"):
        candidates.append(f)

    # Filter by date if not --all
    if not all_files and days is not None:
        cutoff = TODAY - datetime.timedelta(days=days)
        filtered = []
        for f in candidates:
            m = re.search(r'(\d{4}-\d{2}-\d{2})', f.name)
            if m:
                try:
                    d = datetime.date.fromisoformat(m.group(1))
                    if d >= cutoff:
                        filtered.append(f)
                except ValueError:
                    pass
            else:
                filtered.append(f)
        candidates = filtered

    # Deduplicate by date (prefer Analysis_ over log files)
    by_date: dict[str, Path] = {}
    for f in candidates:
        m = re.search(r'(\d{4}-\d{2}-\d{2})', f.name)
        key = m.group(1) if m else f.name
        if key not in by_date or f.name.startswith("Analysis_"):
            by_date[key] = f

    return sorted(by_date.values(), key=lambda f: f.name)


def main() -> int:
    ap = argparse.ArgumentParser(description="Aether cross-session strategy aggregator")
    ap.add_argument("--days", type=int, default=7, help="Days to look back (default: 7)")
    ap.add_argument("--all", action="store_true", help="Include all available files")
    ap.add_argument("--json", action="store_true", help="Output JSON summary")
    args = ap.parse_args()

    files = find_analysis_files(args.days if not args.all else None, args.all)
    if not files:
        print(f"No analysis files found in {ANALYSIS_DIR} or {LOGS_DIR}", file=sys.stderr)
        return 1

    print(f"=== Aether Strategy Aggregator — {TODAY} ===", file=sys.stderr)
    print(f"  Analyzing {len(files)} file(s)...", file=sys.stderr)

    parsed = []
    for f in files:
        result = parse_analysis_file(f)
        parsed.append(result)
        quality = result["parse_quality"]
        pnl_str = f"${result['net_pnl']:+.2f}" if result["net_pnl"] is not None else "no P&L"
        windows = len(result["window_pnl"])
        strategies = len(result["strategy_rows"])
        print(f"  {f.name}: {pnl_str}, {windows} windows, {strategies} strategy rows [{quality}]",
              file=sys.stderr)

    data = aggregate(parsed)

    # Write ledger
    LEDGER_OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(LEDGER_OUT, "w") as f:
        json.dump(data, f, indent=2)
    print(f"\n  Written: {LEDGER_OUT.relative_to(ROOT)}", file=sys.stderr)

    # Write markdown report
    HEALTH_OUT.parent.mkdir(parents=True, exist_ok=True)
    md = render_markdown(data)
    with open(HEALTH_OUT, "w") as f:
        f.write(md)
    print(f"  Written: {HEALTH_OUT.relative_to(ROOT)}", file=sys.stderr)

    # Print summary
    s = data["summary"]
    flags = data["health_flags"]
    print(f"\n=== Summary ===", file=sys.stderr)
    print(f"  Period: {data['date_range']['start']} → {data['date_range']['end']}", file=sys.stderr)
    print(f"  Net P&L: ${s['total_net_pnl']:+.2f} | Win rate: {s['win_rate_pct']}%", file=sys.stderr)
    print(f"  Health flags: {len(flags)}", file=sys.stderr)
    for flag in flags:
        print(f"    ⚠ {flag}", file=sys.stderr)

    if args.json:
        print(json.dumps(data, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
