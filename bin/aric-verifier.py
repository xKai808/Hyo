#!/usr/bin/env python3
"""
bin/aric-verifier.py — Adversarial ARIC Phase 7.5 Verifier

ARCHITECTURE: Based on GVU Operator (arXiv:2512.02731), Constitutional AI
(Anthropic 2022), D3 Debate Framework (arXiv:2410.04663), MAR (arXiv:2512.20845).

WHAT IT DOES:
  Challenges the agent's ARIC improvement plan with adversarial critique before
  execution is permitted. The verifier is architecturally separate from the
  generator — it cannot share the same reasoning session that produced the plan.

  The GVU Variance Inequality proves that self-verification produces noise
  exceeding signal (improvement diverges). Fix: strengthen the Verifier.

  The verifier asks 5 adversarial questions the agent cannot ask itself:
  1. What could go wrong with this plan?
  2. What assumption is most likely false?
  3. Would a skeptic believe this will actually improve anything? Why not?
  4. What evidence would prove this is NOT working?
  5. Is there a simpler fix the agent didn't consider?

SCORING:
  Each question scored 0-20. Total 0-100. Gate at 70.
  Below 70 → plan blocked from advancing to execution (REQUIRES_REVISION)
  Above 70 → APPROVED with critique notes appended for agent context

MODES:
  --llm: Use Claude API for adversarial critique (requires ANTHROPIC_API_KEY)
  --heuristic: Use rule-based heuristics (free, offline, less sharp)

USAGE:
  python3 bin/aric-verifier.py --agent nel --plan-file agents/nel/research/aric-latest.json
  python3 bin/aric-verifier.py --agent nel --heuristic

OUTPUT:
  Writes critique to agents/<name>/research/aric-verifier-latest.json
  Exits 0 = APPROVED, 1 = REQUIRES_REVISION, 2 = ERROR

VERSION: 1.0 — 2026-04-27
SOURCES:
  - arXiv:2512.02731 (GVU Operator, Variance Inequality)
  - arXiv:2212.08073 (Constitutional AI, critique-revision)
  - arXiv:2410.04663 (D3 Debate Framework)
  - arXiv:2512.20845 (MAR, adversarial challenge)
  - arXiv:2602.13213 (adversarial self-critique, hallucination reduction 11.3%→3.8%)
"""

import json
import sys
import os
import argparse
import time
from pathlib import Path
from datetime import datetime, timezone

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
PASS_THRESHOLD = 70  # Gate: below this → REQUIRES_REVISION
KNOWN_ISSUES = os.path.join(ROOT, "kai/ledger/known-issues.jsonl")
SESSION_ERRORS = os.path.join(ROOT, "kai/ledger/session-errors.jsonl")


ADVERSARIAL_PROMPT = """You are a skeptical adversarial reviewer. Your job is to find everything that could go wrong with this agent improvement plan.

You are NOT the agent. You are NOT trying to be helpful to the agent. You are trying to find the flaws that the agent is too close to see.

AGENT: {agent}
WEAKNESS BEING ADDRESSED: {weakness}
IMPROVEMENT PLAN: {plan}
RESEARCH CITED: {research}
EXPECTED OUTCOME: {expected_outcome}

Answer each question with specific, evidence-based critique. Do not be polite. Be precise.

Q1 (0-20): What specific things could go wrong when this plan is executed?
Q2 (0-20): What assumption in this plan is most likely false? What evidence contradicts it?
Q3 (0-20): Why would a skeptic believe this improvement will not actually move the metric? What alternative explanation exists for the weakness?
Q4 (0-20): What would failing look like? What measurement would prove this didn't work?
Q5 (0-20): What simpler fix would address the same weakness without this plan's risks?

SCORING: For each question, award 0-20 based on how well the plan survives the challenge.
- 0-8: Plan collapses under this challenge — fundamental flaw
- 9-15: Plan has issues but could be fixed with revisions
- 16-20: Plan survives this challenge — solid answer exists

Respond in JSON:
{{
  "q1_critique": "...",
  "q1_score": <0-20>,
  "q2_critique": "...",
  "q2_score": <0-20>,
  "q3_critique": "...",
  "q3_score": <0-20>,
  "q4_critique": "...",
  "q4_score": <0-20>,
  "q5_critique": "...",
  "q5_score": <0-20>,
  "total_score": <sum of q1-q5>,
  "blocking_flaws": ["list of critical flaws that must be fixed before execution"],
  "verdict": "APPROVED" or "REQUIRES_REVISION",
  "revision_instructions": "Specific changes the agent must make before re-submitting"
}}"""


def load_aric(agent, plan_file=None):
    """Load the agent's ARIC latest JSON."""
    if plan_file:
        path = plan_file
    else:
        path = os.path.join(ROOT, "agents", agent, "research", "aric-latest.json")
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"[aric-verifier] ERROR: Cannot load plan: {e}", file=sys.stderr)
        return None


def load_known_issues():
    """Load known failure patterns to inform adversarial critique."""
    issues = []
    try:
        with open(KNOWN_ISSUES) as f:
            for line in f:
                try:
                    issues.append(json.loads(line))
                except Exception:
                    pass
    except FileNotFoundError:
        pass
    return issues


def heuristic_verify(agent, aric_data):
    """Rule-based adversarial critique — no API needed, always available."""
    scores = {}
    critiques = {}
    blocking_flaws = []

    plan = aric_data.get("improvement_built", {}) or {}
    weakness = aric_data.get("weakness_worked", "")
    research = aric_data.get("research_conducted", [])
    metric_before = aric_data.get("metric_before", "")
    metric_after = aric_data.get("metric_after", "")
    cycle_date = aric_data.get("cycle_date", "")
    files_changed = plan.get("files_changed", [])
    commit = plan.get("commit", "")
    status = plan.get("status", "")
    description = plan.get("description", "")

    # ── Q1: What could go wrong? ──────────────────────────────────────────────
    q1_score = 15  # default: passable
    q1_critique = "Heuristic: no automated execution path failure analysis available."
    if not files_changed:
        q1_score = 5
        q1_critique = "CRITICAL: Plan has no files_changed — no implementation target. What exactly is being built and where?"
        blocking_flaws.append("No files_changed specified — plan is unexecutable")
    elif not description:
        q1_score = 8
        q1_critique = "WARNING: No description of what the improvement does. Cannot assess failure modes without knowing what is changing."
    scores["q1"] = q1_score
    critiques["q1"] = q1_critique

    # ── Q2: False assumption ──────────────────────────────────────────────────
    q2_score = 15
    q2_critique = "Heuristic: assumption analysis not available without LLM."
    if len(research) < 3:
        q2_score = 6
        q2_critique = f"CRITICAL: Only {len(research)} source(s) cited. Research requires minimum 3 sources per finding. The assumption that this fix is correct is based on insufficient evidence."
        blocking_flaws.append(f"Insufficient research: only {len(research)} sources (min 3 required)")
    elif len(research) < 1:
        q2_score = 2
        q2_critique = "CRITICAL: Zero research sources. This plan is pure intuition."
        blocking_flaws.append("Zero research sources — plan is unsupported assertion")
    scores["q2"] = q2_score
    critiques["q2"] = q2_critique

    # ── Q3: Skeptic challenge ─────────────────────────────────────────────────
    q3_score = 12
    q3_critique = "Heuristic: skeptical challenge requires human or LLM judgment."
    if not weakness:
        q3_score = 4
        q3_critique = "CRITICAL: No weakness_worked identified. What is this improvement fixing? Without a clearly stated problem, improvement is unmeasurable."
        blocking_flaws.append("No weakness_worked — unclear what problem is being solved")
    scores["q3"] = q3_score
    critiques["q3"] = q3_critique

    # ── Q4: What would failing look like? ────────────────────────────────────
    q4_score = 12
    q4_critique = "Heuristic: failure measurement check."
    if not metric_before:
        q4_score = 5
        q4_critique = "CRITICAL: No metric_before recorded. Without a baseline, there is no way to determine if this improvement worked. Metric is required before execution."
        blocking_flaws.append("No metric_before — cannot prove improvement without baseline")
    elif not metric_after:
        q4_score = 10
        q4_critique = "WARNING: No metric_after defined yet. Must define success criteria before execution begins."
    scores["q4"] = q4_score
    critiques["q4"] = q4_critique

    # ── Q5: Simpler fix? ─────────────────────────────────────────────────────
    q5_score = 14
    q5_critique = "Heuristic: simplicity audit."
    if status not in ("shipped", "in_progress", "in progress", "researched", "defined"):
        q5_score = 8
        q5_critique = f"WARNING: Improvement status is '{status}' — not a recognized execution state. May indicate the plan is not concrete enough to execute."
    scores["q5"] = q5_score
    critiques["q5"] = q5_critique

    # ── Stale data check ─────────────────────────────────────────────────────
    if cycle_date:
        try:
            from datetime import datetime, timezone, timedelta
            age_days = (datetime.now(timezone.utc).date() -
                        datetime.strptime(cycle_date, "%Y-%m-%d").date()).days
            if age_days > 3:
                blocking_flaws.append(f"Stale ARIC data: cycle_date={cycle_date} ({age_days} days old). Research must be current before execution.")
                for k in scores:
                    scores[k] = min(scores[k], 10)
        except Exception:
            pass

    total = sum(scores.values())
    verdict = "APPROVED" if total >= PASS_THRESHOLD and not blocking_flaws else "REQUIRES_REVISION"

    return {
        "q1_critique": critiques["q1"], "q1_score": scores["q1"],
        "q2_critique": critiques["q2"], "q2_score": scores["q2"],
        "q3_critique": critiques["q3"], "q3_score": scores["q3"],
        "q4_critique": critiques["q4"], "q4_score": scores["q4"],
        "q5_critique": critiques["q5"], "q5_score": scores["q5"],
        "total_score": total,
        "blocking_flaws": blocking_flaws,
        "verdict": verdict,
        "mode": "heuristic",
        "revision_instructions": (
            "Fix all blocking flaws before re-submitting: " + "; ".join(blocking_flaws)
            if blocking_flaws else "No critical revisions required."
        )
    }


def llm_verify(agent, aric_data, api_key):
    """LLM-backed adversarial critique using Claude API."""
    try:
        import anthropic
        client = anthropic.Anthropic(api_key=api_key)

        plan = aric_data.get("improvement_built", {}) or {}
        research = aric_data.get("research_conducted", [])
        research_str = "\n".join([
            f"- {r.get('source', '?')}: {r.get('finding', '?')[:100]}"
            for r in research[:5]
        ])

        prompt = ADVERSARIAL_PROMPT.format(
            agent=agent,
            weakness=aric_data.get("weakness_worked", "Not specified"),
            plan=json.dumps(plan, indent=2)[:800],
            research=research_str or "No research cited",
            expected_outcome=f"{aric_data.get('metric_before', '?')} → {aric_data.get('metric_after', '?')}"
        )

        response = client.messages.create(
            model="claude-haiku-4-5-20251001",  # Fast, cheap for critique
            max_tokens=1200,
            messages=[{"role": "user", "content": prompt}]
        )

        text = response.content[0].text.strip()
        # Extract JSON from response
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0].strip()
        elif "```" in text:
            text = text.split("```")[1].split("```")[0].strip()

        result = json.loads(text)
        result["mode"] = "llm-claude-haiku"
        return result

    except ImportError:
        print("[aric-verifier] anthropic not installed, falling back to heuristic", file=sys.stderr)
        return heuristic_verify(agent, aric_data)
    except Exception as e:
        print(f"[aric-verifier] LLM critique failed ({e}), falling back to heuristic", file=sys.stderr)
        return heuristic_verify(agent, aric_data)


def write_result(agent, result, aric_data):
    """Write verifier output to agents/<name>/research/aric-verifier-latest.json"""
    out_path = os.path.join(ROOT, "agents", agent, "research", "aric-verifier-latest.json")
    output = {
        "agent": agent,
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "cycle_date": aric_data.get("cycle_date", "unknown"),
        "weakness_worked": aric_data.get("weakness_worked", ""),
        "verdict": result["verdict"],
        "total_score": result["total_score"],
        "gate_threshold": PASS_THRESHOLD,
        "mode": result.get("mode", "unknown"),
        "blocking_flaws": result.get("blocking_flaws", []),
        "revision_instructions": result.get("revision_instructions", ""),
        "critique": {
            "q1": {"score": result.get("q1_score", 0), "text": result.get("q1_critique", "")},
            "q2": {"score": result.get("q2_score", 0), "text": result.get("q2_critique", "")},
            "q3": {"score": result.get("q3_score", 0), "text": result.get("q3_critique", "")},
            "q4": {"score": result.get("q4_score", 0), "text": result.get("q4_critique", "")},
            "q5": {"score": result.get("q5_score", 0), "text": result.get("q5_critique", "")},
        }
    }
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(output, f, indent=2)
    return output


def main():
    parser = argparse.ArgumentParser(description="ARIC Phase 7.5 Adversarial Verifier")
    parser.add_argument("--agent", required=True, help="Agent name (nel, ra, sam, etc.)")
    parser.add_argument("--plan-file", default=None, help="Path to ARIC plan JSON (default: aric-latest.json)")
    parser.add_argument("--heuristic", action="store_true", help="Use rule-based critique only (no API)")
    parser.add_argument("--threshold", type=int, default=PASS_THRESHOLD, help=f"Pass threshold 0-100 (default: {PASS_THRESHOLD})")
    args = parser.parse_args()

    aric_data = load_aric(args.agent, args.plan_file)
    if not aric_data:
        print(f"[aric-verifier] ERROR: No ARIC data for {args.agent}", file=sys.stderr)
        sys.exit(2)

    print(f"[aric-verifier] Verifying {args.agent} plan: {aric_data.get('weakness_worked', 'unknown weakness')}")

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if args.heuristic or not api_key:
        result = heuristic_verify(args.agent, aric_data)
    else:
        result = llm_verify(args.agent, aric_data, api_key)

    output = write_result(args.agent, result, aric_data)

    # Print result summary
    verdict = result["verdict"]
    score = result["total_score"]
    icon = "✓" if verdict == "APPROVED" else "✗"
    print(f"[aric-verifier] {icon} {args.agent}: {verdict} ({score}/{args.threshold*1} — gate: {args.threshold})")

    if result.get("blocking_flaws"):
        print(f"[aric-verifier] Blocking flaws:")
        for flaw in result["blocking_flaws"]:
            print(f"  - {flaw}")

    if verdict == "REQUIRES_REVISION":
        print(f"[aric-verifier] Revision required before execution can proceed.")
        print(f"[aric-verifier] Instructions: {result.get('revision_instructions', '')}")
        # Log as known issue
        try:
            entry = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "agent": args.agent,
                "category": "aric_plan_blocked",
                "score": score,
                "blocking_flaws": result.get("blocking_flaws", []),
                "weakness": aric_data.get("weakness_worked", "")
            }
            with open(SESSION_ERRORS, "a") as f:
                f.write(json.dumps(entry) + "\n")
        except Exception:
            pass
        sys.exit(1)  # Runner should NOT advance to execution

    print(f"[aric-verifier] Plan approved — execution may proceed.")
    print(f"[aric-verifier] Output: agents/{args.agent}/research/aric-verifier-latest.json")
    sys.exit(0)


if __name__ == "__main__":
    main()
