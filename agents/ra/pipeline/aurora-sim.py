#!/usr/bin/env python3
"""
aurora-sim.py — Aurora generation simulator.

Runs Aurora brief generation for a set of sim users, measuring cost,
latency, quality metrics, and voice alignment.

Usage:
    python3 aurora-sim.py --users sim-users.json --count 10        # one brief per user
    python3 aurora-sim.py --users sim-users.json --hours 7         # 7 simulated daily runs
    python3 aurora-sim.py --combos all                              # all 27 voice/depth/length combos
    python3 aurora-sim.py --users sim-users.json --dry-run         # validate without LLM calls

Output:
    agents/ra/pipeline/sim-results.jsonl  — per-run JSONL log
    Prints a summary report to stdout at completion.

Voice alignment gates (from ra voice research):
    FK Grade level     — Flesch-Kincaid proxy (readability)
    Sentence count     — structural length check
    Avg sentence len   — words per sentence
    Hedge density      — "perhaps", "might", "could", "seems", "appears", etc.
    Lead sentence type — italic opener = aurora style, direct assertion = sharp, qualifier = gentle
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
from itertools import product
from pathlib import Path
from typing import Generator

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

# aurora_public provides all generation logic
import aurora_public  # type: ignore  # noqa: E402
import synthesize     # type: ignore  # noqa: E402

SIM_RESULTS = HERE / "sim-results.jsonl"

# ---------------------------------------------------------------------------
# voice / depth / length combos
# ---------------------------------------------------------------------------

VOICES  = ["gentle", "balanced", "sharp"]
DEPTHS  = ["headlines", "balanced", "deep-dives"]
LENGTHS = ["3min", "6min", "12min"]

# Expected word count ranges per length (from aurora_public LENGTH_TARGETS)
EXPECTED_WORDS = {
    "3min":  (350, 600),
    "6min":  (800, 1300),
    "12min": (1600, 2500),
}

# ---------------------------------------------------------------------------
# quality metric extractors
# ---------------------------------------------------------------------------

HEDGE_WORDS = {
    "perhaps", "might", "could", "seems", "appears", "arguably",
    "somewhat", "possibly", "probably", "may", "likely", "suggest",
    "would suggest", "it's worth noting", "it seems",
}

def _strip_frontmatter(text: str) -> str:
    return re.sub(r'^---[\s\S]*?---\n?', '', text).strip()

def _sentences(body: str) -> list[str]:
    """Split body into sentences (rough heuristic)."""
    # Split on . ! ? followed by whitespace or end
    parts = re.split(r'(?<=[.!?])\s+', body.strip())
    return [p.strip() for p in parts if p.strip() and len(p.strip()) > 8]

def _words(body: str) -> list[str]:
    return re.findall(r'\b[a-zA-Z]+\b', body.lower())

def compute_fk_grade(body: str) -> float:
    """Flesch-Kincaid Grade Level approximation (pure Python, no syllable dict)."""
    sents = _sentences(body)
    words = _words(body)
    if not sents or not words:
        return 0.0
    num_words = len(words)
    num_sents = len(sents)
    # Approximate syllables: count vowel groups
    total_syllables = sum(max(1, len(re.findall(r'[aeiou]+', w))) for w in words)
    fk = 0.39 * (num_words / num_sents) + 11.8 * (total_syllables / num_words) - 15.59
    return round(fk, 2)

def hedge_density(body: str) -> float:
    """Fraction of words that are hedge words."""
    words = _words(body)
    if not words:
        return 0.0
    count = sum(1 for w in words if w in HEDGE_WORDS)
    return round(count / len(words), 4)

def lead_sentence_type(text: str) -> str:
    """
    Classify the opening sentence of the brief body:
      'italic'    — starts with *, suggests aurora-style poetic opener
      'assertion' — direct declarative (sharp style)
      'question'  — opens with a question
      'qualifier' — starts with hedge word (gentle style)
      'other'     — anything else
    """
    body = _strip_frontmatter(text).strip()
    if body.startswith('*') or body.startswith('_'):
        return 'italic'
    sents = _sentences(body)
    if not sents:
        return 'other'
    first = sents[0].lower().strip()
    if first.endswith('?'):
        return 'question'
    if any(first.startswith(h) for h in HEDGE_WORDS):
        return 'qualifier'
    return 'assertion'

def quality_metrics(text: str) -> dict:
    body = _strip_frontmatter(text)
    sents = _sentences(body)
    words = _words(body)
    wc = len(words)
    sc = len(sents)
    avg_sl = round(wc / sc, 1) if sc else 0.0
    return {
        "word_count":       wc,
        "sentence_count":   sc,
        "avg_sentence_len": avg_sl,
        "fk_grade":         compute_fk_grade(body),
        "hedge_density":    hedge_density(body),
        "lead_type":        lead_sentence_type(text),
    }

# ---------------------------------------------------------------------------
# voice alignment gates
# ---------------------------------------------------------------------------
#
# Reference thresholds derived from Ra voice research (2026-04).
# FK Grade: sharp → 8-11, balanced → 10-13, gentle → 11-15
# Hedge density: gentle > 0.008, balanced 0.004-0.012, sharp < 0.006
# Avg sentence length: sharp < 15, balanced 14-18, gentle 15-20
# Lead type: sharp → assertion, gentle → italic/qualifier, balanced → any

VOICE_GATES: dict[str, dict] = {
    "gentle": {
        "fk_grade_min":     10.0,
        "fk_grade_max":     16.0,
        "avg_sentence_min": 13.0,
        "avg_sentence_max": 22.0,
        "hedge_min":        0.006,
        "ok_lead_types":    {"italic", "qualifier", "assertion", "question", "other"},
    },
    "balanced": {
        "fk_grade_min":     9.0,
        "fk_grade_max":     14.0,
        "avg_sentence_min": 12.0,
        "avg_sentence_max": 20.0,
        "hedge_min":        0.003,
        "ok_lead_types":    {"italic", "assertion", "question", "qualifier", "other"},
    },
    "sharp": {
        "fk_grade_min":     7.0,
        "fk_grade_max":     12.0,
        "avg_sentence_min": 8.0,
        "avg_sentence_max": 17.0,
        "hedge_max":        0.008,
        "ok_lead_types":    {"italic", "assertion", "question", "other"},
    },
}

def voice_alignment(metrics: dict, voice: str) -> dict[str, bool]:
    """
    Returns a dict of gate_name → passed (bool).
    All gates must pass for overall voice alignment.
    """
    g = VOICE_GATES.get(voice, {})
    results: dict[str, bool] = {}

    fk = metrics.get("fk_grade", 0.0)
    if "fk_grade_min" in g:
        results["fk_grade_min"] = fk >= g["fk_grade_min"]
    if "fk_grade_max" in g:
        results["fk_grade_max"] = fk <= g["fk_grade_max"]

    asl = metrics.get("avg_sentence_len", 0.0)
    if "avg_sentence_min" in g:
        results["avg_sentence_min"] = asl >= g["avg_sentence_min"]
    if "avg_sentence_max" in g:
        results["avg_sentence_max"] = asl <= g["avg_sentence_max"]

    hd = metrics.get("hedge_density", 0.0)
    if "hedge_min" in g:
        results["hedge_density_min"] = hd >= g["hedge_min"]
    if "hedge_max" in g:
        results["hedge_density_max"] = hd <= g["hedge_max"]

    lead = metrics.get("lead_type", "other")
    if "ok_lead_types" in g:
        results["lead_type"] = lead in g["ok_lead_types"]

    return results

# ---------------------------------------------------------------------------
# word count gate
# ---------------------------------------------------------------------------

def word_count_gate(wc: int, length: str) -> bool:
    lo, hi = EXPECTED_WORDS.get(length, (0, 99999))
    return lo <= wc <= hi

# ---------------------------------------------------------------------------
# brief generation wrapper (wraps aurora_public.generate_for_sub)
# ---------------------------------------------------------------------------

def run_one(sub: dict, records: list[dict], date: str,
            context_md: str | None, backend: str, model: str,
            timeout: int, dry_run: bool) -> dict:
    """Run generation for one subscriber and return a structured result."""
    interests = sub.get("interests", {})
    voice  = interests.get("voice", "balanced")
    depth  = interests.get("depth", "balanced")
    length = interests.get("length", "6min")

    t0 = time.time()
    result = aurora_public.generate_for_sub(
        sub=sub, records=records, date=date,
        context_md=context_md, backend=backend,
        model=model, timeout=timeout, dry_run=dry_run,
    )
    elapsed = round(time.time() - t0, 2)

    entry: dict = {
        "ts":        dt.datetime.now(dt.timezone.utc).isoformat(),
        "sub_id":    sub["id"],
        "voice":     voice,
        "depth":     depth,
        "length":    length,
        "date":      date,
        "backend":   backend,
        "model":     model,
        "elapsed_s": elapsed,
        "ok":        result is not None and not result.get("error"),
        "error":     result.get("error") if result else "generate_for_sub returned None",
        "skipped":   result.get("skipped", False) if result else False,
        "bytes":     result.get("bytes", 0) if result else 0,
        "matched_records": result.get("matched", 0) if result else 0,
    }

    # Read generated file and compute quality metrics
    if not dry_run and result and result.get("path") and not result.get("error"):
        try:
            text = Path(result["path"]).read_text()
            qm = quality_metrics(text)
            va = voice_alignment(qm, voice)
            wc_ok = word_count_gate(qm["word_count"], length)
            entry["metrics"]           = qm
            entry["voice_gates"]       = va
            entry["voice_aligned"]     = all(va.values())
            entry["word_count_ok"]     = wc_ok
            entry["quality_pass"]      = entry["voice_aligned"] and wc_ok
        except Exception as e:
            entry["metrics_error"] = str(e)

    return entry

# ---------------------------------------------------------------------------
# user generators
# ---------------------------------------------------------------------------

def users_from_file(path: Path, count: int | None = None) -> list[dict]:
    subs = json.loads(path.read_text())
    if count:
        subs = subs[:count]
    return subs


def combo_users() -> list[dict]:
    """Generate synthetic users for all 27 voice/depth/length combos."""
    users = []
    for i, (v, d, l) in enumerate(product(VOICES, DEPTHS, LENGTHS), start=1):
        users.append({
            "id":    f"sim_combo_{i:03d}",
            "name":  f"Combo User {i}",
            "email": f"combo{i:03d}@sim.hyo.world",
            "status": "active",
            "interests": {
                "voice":    v,
                "depth":    d,
                "length":   l,
                "topics":   ["ai", "tech", "finance", "politics", "health"],
                "freetext": f"combo test user {i}: {v}/{d}/{l}",
            },
        })
    return users

# ---------------------------------------------------------------------------
# summary report generator
# ---------------------------------------------------------------------------

def generate_summary(results: list[dict]) -> str:
    total   = len(results)
    ok      = sum(1 for r in results if r.get("ok") and not r.get("skipped"))
    skipped = sum(1 for r in results if r.get("skipped"))
    errors  = sum(1 for r in results if r.get("error") and not r.get("skipped"))

    # Cost proxy: estimate tokens from bytes (rough: 1 token ≈ 4 bytes)
    total_bytes = sum(r.get("bytes", 0) for r in results)
    est_tokens  = total_bytes // 4

    latencies = [r["elapsed_s"] for r in results if r.get("ok") and not r.get("skipped")]
    p50 = sorted(latencies)[len(latencies)//2] if latencies else 0.0
    p95 = sorted(latencies)[int(len(latencies)*0.95)] if latencies else 0.0

    # Voice alignment
    va_results = [r for r in results if "voice_gates" in r]
    va_pass    = sum(1 for r in va_results if r.get("voice_aligned"))

    # Word count gate
    wc_results = [r for r in results if "word_count_ok" in r]
    wc_pass    = sum(1 for r in wc_results if r.get("word_count_ok"))

    lines = [
        "",
        "═" * 60,
        "  AURORA SIM SUMMARY",
        "═" * 60,
        f"  Total runs     : {total}",
        f"  OK             : {ok}",
        f"  Skipped (dry)  : {skipped}",
        f"  Errors         : {errors}",
        f"  Pass rate       : {round(ok / max(total - skipped, 1) * 100, 1)}%",
        "",
        f"  Estimated tokens: {est_tokens:,}",
        f"  Latency p50     : {p50:.1f}s",
        f"  Latency p95     : {p95:.1f}s",
        "",
    ]

    if va_results:
        va_rate = round(va_pass / len(va_results) * 100, 1)
        lines.append(f"  Voice alignment : {va_pass}/{len(va_results)} ({va_rate}%)")
    if wc_results:
        wc_rate = round(wc_pass / len(wc_results) * 100, 1)
        lines.append(f"  Word count gate : {wc_pass}/{len(wc_results)} ({wc_rate}%)")

    # Per-voice breakdown
    if va_results:
        lines.append("")
        lines.append("  Per-voice alignment:")
        for v in VOICES:
            vr = [r for r in va_results if r.get("voice") == v]
            if vr:
                vp = sum(1 for r in vr if r.get("voice_aligned"))
                lines.append(f"    {v:10s}: {vp}/{len(vr)} ({round(vp/len(vr)*100,1)}%)")

    # Errors
    err_list = [r for r in results if r.get("error") and not r.get("skipped")]
    if err_list:
        lines.append("")
        lines.append(f"  Errors ({len(err_list)}):")
        for r in err_list[:10]:
            lines.append(f"    {r['sub_id']} [{r.get('voice')}/{r.get('depth')}/{r.get('length')}]: {r['error']}")

    lines.append("═" * 60)
    lines.append("")
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Aurora simulation runner")
    ap.add_argument("--users",    default=str(HERE / "sim-users.json"), help="Path to sim users JSON file")
    ap.add_argument("--count",    type=int, default=None,    help="Max users to run (default: all)")
    ap.add_argument("--hours",    type=int, default=None,    help="Simulate N hourly runs for each user")
    ap.add_argument("--combos",   default=None,              help="Use 'all' to test all 27 voice/depth/length combos")
    ap.add_argument("--date",     default=None,              help="YYYY-MM-DD (default: today)")
    ap.add_argument("--backend",  default=None,              help="Force LLM backend")
    ap.add_argument("--timeout",  type=int, default=240,     help="Per-call timeout seconds")
    ap.add_argument("--dry-run",  action="store_true",       help="Skip LLM calls, validate user set only")
    ap.add_argument("--no-log",   action="store_true",       help="Don't write to sim-results.jsonl")
    args = ap.parse_args()

    date = args.date or dt.date.today().isoformat()

    # Determine user list
    if args.combos == "all":
        subs = combo_users()
        print(f"[aurora-sim] combo mode: {len(subs)} users × all voice/depth/length combos")
    else:
        users_path = Path(args.users)
        if not users_path.exists():
            print(f"[aurora-sim] ERROR: users file not found: {users_path}", file=sys.stderr)
            return 1
        subs = users_from_file(users_path, args.count)
        print(f"[aurora-sim] loaded {len(subs)} users from {users_path}")

    if not subs:
        print("[aurora-sim] No users to run. Exiting.")
        return 0

    # Pick LLM backend
    backend, model = synthesize.pick_backend(args.backend)
    if backend == "bundle" and not args.dry_run:
        print("[aurora-sim] No LLM backend available. Use --dry-run or set ANTHROPIC_API_KEY.", file=sys.stderr)
        return 2
    print(f"[aurora-sim] backend={backend} model={model} date={date} dry_run={args.dry_run}")

    # Load gather records
    records = aurora_public.load_all_records(date)
    print(f"[aurora-sim] {len(records)} gather records for {date}")

    # Load optional context
    context_md: str | None = None
    if aurora_public.CONTEXT_FILE.exists():
        context_md = aurora_public.CONTEXT_FILE.read_text()

    # Run simulation
    all_results: list[dict] = []

    if args.hours:
        # Simulate N consecutive daily runs (different dates)
        for h in range(args.hours):
            run_date = (dt.date.fromisoformat(date) + dt.timedelta(days=h)).isoformat()
            print(f"\n[aurora-sim] ── Simulated day {h+1}: {run_date} ──")
            for sub in subs:
                entry = run_one(sub, records, run_date, context_md, backend, model, args.timeout, args.dry_run)
                entry["sim_run"] = h + 1
                all_results.append(entry)
                status = "OK" if entry["ok"] else ("SKIP" if entry["skipped"] else "ERR")
                va = entry.get("voice_aligned")
                va_str = f" voice={'PASS' if va else 'FAIL'}" if va is not None else ""
                print(f"  {entry['sub_id']} [{entry['voice']}/{entry['depth']}/{entry['length']}] {status}{va_str} {entry['elapsed_s']:.1f}s")
    else:
        for sub in subs:
            entry = run_one(sub, records, date, context_md, backend, model, args.timeout, args.dry_run)
            all_results.append(entry)
            status = "OK" if entry["ok"] else ("SKIP" if entry["skipped"] else "ERR")
            va = entry.get("voice_aligned")
            va_str = f" voice={'PASS' if va else 'FAIL'}" if va is not None else ""
            print(f"[aurora-sim] {entry['sub_id']} [{entry['voice']}/{entry['depth']}/{entry['length']}] {status}{va_str} {entry['elapsed_s']:.1f}s")

    # Write results log
    if not args.no_log:
        with SIM_RESULTS.open("a") as f:
            for entry in all_results:
                f.write(json.dumps(entry) + "\n")
        print(f"\n[aurora-sim] {len(all_results)} results appended → {SIM_RESULTS}")

    # Print summary
    print(generate_summary(all_results))

    errors = sum(1 for r in all_results if r.get("error") and not r.get("skipped"))
    return 0 if errors == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
