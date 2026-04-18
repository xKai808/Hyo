#!/usr/bin/env python3
"""
sim-report-template.py — Reads sim-results.jsonl and generates an HTML analysis report.

Usage:
    python3 sim-report-template.py                          # reads sim-results.jsonl, writes today's report
    python3 sim-report-template.py --input sim-results.jsonl --date 2026-04-17
    python3 sim-report-template.py --last-n 50              # only last N result entries

Output:
    agents/sam/website/daily/aurora-sim-analysis-DATE.html
    (also synced to website/daily/ via dual-path rule)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import median, mean, quantiles

HERE = Path(__file__).resolve().parent
HYO_ROOT = Path(os.environ.get("HYO_ROOT", HERE.parent.parent)).resolve()

SIM_RESULTS    = HERE / "sim-results.jsonl"
WEBSITE_DAILY  = HYO_ROOT / "agents" / "sam" / "website" / "daily"
WEBSITE_DAILY2 = HYO_ROOT / "website" / "daily"  # dual-path

VOICES  = ["gentle", "balanced", "sharp"]
DEPTHS  = ["headlines", "balanced", "deep-dives"]
LENGTHS = ["3min", "6min", "12min"]

# ---------------------------------------------------------------------------
# data loading
# ---------------------------------------------------------------------------

def load_results(path: Path, last_n: int | None = None) -> list[dict]:
    if not path.exists():
        return []
    rows = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    if last_n:
        rows = rows[-last_n:]
    return rows

# ---------------------------------------------------------------------------
# aggregation helpers
# ---------------------------------------------------------------------------

def safe_pct(a: int, b: int) -> str:
    return f"{round(a / b * 100, 1)}%" if b else "n/a"

def p50_p95(vals: list[float]) -> tuple[float, float]:
    if not vals:
        return 0.0, 0.0
    s = sorted(vals)
    p50 = s[len(s)//2]
    p95 = s[int(len(s) * 0.95)]
    return round(p50, 2), round(p95, 2)

def group_by(rows: list[dict], key: str) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        out[r.get(key, "unknown")].append(r)
    return dict(out)

# ---------------------------------------------------------------------------
# section builders
# ---------------------------------------------------------------------------

def section_exec_summary(results: list[dict], date: str) -> str:
    total   = len(results)
    ok      = [r for r in results if r.get("ok") and not r.get("skipped")]
    skipped = [r for r in results if r.get("skipped")]
    errors  = [r for r in results if r.get("error") and not r.get("skipped")]

    total_bytes = sum(r.get("bytes", 0) for r in ok)
    est_tokens  = total_bytes // 4
    # Rough cost: assume $3/M input + $15/M output tokens, avg output ~1k tokens
    # This is a ballpark only — real cost requires API receipts
    est_cost_usd = round(est_tokens / 1_000_000 * 15, 4)

    latencies = [r["elapsed_s"] for r in ok]
    p50, p95  = p50_p95(latencies)
    avg_lat   = round(mean(latencies), 2) if latencies else 0.0

    pass_rate = safe_pct(len(ok), total - len(skipped))

    return f"""
    <div class="section" id="exec-summary">
      <h2>1. Executive Summary</h2>
      <div class="stat-grid">
        <div class="stat-card"><div class="stat-n">{total}</div><div class="stat-label">Total runs</div></div>
        <div class="stat-card ok"><div class="stat-n">{len(ok)}</div><div class="stat-label">Passed</div></div>
        <div class="stat-card err"><div class="stat-n">{len(errors)}</div><div class="stat-label">Errors</div></div>
        <div class="stat-card"><div class="stat-n">{pass_rate}</div><div class="stat-label">Pass rate</div></div>
        <div class="stat-card"><div class="stat-n">{est_tokens:,}</div><div class="stat-label">Est. tokens</div></div>
        <div class="stat-card"><div class="stat-n">${est_cost_usd}</div><div class="stat-label">Est. output cost</div></div>
        <div class="stat-card"><div class="stat-n">{p50}s</div><div class="stat-label">Latency p50</div></div>
        <div class="stat-card"><div class="stat-n">{p95}s</div><div class="stat-label">Latency p95</div></div>
      </div>
      <p class="note">Date: {date} &nbsp;|&nbsp; {len(skipped)} skipped (dry-run) &nbsp;|&nbsp; avg latency {avg_lat}s</p>
    </div>"""

def section_voice_alignment(results: list[dict]) -> str:
    va_results = [r for r in results if "voice_gates" in r]
    if not va_results:
        return '<div class="section" id="voice-alignment"><h2>2. Voice Alignment</h2><p class="muted">No voice alignment data (dry-run?).</p></div>'

    rows_html = ""
    for voice in VOICES:
        vr = [r for r in va_results if r.get("voice") == voice]
        if not vr:
            continue
        vp = sum(1 for r in vr if r.get("voice_aligned"))

        # Per-gate breakdown
        gate_names = list(vr[0]["voice_gates"].keys()) if vr else []
        gate_rows = ""
        for g in gate_names:
            gp = sum(1 for r in vr if r.get("voice_gates", {}).get(g))
            gc = len(vr)
            pct = safe_pct(gp, gc)
            cls = "ok" if gp == gc else ("warn" if gp >= gc * 0.7 else "err")
            gate_rows += f'<tr><td>{g}</td><td class="{cls}">{gp}/{gc} ({pct})</td></tr>'

        rows_html += f"""
        <div class="voice-block">
          <h3>{voice} &mdash; {vp}/{len(vr)} aligned ({safe_pct(vp, len(vr))})</h3>
          <table><thead><tr><th>Gate</th><th>Pass rate</th></tr></thead>
          <tbody>{gate_rows}</tbody></table>
        </div>"""

    overall = sum(1 for r in va_results if r.get("voice_aligned"))
    return f"""
    <div class="section" id="voice-alignment">
      <h2>2. Voice Alignment Results</h2>
      <p>Overall: <strong>{overall}/{len(va_results)} ({safe_pct(overall, len(va_results))})</strong> briefs passed all voice gates.</p>
      {rows_html}
    </div>"""

def section_performance(results: list[dict]) -> str:
    ok = [r for r in results if r.get("ok") and not r.get("skipped") and r.get("elapsed_s")]

    # By voice
    rows = ""
    for voice in VOICES:
        vr = [r for r in ok if r.get("voice") == voice]
        lats = [r["elapsed_s"] for r in vr]
        p50, p95 = p50_p95(lats)
        total_bytes = sum(r.get("bytes", 0) for r in vr)
        est_tok = total_bytes // 4
        rows += f'<tr><td>{voice}</td><td>{len(vr)}</td><td>{p50}s</td><td>{p95}s</td><td>{est_tok:,}</td></tr>'

    # By length
    rows2 = ""
    for length in LENGTHS:
        lr = [r for r in ok if r.get("length") == length]
        lats = [r["elapsed_s"] for r in lr]
        p50, p95 = p50_p95(lats)
        wcs = [r.get("metrics", {}).get("word_count", 0) for r in lr if r.get("metrics")]
        avg_wc = round(mean(wcs), 0) if wcs else 0
        rows2 += f'<tr><td>{length}</td><td>{len(lr)}</td><td>{p50}s</td><td>{p95}s</td><td>{int(avg_wc)}</td></tr>'

    return f"""
    <div class="section" id="performance">
      <h2>3. Performance Metrics</h2>
      <h3>By voice</h3>
      <table><thead><tr><th>Voice</th><th>Count</th><th>p50 latency</th><th>p95 latency</th><th>Est. tokens</th></tr></thead>
      <tbody>{rows}</tbody></table>
      <h3>By length</h3>
      <table><thead><tr><th>Length</th><th>Count</th><th>p50 latency</th><th>p95 latency</th><th>Avg word count</th></tr></thead>
      <tbody>{rows2}</tbody></table>
    </div>"""

def section_quality(results: list[dict]) -> str:
    has_metrics = [r for r in results if r.get("metrics")]
    if not has_metrics:
        return '<div class="section" id="quality"><h2>4. Quality Analysis</h2><p class="muted">No quality data (dry-run?).</p></div>'

    rows = ""
    for length in LENGTHS:
        lr = [r for r in has_metrics if r.get("length") == length]
        if not lr:
            continue
        wcs  = [r["metrics"]["word_count"] for r in lr]
        fks  = [r["metrics"]["fk_grade"]   for r in lr]
        hds  = [r["metrics"]["hedge_density"] for r in lr]
        wc_range = f"{min(wcs)}–{max(wcs)}"
        fk_avg   = round(mean(fks), 1)
        hd_avg   = round(mean(hds) * 100, 2)
        wc_ok    = sum(1 for r in lr if r.get("word_count_ok"))
        rows += f'<tr><td>{length}</td><td>{len(lr)}</td><td>{wc_range}</td><td>{fk_avg}</td><td>{hd_avg}%</td><td>{wc_ok}/{len(lr)}</td></tr>'

    # Lead types
    lead_counts: dict[str, int] = defaultdict(int)
    for r in has_metrics:
        lead_counts[r["metrics"].get("lead_type", "other")] += 1
    lead_rows = "".join(f'<tr><td>{k}</td><td>{v}</td></tr>' for k, v in sorted(lead_counts.items(), key=lambda x: -x[1]))

    return f"""
    <div class="section" id="quality">
      <h2>4. Quality Analysis</h2>
      <h3>Word count &amp; readability by length</h3>
      <table><thead><tr><th>Length</th><th>Count</th><th>Word count range</th><th>FK grade avg</th><th>Hedge density avg</th><th>WC gate pass</th></tr></thead>
      <tbody>{rows}</tbody></table>
      <h3>Lead sentence types</h3>
      <table><thead><tr><th>Type</th><th>Count</th></tr></thead>
      <tbody>{lead_rows}</tbody></table>
    </div>"""

def section_scalability(results: list[dict]) -> str:
    ok = [r for r in results if r.get("ok") and not r.get("skipped")]
    latencies = [r["elapsed_s"] for r in ok]
    p50, p95 = p50_p95(latencies)

    # Serial time for 1000 users at p50
    serial_1k = round(p50 * 1000 / 60, 1)
    # With 10 concurrent workers
    parallel_10_1k = round(serial_1k / 10, 1)

    # Bottleneck: anything > 2× p50 is slow
    slow = [r for r in ok if r.get("elapsed_s", 0) > p50 * 2.5]

    findings = []
    if p95 > 60:
        findings.append(f"p95 latency is {p95}s — some calls are slow. Consider timeout of 120s or retry logic.")
    if serial_1k > 120:
        findings.append(f"Serial generation for 1k users would take {serial_1k} minutes. Parallel workers required.")
    if not findings:
        findings.append("No critical scalability issues detected at this sample size.")

    findings_html = "".join(f"<li>{f}</li>" for f in findings)
    slow_html = "".join(f'<tr><td>{r["sub_id"]}</td><td>{r["elapsed_s"]}s</td><td>{r.get("voice")}/{r.get("depth")}/{r.get("length")}</td></tr>' for r in slow[:10]) or "<tr><td colspan='3'>None</td></tr>"

    return f"""
    <div class="section" id="scalability">
      <h2>5. Scalability Findings</h2>
      <div class="stat-grid">
        <div class="stat-card"><div class="stat-n">{p50}s</div><div class="stat-label">p50 latency</div></div>
        <div class="stat-card"><div class="stat-n">{p95}s</div><div class="stat-label">p95 latency</div></div>
        <div class="stat-card"><div class="stat-n">{serial_1k} min</div><div class="stat-label">1k users serial</div></div>
        <div class="stat-card ok"><div class="stat-n">{parallel_10_1k} min</div><div class="stat-label">1k users / 10 workers</div></div>
      </div>
      <h3>Findings</h3>
      <ul>{findings_html}</ul>
      <h3>Slow calls (&gt;2.5× p50)</h3>
      <table><thead><tr><th>Sub ID</th><th>Elapsed</th><th>Config</th></tr></thead>
      <tbody>{slow_html}</tbody></table>
    </div>"""

def section_errors(results: list[dict]) -> str:
    errors = [r for r in results if r.get("error") and not r.get("skipped")]
    if not errors:
        return '<div class="section" id="errors"><h2>6. Error Log</h2><p class="ok-text">No errors recorded.</p></div>'

    rows = "".join(
        f'<tr><td class="mono">{r["sub_id"]}</td>'
        f'<td>{r.get("voice")}/{r.get("depth")}/{r.get("length")}</td>'
        f'<td class="err-text">{r.get("error", "")[:120]}</td>'
        f'<td class="mono">{r.get("ts","")[:19]}</td></tr>'
        for r in errors[:50]
    )

    return f"""
    <div class="section" id="errors">
      <h2>6. Error Log</h2>
      <p>{len(errors)} error(s) recorded.</p>
      <table><thead><tr><th>Sub ID</th><th>Config</th><th>Error</th><th>Timestamp</th></tr></thead>
      <tbody>{rows}</tbody></table>
    </div>"""

def section_recommendations(results: list[dict]) -> str:
    ok = [r for r in results if r.get("ok") and not r.get("skipped")]
    va_results = [r for r in ok if "voice_gates" in r]
    errors = [r for r in results if r.get("error") and not r.get("skipped")]

    recs = []
    priority = 1

    # Voice alignment failures
    if va_results:
        fail_rate = 1 - sum(1 for r in va_results if r.get("voice_aligned")) / len(va_results)
        if fail_rate > 0.2:
            recs.append({
                "p":   "P1",
                "rec": "Voice alignment failure rate is high. Strengthen voice-specific instructions in compose_prompt() — particularly hedge word requirements for 'gentle' and sentence length caps for 'sharp'.",
            })

    # Word count drift
    wc_results = [r for r in ok if "word_count_ok" in r]
    if wc_results:
        wc_fail = sum(1 for r in wc_results if not r.get("word_count_ok"))
        if wc_fail / len(wc_results) > 0.15:
            recs.append({
                "p":   "P1",
                "rec": "Word count gate failing >15% of runs. Add explicit word count reminders to prompts or implement post-generation truncation.",
            })

    # High error rate
    non_skip = [r for r in results if not r.get("skipped")]
    if non_skip and len(errors) / len(non_skip) > 0.05:
        recs.append({
            "p":   "P1",
            "rec": f"Error rate is {round(len(errors)/len(non_skip)*100,1)}%. Add retry logic with exponential backoff in generate_for_sub().",
        })

    # Latency
    latencies = [r["elapsed_s"] for r in ok]
    if latencies:
        _, p95 = p50_p95(latencies)
        if p95 > 90:
            recs.append({
                "p":   "P2",
                "rec": f"p95 latency is {p95}s. Consider increasing --timeout and adding a progress heartbeat to detect stalled calls.",
            })

    # Hedge density for gentle
    gentle = [r for r in ok if r.get("voice") == "gentle" and r.get("metrics")]
    if gentle:
        low_hedge = [r for r in gentle if r["metrics"].get("hedge_density", 1) < 0.006]
        if len(low_hedge) / len(gentle) > 0.3:
            recs.append({
                "p":   "P2",
                "rec": "Gentle briefs have low hedge density. Prompt may need explicit instruction to use softer framing language.",
            })

    if not recs:
        recs.append({"p": "INFO", "rec": "No critical issues detected. Baseline quality is acceptable."})

    rows = "".join(
        f'<tr><td class="badge badge-{r["p"].lower()}">{r["p"]}</td><td>{r["rec"]}</td></tr>'
        for r in recs
    )

    return f"""
    <div class="section" id="recommendations">
      <h2>7. Recommendations</h2>
      <table><thead><tr><th>Priority</th><th>Recommendation</th></tr></thead>
      <tbody>{rows}</tbody></table>
    </div>"""

# ---------------------------------------------------------------------------
# HTML shell
# ---------------------------------------------------------------------------

def render_html(sections: list[str], date: str, total: int) -> str:
    body = "\n".join(sections)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Aurora Sim Analysis — {date}</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=DM+Mono:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    :root {{
      --bg: #0a0a12; --bg-card: #0f0f1a; --fg: #f2e2c4;
      --muted: rgba(242,226,196,0.55); --dim: rgba(242,226,196,0.32);
      --border: rgba(242,226,196,0.10);
      --accent: #e8b877; --ok: #a3c98a; --err: #e89070; --warn: #e8c96a;
      --font-b: 'Inter', sans-serif; --font-m: 'DM Mono', monospace;
    }}
    html {{ background: var(--bg); color: var(--fg); }}
    body {{ font-family: var(--font-b); max-width: 960px; margin: 0 auto; padding: 40px 28px 80px; font-size: 14px; line-height: 1.7; }}
    h1 {{ font-size: 26px; font-weight: 700; letter-spacing: -0.02em; color: var(--fg); margin-bottom: 6px; }}
    h2 {{ font-size: 16px; font-weight: 700; letter-spacing: -0.01em; color: var(--accent); text-transform: uppercase; letter-spacing: 0.08em; margin: 0 0 18px; padding-bottom: 10px; border-bottom: 1px solid var(--border); }}
    h3 {{ font-size: 14px; font-weight: 600; color: var(--fg); margin: 24px 0 12px; }}
    p {{ color: var(--muted); margin-bottom: 14px; }}
    .header {{ margin-bottom: 40px; padding-bottom: 24px; border-bottom: 1px solid var(--border); }}
    .header .sub {{ font-family: var(--font-m); font-size: 11px; color: var(--dim); letter-spacing: 0.12em; text-transform: uppercase; margin-top: 6px; }}
    .toc {{ display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 36px; }}
    .toc a {{ font-family: var(--font-m); font-size: 10px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--dim); border: 1px solid var(--border); padding: 5px 12px; border-radius: 4px; text-decoration: none; transition: all 0.2s; }}
    .toc a:hover {{ color: var(--accent); border-color: rgba(232,184,119,0.3); }}
    .section {{ background: var(--bg-card); border: 1px solid var(--border); border-radius: 12px; padding: 28px 32px; margin-bottom: 20px; }}
    .stat-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 12px; margin-bottom: 20px; }}
    .stat-card {{ background: rgba(255,255,255,0.03); border: 1px solid var(--border); border-radius: 8px; padding: 16px 18px; text-align: center; }}
    .stat-card.ok {{ border-color: rgba(163,201,138,0.3); }}
    .stat-card.err {{ border-color: rgba(232,144,112,0.3); }}
    .stat-n {{ font-size: 24px; font-weight: 700; color: var(--accent); font-family: var(--font-m); margin-bottom: 4px; }}
    .stat-card.ok .stat-n {{ color: var(--ok); }}
    .stat-card.err .stat-n {{ color: var(--err); }}
    .stat-label {{ font-size: 11px; color: var(--dim); text-transform: uppercase; letter-spacing: 0.1em; }}
    .note {{ font-family: var(--font-m); font-size: 11px; color: var(--dim); }}
    table {{ width: 100%; border-collapse: collapse; margin-bottom: 20px; font-size: 13px; }}
    th {{ font-family: var(--font-m); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--dim); background: rgba(255,255,255,0.02); padding: 10px 12px; text-align: left; border-bottom: 1px solid var(--border); }}
    td {{ padding: 9px 12px; border-bottom: 1px solid rgba(242,226,196,0.05); color: var(--muted); }}
    td.ok {{ color: var(--ok); }}
    td.err {{ color: var(--err); }}
    td.warn {{ color: var(--warn); }}
    td.mono {{ font-family: var(--font-m); font-size: 11px; }}
    td.ok-text {{ color: var(--ok); }}
    td.err-text {{ color: var(--err); font-size: 12px; }}
    .voice-block {{ margin-bottom: 24px; }}
    .muted {{ color: var(--dim); font-style: italic; }}
    ul {{ padding-left: 20px; }}
    li {{ color: var(--muted); margin-bottom: 6px; }}
    .badge {{ font-family: var(--font-m); font-size: 9px; letter-spacing: 0.12em; text-transform: uppercase; padding: 3px 8px; border-radius: 4px; font-weight: 700; white-space: nowrap; }}
    .badge-p1 {{ background: rgba(232,144,112,0.2); color: var(--err); }}
    .badge-p2 {{ background: rgba(232,201,106,0.15); color: var(--warn); }}
    .badge-info {{ background: rgba(163,201,138,0.15); color: var(--ok); }}
    .ok-text {{ color: var(--ok); }}
    @media (max-width: 600px) {{
      body {{ padding: 24px 14px 60px; }}
      .section {{ padding: 20px 18px; }}
      .stat-grid {{ grid-template-columns: repeat(2, 1fr); }}
    }}
  </style>
</head>
<body>
  <div class="header">
    <h1>Aurora Sim Analysis</h1>
    <div class="sub">{date} &nbsp;·&nbsp; {total} runs &nbsp;·&nbsp; aurora.hyo.world</div>
  </div>
  <div class="toc">
    <a href="#exec-summary">1. Summary</a>
    <a href="#voice-alignment">2. Voice Alignment</a>
    <a href="#performance">3. Performance</a>
    <a href="#quality">4. Quality</a>
    <a href="#scalability">5. Scalability</a>
    <a href="#errors">6. Errors</a>
    <a href="#recommendations">7. Recommendations</a>
  </div>
  {body}
  <p class="note" style="margin-top:32px;text-align:center;">Generated by sim-report-template.py · Aurora / Hyo · {date}</p>
</body>
</html>"""

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Aurora sim report generator")
    ap.add_argument("--input",  default=str(SIM_RESULTS), help="Path to sim-results.jsonl")
    ap.add_argument("--date",   default=None,              help="Report date label (YYYY-MM-DD, default: today)")
    ap.add_argument("--last-n", type=int, default=None,    help="Only use last N result entries")
    ap.add_argument("--out",    default=None,              help="Output HTML file path (default: auto)")
    args = ap.parse_args()

    date = args.date or dt.date.today().isoformat()

    results_path = Path(args.input)
    results = load_results(results_path, args.last_n)

    if not results:
        print(f"[sim-report] No results found in {results_path}. Run aurora-sim.py first.", file=sys.stderr)
        return 1

    print(f"[sim-report] {len(results)} result entries loaded from {results_path}")

    # Filter to requested date if results span multiple dates
    date_results = [r for r in results if r.get("date") == date]
    if date_results:
        print(f"[sim-report] Filtering to {date}: {len(date_results)} entries")
        results = date_results
    else:
        print(f"[sim-report] No results for {date} — using all {len(results)} entries")

    sections = [
        section_exec_summary(results, date),
        section_voice_alignment(results),
        section_performance(results),
        section_quality(results),
        section_scalability(results),
        section_errors(results),
        section_recommendations(results),
    ]

    html = render_html(sections, date, len(results))

    # Output path
    if args.out:
        out_path = Path(args.out)
    else:
        out_name = f"aurora-sim-analysis-{date}.html"
        WEBSITE_DAILY.mkdir(parents=True, exist_ok=True)
        out_path = WEBSITE_DAILY / out_name

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html)
    print(f"[sim-report] Report written → {out_path}")

    # Dual-path sync
    if args.out is None:
        WEBSITE_DAILY2.mkdir(parents=True, exist_ok=True)
        dual = WEBSITE_DAILY2 / out_path.name
        dual.write_text(html)
        print(f"[sim-report] Dual-path sync  → {dual}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
