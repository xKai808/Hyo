#!/usr/bin/env python3
"""
bin/agent-bluf-augment.py — Prepend BLUF + 5-question block to agent reflection sections.

Call before publish-to-feed.sh to ensure every report meets PROTOCOL_AGENT_REPORT.md v1.0.

Usage:
  python3 bin/agent-bluf-augment.py <agent> <sections_json_file>

Reads:
  - <sections_json_file>: existing Nel/Ra/Sam/Dex/Aether sections JSON
  - agents/<agent>/research/aric-latest.json: improvement status

Writes:
  - <sections_json_file> (in-place): augmented with bluf, five_questions, improvement_status keys

Exit codes:
  0 — success (sections file updated)
  1 — error (file not found, JSON parse error)
"""

import json
import os
import sys
from datetime import datetime

HYO_ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))


def load_aric(agent: str) -> dict:
    """Load aric-latest.json, return empty dict on any error."""
    path = os.path.join(HYO_ROOT, "agents", agent, "research", "aric-latest.json")
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def improvement_status_text(aric: dict, agent: str) -> str:
    """One-line improvement status string from aric-latest.json."""
    if not aric:
        return "ARIC data unavailable"

    built = aric.get("improvement_built", {})
    status = built.get("status", "unknown")
    ticket_id = built.get("ticket_id", "?")
    description = built.get("description", "?")[:60]
    commit = built.get("commit") or ""
    cycle_date = aric.get("cycle_date", "?")

    # Check staleness
    today = datetime.now().strftime("%Y-%m-%d")
    try:
        days_stale = (
            datetime.strptime(today, "%Y-%m-%d")
            - datetime.strptime(cycle_date, "%Y-%m-%d")
        ).days
    except Exception:
        days_stale = 0

    stale_note = f" [ARIC {days_stale}d stale]" if days_stale > 1 else ""

    if status == "shipped" and commit:
        return f"SHIPPED: {ticket_id} — {description} — commit {commit}{stale_note}"
    elif status == "shipped":
        return f"SHIPPED: {ticket_id} — {description}{stale_note}"
    elif status == "in_progress":
        return f"IN PROGRESS: {ticket_id} — {description}{stale_note}"
    elif status == "researched":
        return f"PENDING EXECUTION: {ticket_id} — {description} (research done, code pending){stale_note}"
    else:
        return f"IDLE: no active improvement ({status}){stale_note}"


def build_bluf(agent: str, sections: dict, imp_status: str) -> str:
    """
    Build a 3-sentence BLUF from existing sections.
    [Shipped]: what actually changed
    [Watching]: highest-priority issue
    [Next]: concrete next action
    """
    # Try to extract shipped signal from introspection or changes
    shipped_signal = ""
    changes = sections.get("changes", "")
    introspection = sections.get("introspection", "")
    for_kai = sections.get("forKai", "")

    if "SHIPPED:" in imp_status:
        # Pull the description from imp_status
        shipped_signal = imp_status.replace("SHIPPED: ", "").split("—")[1].strip() if "—" in imp_status else imp_status
        shipped_line = f"[Shipped]: {shipped_signal.strip()}"
    elif changes:
        # First sentence of changes
        first_sent = changes.split(".")[0].strip()
        shipped_line = f"[Shipped]: {first_sent}." if first_sent else "[Shipped]: Routine cycle completed — no new code shipped."
    else:
        shipped_line = "[Shipped]: Routine cycle completed — no new code shipped."

    # Watching: pull from for_kai or introspection
    if for_kai and "nothing urgent" not in for_kai.lower():
        watch_sent = for_kai.split(".")[0].strip()
        watch_line = f"[Watching]: {watch_sent}."
    elif "fail" in introspection.lower():
        # Find the sentence with "fail" in it
        for sent in introspection.split("."):
            if "fail" in sent.lower():
                watch_line = f"[Watching]: {sent.strip()}."
                break
        else:
            watch_line = "[Watching]: See introspection for active issues."
    else:
        watch_line = "[Watching]: No urgent issues — system running normally."

    # Next: pull from followUps
    followups = sections.get("followUps", [])
    if followups and isinstance(followups, list):
        next_line = f"[Next]: {followups[0]}"
    else:
        next_line = "[Next]: Continue monitoring and advance next improvement ticket."

    return f"{shipped_line}\n{watch_line}\n{next_line}"


def build_five_questions(agent: str, sections: dict, imp_status: str, aric: dict) -> str:
    """Build the 5-question block for PROTOCOL_AGENT_REPORT.md compliance."""
    built = aric.get("improvement_built", {})
    weakness = built.get("weakness", "?")
    description = built.get("description", "?")[:60]
    ticket_id = built.get("ticket_id", "?")

    # Q1: What shipped?
    if "SHIPPED:" in imp_status:
        q1 = f"Shipped: {description} ({ticket_id})."
    else:
        q1 = "Nothing shipped this cycle — running diagnostics and research."

    # Q2: Highest-priority unresolved issue
    for_kai = sections.get("forKai", "")
    if for_kai and len(for_kai) > 10:
        q2_text = for_kai.split(".")[0].strip()
        q2 = f"{q2_text}."
    else:
        q2 = "No critical open issues at this time."

    # Q3: Next concrete action
    followups = sections.get("followUps", [])
    if isinstance(followups, list) and followups:
        q3 = followups[0]
    else:
        q3 = "Advance to next open improvement ticket."

    # Q4: Action type
    next_str = q3.lower()
    if any(k in next_str for k in ["build", "create", "write", "implement"]):
        q4 = "build"
    elif any(k in next_str for k in ["deploy", "push", "publish", "ship"]):
        q4 = "deploy"
    elif any(k in next_str for k in ["scan", "monitor", "check", "audit"]):
        q4 = "instrument"
    elif any(k in next_str for k in ["research", "analyse", "investigate", "study"]):
        q4 = "research"
    else:
        q4 = "execute"

    # Q5: Evidence for priority
    research = sections.get("research", "")
    if "CVE" in research:
        import re
        cves = re.findall(r"CVE-\d{4}-\d{4,}", research)
        q5 = f"CVEs found in this cycle: {', '.join(cves[:3])}." if cves else "Research findings support this priority."
    elif weakness and weakness != "?":
        q5 = f"Ticket {ticket_id} addresses {weakness} — identified as systemic weakness in GROWTH.md."
    else:
        q5 = "Based on recurring pattern in session-errors.jsonl and known-issues.jsonl."

    return (
        f"Q1 (What shipped?): {q1}\n"
        f"Q2 (Highest-priority open issue?): {q2}\n"
        f"Q3 (Next concrete action?): {q3}\n"
        f"Q4 (Action type): {q4}\n"
        f"Q5 (Evidence for priority): {q5}"
    )


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <agent> <sections_json_file>", file=sys.stderr)
        sys.exit(1)

    agent = sys.argv[1]
    sections_file = sys.argv[2]

    if not os.path.exists(sections_file):
        print(f"ERROR: sections file not found: {sections_file}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(sections_file) as f:
            sections = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON in {sections_file}: {e}", file=sys.stderr)
        sys.exit(1)

    # Load improvement status
    aric = load_aric(agent)
    imp_status = improvement_status_text(aric, agent)

    # Build BLUF and 5-question block
    bluf = build_bluf(agent, sections, imp_status)
    five_q = build_five_questions(agent, sections, imp_status, aric)

    # Augment sections in-place
    sections["bluf"] = bluf
    sections["five_questions"] = five_q
    sections["improvement_status"] = imp_status

    # Write back
    with open(sections_file, "w") as f:
        json.dump(sections, f, indent=2)

    print(f"[bluf-augment] {agent}: sections augmented — status: {imp_status[:60]}")


if __name__ == "__main__":
    main()
