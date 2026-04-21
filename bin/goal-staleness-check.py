#!/usr/bin/env python3
"""
bin/goal-staleness-check.py
Goal Staleness Check — per PROTOCOL_GOAL_STALENESS.md

Runs daily at 06:00 MT (before morning report generation).
Scans each agent's GROWTH.md for goals and evolution.jsonl for last progress.
Flags stale goals with severity P1/P2 and outputs findings for morning report.

Usage:
    python3 bin/goal-staleness-check.py [--agent <name>] [--dry-run] [--json]
"""

import json
import re
import sys
import datetime
import pathlib
import argparse

ROOT = pathlib.Path(__file__).parent.parent
AGENTS = ["nel", "ra", "sam", "dex"]  # NOT aether (external scope only per PROTOCOL_AETHER_ISOLATION.md)
NOW = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-6)))  # MT (MDT)

# Staleness thresholds per PROTOCOL_GOAL_STALENESS.md Section 1
STALENESS_THRESHOLDS = {
    "short": 3,    # days — stale if overdue by >3 days
    "medium": 14,  # days — stale if no progress in 14 days
    "long": 30,    # days — stale if no progress in 30 days
}

DEAD_LOOP_THRESHOLD = 3      # consecutive entries that look the same
JACCARD_THRESHOLD = 0.80     # similarity score for dead-loop detection


def parse_goals_from_growth(growth_file: pathlib.Path) -> list:
    """
    Parse goals from GROWTH.md using the standard table format per Section 7.

    Expected format:
    ## Goals (self-set)
    | Goal | Timeframe | Target Date | Status | Last Progress |
    |------|-----------|-------------|--------|---------------|
    | [Short description] | short/medium/long | YYYY-MM-DD | active/blocked/done/archived | YYYY-MM-DD |
    """
    goals = []
    if not growth_file.exists():
        return goals

    content = growth_file.read_text()
    in_goals_table = False
    header_seen = False

    for line in content.splitlines():
        if "## Goals (self-set)" in line or "## Goals" in line:
            in_goals_table = True
            header_seen = False
            continue

        if in_goals_table:
            # Skip separator lines
            if re.match(r"^\|[-| ]+\|$", line.strip()):
                header_seen = True
                continue
            # Stop at next section header
            if line.startswith("##") and not line.startswith("### "):
                break
            # Parse table row
            if line.startswith("|") and header_seen:
                cells = [c.strip() for c in line.strip("|").split("|")]
                if len(cells) >= 5:
                    title = cells[0].strip("[]").strip()
                    timeframe = cells[1].strip().lower()
                    target_date_str = cells[2].strip()
                    status = cells[3].strip().lower()
                    last_progress_str = cells[4].strip()

                    if not title or title in ("Goal", "---"):
                        continue
                    if timeframe not in ("short", "medium", "long"):
                        continue

                    # Parse dates
                    target_date = None
                    last_progress = None
                    try:
                        target_date = datetime.datetime.strptime(
                            target_date_str, "%Y-%m-%d"
                        ).replace(tzinfo=datetime.timezone(datetime.timedelta(hours=-6)))
                    except ValueError:
                        pass
                    try:
                        last_progress = datetime.datetime.strptime(
                            last_progress_str, "%Y-%m-%d"
                        ).replace(tzinfo=datetime.timezone(datetime.timedelta(hours=-6)))
                    except ValueError:
                        pass

                    goals.append({
                        "title": title,
                        "timeframe": timeframe,
                        "target_date": target_date,
                        "status": status,
                        "last_progress": last_progress,
                    })

    return goals


def get_evolution_entries(evolution_file: pathlib.Path, limit: int = 10) -> list:
    """Read last N entries from evolution.jsonl."""
    entries = []
    if not evolution_file.exists():
        return entries
    try:
        for line in evolution_file.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                entries.append(entry)
            except json.JSONDecodeError:
                pass
    except Exception:
        pass
    return entries[-limit:]  # Return last N


def get_last_goal_progress(evolution_entries: list, goal_title: str) -> datetime.datetime | None:
    """Find last evolution entry that references this goal."""
    goal_lower = goal_title.lower()
    for entry in reversed(evolution_entries):
        # Check all string values in entry for goal mention
        text = json.dumps(entry).lower()
        if goal_lower[:20].lower() in text:
            date_str = entry.get("date") or entry.get("timestamp", "")[:10]
            if date_str:
                try:
                    return datetime.datetime.strptime(date_str[:10], "%Y-%m-%d").replace(
                        tzinfo=datetime.timezone(datetime.timedelta(hours=-6))
                    )
                except ValueError:
                    pass
    return None


def tokenize(text: str) -> set:
    """Tokenize text for Jaccard similarity."""
    return set(re.findall(r"\w+", text.lower()))


def jaccard_similarity(set1: set, set2: set) -> float:
    """Calculate Jaccard similarity between two sets."""
    if not set1 and not set2:
        return 1.0
    intersection = len(set1 & set2)
    union = len(set1 | set2)
    return intersection / union if union > 0 else 0.0


def detect_dead_loop(evolution_entries: list, consecutive: int = DEAD_LOOP_THRESHOLD) -> bool:
    """
    Dead-loop detection per PROTOCOL_GOAL_STALENESS.md Section 4.
    Returns True if last N entries have Jaccard similarity > JACCARD_THRESHOLD.
    """
    if len(evolution_entries) < consecutive:
        return False
    recent = evolution_entries[-consecutive:]
    texts = [json.dumps(e) for e in recent]
    for i in range(len(texts) - 1):
        sim = jaccard_similarity(tokenize(texts[i]), tokenize(texts[i + 1]))
        if sim < JACCARD_THRESHOLD:
            return False
    return True


def check_agent(agent: str, verbose: bool = False) -> dict:
    """
    Run Goal Staleness Gate for one agent.
    Returns dict of findings.
    """
    result = {
        "agent": agent,
        "goals_found": 0,
        "stale_goals": [],
        "dead_loop": False,
        "no_goals_defined": False,
        "no_growth_file": False,
    }

    growth_file = ROOT / f"agents/{agent}/GROWTH.md"
    evolution_file = ROOT / f"agents/{agent}/evolution.jsonl"

    # GATE 1: Does the agent have active goals in GROWTH.md?
    if not growth_file.exists():
        result["no_growth_file"] = True
        return result

    goals = parse_goals_from_growth(growth_file)
    active_goals = [g for g in goals if g["status"] in ("active", "")]

    if not active_goals:
        result["no_goals_defined"] = True
        return result

    result["goals_found"] = len(active_goals)
    evolution_entries = get_evolution_entries(evolution_file)

    # GATE 6: Dead-loop detection
    if detect_dead_loop(evolution_entries):
        result["dead_loop"] = True

    for goal in active_goals:
        title = goal["title"]
        timeframe = goal["timeframe"]
        target_date = goal["target_date"]
        last_progress_from_table = goal["last_progress"]

        # Try to find progress in evolution.jsonl as well
        last_progress_from_evolution = get_last_goal_progress(evolution_entries, title)

        # Use the most recent of the two sources
        last_progress = None
        if last_progress_from_table and last_progress_from_evolution:
            last_progress = max(last_progress_from_table, last_progress_from_evolution)
        elif last_progress_from_table:
            last_progress = last_progress_from_table
        elif last_progress_from_evolution:
            last_progress = last_progress_from_evolution

        threshold = STALENESS_THRESHOLDS[timeframe]
        days_stale = None
        stale_type = None

        # GATE 3: Short-term overdue?
        if timeframe == "short" and target_date:
            days_overdue = (NOW - target_date).days
            if days_overdue > threshold:
                days_stale = days_overdue
                stale_type = "overdue"
                severity = "P1"
        # GATE 4/5: Medium/long — no progress for threshold days?
        if last_progress:
            days_since_progress = (NOW - last_progress).days
            if days_since_progress > threshold:
                days_stale = days_since_progress
                stale_type = "no_progress"
                severity = "P1" if timeframe == "short" else "P2"
        elif last_progress is None:
            # No progress recorded at all
            days_stale = 9999
            stale_type = "no_progress_ever"
            severity = "P1" if timeframe == "short" else "P2"

        if stale_type:
            result["stale_goals"].append({
                "title": title,
                "timeframe": timeframe,
                "severity": severity,
                "days_stale": days_stale,
                "stale_type": stale_type,
                "last_progress": last_progress.strftime("%Y-%m-%d") if last_progress else "never",
                "target_date": target_date.strftime("%Y-%m-%d") if target_date else "none",
            })

    return result


def main():
    parser = argparse.ArgumentParser(description="Goal Staleness Check — PROTOCOL_GOAL_STALENESS.md")
    parser.add_argument("--agent", help="Check specific agent only (default: all)")
    parser.add_argument("--json", action="store_true", help="Output JSON (for morning report integration)")
    parser.add_argument("--dry-run", action="store_true", help="Don't open tickets (default: opens tickets)")
    args = parser.parse_args()

    agents_to_check = [args.agent] if args.agent else AGENTS
    all_results = []
    any_stale = False
    any_dead_loop = False

    for agent in agents_to_check:
        result = check_agent(agent)
        all_results.append(result)

        if result["stale_goals"] or result["dead_loop"] or result["no_goals_defined"]:
            any_stale = True
        if result["dead_loop"]:
            any_dead_loop = True

    if args.json:
        print(json.dumps({
            "date": NOW.strftime("%Y-%m-%d"),
            "any_stale": any_stale,
            "any_dead_loop": any_dead_loop,
            "agents": all_results
        }, indent=2))
        return

    # Human-readable output for morning report
    print(f"\n=== GOAL STALENESS CHECK — {NOW.strftime('%Y-%m-%d')} ===")
    print(f"Agents checked: {', '.join(agents_to_check)}\n")

    found_issues = False
    for result in all_results:
        agent = result["agent"]

        if result["no_growth_file"]:
            print(f"[P2] {agent.upper()}: GROWTH.md not found — cannot check goals")
            found_issues = True
            continue

        if result["no_goals_defined"]:
            print(f"[P2] {agent.upper()}: No active goals defined in GROWTH.md")
            print(f"     → Action: Run ARIC to help {agent} define self-set goals")
            found_issues = True
            continue

        if result["dead_loop"]:
            print(f"[P1] {agent.upper()}: DEAD-LOOP detected (evolution.jsonl entries too similar)")
            print(f"     → Action: Run Kai Guidance Protocol — open-ended questions to break the loop")
            found_issues = True

        for sg in result["stale_goals"]:
            severity = sg["severity"]
            title = sg["title"]
            timeframe = sg["timeframe"]
            days = sg["days_stale"]
            stale_type = sg["stale_type"]
            last = sg["last_progress"]

            if stale_type == "overdue":
                msg = f"{days}d overdue (target: {sg['target_date']})"
            elif stale_type == "no_progress_ever":
                msg = "no progress ever recorded"
            else:
                msg = f"{days}d since last progress (last: {last})"

            print(f"[{severity}] {agent.upper()}: STALE {timeframe.upper()}-TERM GOAL — '{title}'")
            print(f"     Status: {msg}")
            print(f"     → Action: Ask '{agent}' — what is the single most concrete next step?")
            found_issues = True

        if not result["stale_goals"] and not result["dead_loop"] and not result["no_goals_defined"]:
            goals = result["goals_found"]
            print(f"[OK] {agent.upper()}: {goals} goal(s) — no staleness detected")

    if not found_issues:
        print("\n✓ All agent goals are on track. No staleness detected.\n")
    else:
        print(f"\n{'='*50}")
        print("NEXT ACTION: Surface stale goals in morning report.")
        print("P1 items: run Kai Guidance Protocol before any other work.")
        print("Gate: 'Are any agents showing stale goals? YES → run push algorithm first.'")
        print(f"{'='*50}\n")

    # Exit code: 0 = clean, 1 = issues found (for integration with morning report)
    sys.exit(1 if found_issues else 0)


if __name__ == "__main__":
    main()
