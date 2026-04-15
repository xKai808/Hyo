#!/usr/bin/env python3
"""
source_health.py — Ra newsletter source health monitoring

Tracks the health of all sources defined in sources.json. For each source,
records success/failure metrics, response times, and error details. Classifies
sources as healthy, degraded, or disabled based on success rate and consecutive
failures over a rolling 7-day window.

Usage:
    python3 source_health.py                          # full health check
    python3 source_health.py --dry-run               # report status without network calls
    python3 source_health.py --report                # human-readable summary
    python3 source_health.py --skip-source NAME      # check if source should be skipped

Output:
    agents/ra/pipeline/source-health.json             # health metrics per source

Design note:
    This script is designed to run in a sandbox that may block HTTP. It detects
    sandbox mode (all sources fail) and doesn't count those failures as real
    source health issues. Use --dry-run in sandbox; real health checks run on
    the Mini via launchd.

Exit codes:
    0 = success (health data updated or reported)
    1 = error (bad config, I/O error, etc.)
    2 = degraded (one or more sources unhealthy, but data collected)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

# Config
HERE = Path(__file__).resolve().parent
SOURCES_CONFIG = HERE / "sources.json"
HEALTH_FILE = HERE / "source-health.json"

# Time constants (all in UTC)
SEVEN_DAYS_SECONDS = 7 * 24 * 60 * 60
NOW_UTC = dt.datetime.now(dt.timezone.utc)


def now_iso() -> str:
    """ISO 8601 timestamp (UTC)."""
    return NOW_UTC.isoformat()


def http_get(
    url: str,
    *,
    timeout: int = 6,
    user_agent: str = "hyo-newsletter/0.2 (+https://hyo.world)",
) -> tuple[bool, float, str | None]:
    """
    Attempt a GET request to url. Return (success, response_time_ms, error_msg).

    Does NOT raise exceptions — all errors are caught and returned as (False, time, msg).
    """
    t0 = time.time()
    try:
        headers = {"User-Agent": user_agent}
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
        elapsed_ms = (time.time() - t0) * 1000
        # Check if we got actual content
        if len(data) > 0:
            return (True, elapsed_ms, None)
        else:
            return (False, elapsed_ms, "Empty response body")
    except urllib.error.HTTPError as e:
        elapsed_ms = (time.time() - t0) * 1000
        return (False, elapsed_ms, f"HTTP {e.code} — {e.reason}")
    except urllib.error.URLError as e:
        elapsed_ms = (time.time() - t0) * 1000
        return (False, elapsed_ms, f"URLError — {str(e.reason)[:100]}")
    except Exception as e:
        elapsed_ms = (time.time() - t0) * 1000
        return (False, elapsed_ms, f"{type(e).__name__} — {str(e)[:80]}")


def load_sources() -> dict:
    """Load sources.json. Return the 'sources' list."""
    if not SOURCES_CONFIG.exists():
        raise FileNotFoundError(f"sources.json not found at {SOURCES_CONFIG}")
    with SOURCES_CONFIG.open("r") as f:
        doc = json.load(f)
    return doc.get("sources", [])


def load_health() -> dict:
    """Load existing source-health.json. Return {} if it doesn't exist or is corrupt."""
    if not HEALTH_FILE.exists():
        return {}
    try:
        with HEALTH_FILE.open("r") as f:
            data = json.load(f)
        return data
    except json.JSONDecodeError:
        print(f"[warn] source-health.json corrupted, reinitializing", file=sys.stderr)
        return {}


def save_health(data: dict) -> None:
    """Atomically write health data to source-health.json."""
    HEALTH_FILE.parent.mkdir(parents=True, exist_ok=True)
    # Write to temp file first, then rename (atomic on Unix)
    temp = HEALTH_FILE.with_suffix(".json.tmp")
    with temp.open("w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    temp.replace(HEALTH_FILE)


def init_source_health(source_name: str, sources: list) -> dict:
    """Initialize a new health record for a source."""
    return {
        "last_success": None,
        "last_failure": None,
        "consecutive_failures": 0,
        "total_checks": 0,
        "successful_checks": 0,
        "success_rate": 0.0,
        "avg_response_time_ms": None,
        "status": "unknown",
        "last_error": None,
    }


def get_status(health: dict) -> str:
    """
    Classify source status based on health metrics.

    Rules:
    - disabled: success_rate < 0.3 OR consecutive_failures >= 7
    - degraded: success_rate 0.3-0.8 OR consecutive_failures >= 3
    - healthy: success_rate >= 0.8
    - unknown: no data yet
    """
    if health["total_checks"] == 0:
        return "unknown"

    sr = health["success_rate"]
    cf = health["consecutive_failures"]

    if sr < 0.3 or cf >= 7:
        return "disabled"
    elif (0.3 <= sr <= 0.8) or cf >= 3:
        return "degraded"
    elif sr >= 0.8:
        return "healthy"
    else:
        return "unknown"


def record_check(
    health_data: dict,
    source_name: str,
    success: bool,
    response_time_ms: float | None,
    error_msg: str | None,
) -> None:
    """
    Record a single health check result for a source.
    Updates or creates health record in place.
    """
    if source_name not in health_data:
        health_data[source_name] = init_source_health(source_name, [])

    rec = health_data[source_name]
    rec["total_checks"] += 1

    if success:
        rec["successful_checks"] += 1
        rec["last_success"] = now_iso()
        rec["consecutive_failures"] = 0
        if response_time_ms is not None:
            if rec["avg_response_time_ms"] is None:
                rec["avg_response_time_ms"] = response_time_ms
            else:
                # Simple exponential moving average
                rec["avg_response_time_ms"] = (
                    0.8 * rec["avg_response_time_ms"] + 0.2 * response_time_ms
                )
    else:
        rec["last_failure"] = now_iso()
        rec["consecutive_failures"] += 1
        rec["last_error"] = error_msg

    # Calculate success rate: successful_checks / total_checks
    if rec["total_checks"] > 0:
        rec["success_rate"] = round(rec["successful_checks"] / rec["total_checks"], 3)

    rec["status"] = get_status(rec)


def check_all_sources(sources: list) -> tuple[dict, int, int]:
    """
    Check health of all sources. Return (updated_health_data, failures, sandbox_detected).

    If all sources fail (every single one), we assume sandbox mode and don't count
    failures as real issues. Instead, return with sandbox_detected=1 and don't update
    health data.
    """
    health_data_raw = load_health()
    # Extract sources dict, handling both old and new formats
    health_data = health_data_raw.get("sources", {}) if isinstance(health_data_raw, dict) and "sources" in health_data_raw else health_data_raw
    failures = 0
    successes = 0
    results = {}

    for src in sources:
        name = src.get("name", "?")
        url = src.get("url") or ""

        if not url:
            print(f"[skip] {name}: no URL defined", file=sys.stderr)
            continue

        success, elapsed_ms, error = http_get(url)
        results[name] = (success, elapsed_ms, error)

        if success:
            successes += 1
        else:
            failures += 1

    # Sandbox detection: if every single source failed, we're in sandbox mode
    total = successes + failures
    if total > 0 and failures == total:
        print(f"[warn] all {total} sources failed — sandbox detected, not updating health", file=sys.stderr)
        return (health_data_raw, failures, 1)

    # Record results (only if not in sandbox)
    for name, (success, elapsed_ms, error) in results.items():
        record_check(health_data, name, success, elapsed_ms, error)

    # Return updated data with proper structure
    return ({"sources": health_data, "summary": {"total": len(health_data), "last_check": now_iso()}}, failures, 0)


def should_skip(source_name: str) -> bool:
    """
    Check if a source should be skipped during gather (disabled status).
    Return True if source is disabled, False otherwise.
    """
    health_data = load_health()
    sources_health = health_data.get("sources", health_data)  # Support both formats
    if source_name not in sources_health:
        return False

    status = sources_health[source_name].get("status", "unknown")
    return status == "disabled"


def get_health_report() -> str:
    """Generate a human-readable health report."""
    health_data = load_health()

    if not health_data:
        return "No health data yet. Run health checks first."

    # Extract sources from the loaded data structure
    sources_health = health_data.get("sources", health_data)  # Support both formats
    if not sources_health or not isinstance(sources_health, dict):
        return "No health data yet. Run health checks first."

    try:
        sources = load_sources()
    except Exception:
        sources = []
    source_names = {s.get("name"): s for s in sources}

    lines = []
    lines.append("# Source Health Report")
    lines.append(f"**As of:** {now_iso()}")
    lines.append("")

    # Classify by status
    statuses = {"healthy": [], "degraded": [], "disabled": [], "unknown": []}
    for name, health in sources_health.items():
        status = health.get("status", "unknown")
        statuses[status].append((name, health))

    # Count summary
    total = len(health_data)
    healthy = len(statuses["healthy"])
    degraded = len(statuses["degraded"])
    disabled = len(statuses["disabled"])
    unknown = len(statuses["unknown"])

    lines.append(f"## Summary")
    lines.append(f"- **Total sources:** {total}")
    lines.append(f"- **Healthy:** {healthy}")
    lines.append(f"- **Degraded:** {degraded}")
    lines.append(f"- **Disabled:** {disabled}")
    lines.append(f"- **Unknown:** {unknown}")
    lines.append("")

    # Healthy sources
    if statuses["healthy"]:
        lines.append(f"## Healthy ({healthy})")
        for name, health in statuses["healthy"]:
            sr = health.get("success_rate", 0.0)
            rt = health.get("avg_response_time_ms")
            rt_str = f"{rt:.0f}ms" if rt is not None else "?"
            lines.append(f"- **{name}**: {sr*100:.0f}% success, {rt_str} avg response")
        lines.append("")

    # Degraded sources
    if statuses["degraded"]:
        lines.append(f"## Degraded ({degraded})")
        for name, health in statuses["degraded"]:
            sr = health.get("success_rate", 0.0)
            cf = health.get("consecutive_failures", 0)
            error = health.get("last_error", "?")
            lines.append(f"- **{name}**: {sr*100:.0f}% success, {cf} consecutive failures")
            lines.append(f"  - Last error: {error}")
        lines.append("")

    # Disabled sources
    if statuses["disabled"]:
        lines.append(f"## Disabled ({disabled})")
        for name, health in statuses["disabled"]:
            sr = health.get("success_rate", 0.0)
            ls = health.get("last_success")
            error = health.get("last_error", "unknown")
            lines.append(f"- **{name}**: {sr*100:.0f}% success, last success {ls or 'never'}")
            lines.append(f"  - Reason: {error}")
        lines.append("")

    # Recommendation
    if disabled > 0:
        lines.append(f"## Recommendations")
        lines.append(f"- {disabled} source(s) are disabled and should be replaced or fixed.")
        lines.append(f"- Check `source-health.json` for details on errors and last successful fetch times.")
        lines.append("")

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Ra newsletter source health monitor"
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't make network requests; just report existing health data",
    )
    ap.add_argument(
        "--report",
        action="store_true",
        help="Print human-readable health report and exit",
    )
    ap.add_argument(
        "--skip-source",
        metavar="NAME",
        help="Check if SOURCE should be skipped (disabled); exit 0 if yes, 1 if no",
    )
    args = ap.parse_args()

    try:
        sources = load_sources()
    except FileNotFoundError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"[error] bad JSON in sources.json: {e}", file=sys.stderr)
        return 1

    # --report mode: print report and exit
    if args.report:
        print(get_health_report())
        return 0

    # --skip-source mode: check if a source is disabled
    if args.skip_source:
        if should_skip(args.skip_source):
            print(f"{args.skip_source}: disabled", file=sys.stderr)
            return 0
        else:
            print(f"{args.skip_source}: enabled", file=sys.stderr)
            return 1

    # --dry-run mode: report without network calls
    if args.dry_run:
        health_data = load_health()
        if not health_data:
            print("[info] no health data available yet", file=sys.stderr)
        else:
            count = len(health_data)
            statuses = {}
            for h in health_data.values():
                s = h.get("status", "unknown")
                statuses[s] = statuses.get(s, 0) + 1
            print(f"[info] {count} sources tracked: {json.dumps(statuses)}", file=sys.stderr)
        return 0

    # Normal mode: check all sources and update health data
    print(f"[info] checking health of {len(sources)} sources...", file=sys.stderr)
    health_data, failures, sandbox = check_all_sources(sources)

    if sandbox:
        print(f"[warn] sandbox detected (all sources unreachable), not updating health", file=sys.stderr)
        return 0

    try:
        save_health(health_data)
    except OSError as e:
        print(f"[error] failed to write health file: {e}", file=sys.stderr)
        return 1

    # Summary
    total = len(health_data)
    statuses = {}
    for h in health_data.values():
        s = h.get("status", "unknown")
        statuses[s] = statuses.get(s, 0) + 1

    print(f"[ok] health check complete: {json.dumps(statuses)}", file=sys.stderr)

    # Exit code 2 if any sources degraded/disabled
    if statuses.get("degraded", 0) > 0 or statuses.get("disabled", 0) > 0:
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
