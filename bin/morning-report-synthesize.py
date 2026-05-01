#!/usr/bin/env python3
"""
morning-report-synthesize.py — Synthesis pass for morning report intelligence items.

Takes raw intelligence_items (from ARIC JSON) and rewrites them into
Aurora-style prose that a CEO can read: category tag, bold topic, one takeaway
sentence, one Watch signal.

Called by generate-morning-report.sh after collecting intelligence_items.

Input  (stdin): JSON array of raw intelligence items
Output (stdout): JSON array of synthesized items

Usage:
    echo '[{"topic": "...", "finding": "...", ...}]' | python3 bin/morning-report-synthesize.py

Exit 0 on success (stdout = synthesized JSON).
Exit 1 if synthesis failed — caller falls back to raw items.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SYNTHESIS_PROMPT = """You are writing the Intelligence section of a morning briefing for the CEO of hyo.world — a crypto/AI startup.

For each raw research item below, produce a polished 4-part entry that a non-technical executive can read in 10 seconds:

1. category — one of: AI-STRATEGY, AI-MODELS, AI-FINANCE, ONCHAIN, DEVELOPER-TOOLS, MARKET, RISK, OPPORTUNITY
2. topic — 2-4 word headline (specific thing studied, no jargon)
3. takeaway — ONE sentence in plain English. State what was discovered and why it matters to hyo.world. No technical terms without plain explanations. Write like The Economist, not a GitHub README.
4. watch — ONE forward-looking sentence. What signal should we track next? What could change?

Rules:
- Never use: "improvement_built", "weakness_worked", "ARIC", "Phase", "shipped commit", agent system names
- Never mention internal systems or processes — only external findings
- If the raw item is about internal agent work rather than external research, still extract the underlying external topic and write about that
- Output ONLY valid JSON — no commentary, no markdown fences

Output format (JSON array, one object per input item):
[
  {
    "category": "AI-STRATEGY",
    "topic": "Example Topic",
    "takeaway": "One plain-English sentence about what was found and why it matters.",
    "watch": "One forward-looking sentence about what to track next.",
    "agent": "<agent name from input>"
  }
]

Raw items to synthesize:
"""

def _find_claude_bin() -> str | None:
    env_path = os.environ.get("HYO_CLAUDE_BIN", "").strip()
    if env_path and Path(env_path).is_file() and os.access(env_path, os.X_OK):
        return env_path
    on_path = shutil.which("claude")
    if on_path:
        return on_path
    home = os.path.expanduser("~")
    candidates = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        f"{home}/.claude/local/claude",
        f"{home}/.local/bin/claude",
        f"{home}/.npm-global/bin/claude",
        f"{home}/.volta/bin/claude",
    ]
    for c in candidates:
        if Path(c).is_file() and os.access(c, os.X_OK):
            return c
    return None


def synthesize(items: list[dict]) -> list[dict]:
    """Call Claude CLI to synthesize raw items into Aurora-style prose."""
    if not items:
        return []

    bin_path = _find_claude_bin()
    if not bin_path:
        raise RuntimeError("claude binary not found")

    raw_json = json.dumps(items, indent=2)
    combined = SYNTHESIS_PROMPT + raw_json

    proc = subprocess.run(
        [bin_path, "-p", "--output-format", "text"],
        input=combined,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )

    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: {proc.stderr.strip()[:300]}")

    output = (proc.stdout or "").strip()
    if not output:
        raise RuntimeError("claude returned empty output")

    # Strip markdown fences if present
    if output.startswith("```"):
        lines = output.split("\n")
        output = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])

    synthesized = json.loads(output)
    if not isinstance(synthesized, list):
        raise RuntimeError(f"expected JSON array, got {type(synthesized)}")

    return synthesized


def main():
    raw_json = sys.stdin.read().strip()
    if not raw_json:
        print("[]")
        return

    try:
        items = json.loads(raw_json)
    except json.JSONDecodeError as e:
        print(f"Input JSON parse error: {e}", file=sys.stderr)
        sys.exit(1)

    if not items:
        print("[]")
        return

    try:
        result = synthesize(items)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(f"Synthesis failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
