#!/usr/bin/env python3
"""
synthesize.py — Hyo Daily Newsletter, stage 2 (synthesize)

Reads today's JSONL produced by gather.py, sorts and groups the
records, builds a tight context bundle, and calls a single LLM
synthesis pass using the prompt in prompts/synthesize.md. Writes the
final markdown newsletter to:

    ~/Documents/Projects/Hyo/newsletters/YYYY-MM-DD.md

ZERO external dependencies. Python 3.9+ stdlib only. No openai, no
anthropic SDK, no requests. Plain urllib against the provider's HTTP
API. Supports four synthesis backends, picked in this order:

    1. Claude Code CLI           — if `claude` binary is on PATH (uses
                                    Hyo's Max subscription, no API key)
    2. xAI Grok 4 Fast           — if GROK_API_KEY is set
    3. OpenAI GPT-4o             — if OPENAI_API_KEY is set or
                                    agents/nel/security/openai.key exists
    4. Anthropic Claude API       — if ANTHROPIC_API_KEY is set
    5. "bundle mode" (no key)    — writes a prompt+context bundle to
                                    newsletters/YYYY-MM-DD.input.md
                                    that a Cowork scheduled task can
                                    pick up and complete manually.

Usage:
    python3 synthesize.py                        # today, auto backend
    python3 synthesize.py --date 2026-04-09      # backfill
    python3 synthesize.py --backend claude_code  # force backend
    python3 synthesize.py --model grok-4-fast    # override model
    python3 synthesize.py --dry-run              # no API call, no write
    python3 synthesize.py --bundle               # force bundle mode

Env vars:
    HYO_CLAUDE_BIN     absolute path to `claude` binary (optional)
    GROK_API_KEY       xAI Grok API key (optional)
    ANTHROPIC_API_KEY  Anthropic API key (optional)
    HYO_NEWSLETTERS_DIR  override the output directory
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------

HERE = Path(__file__).resolve().parent
PROMPT_PATH = HERE / "prompts" / "synthesize.md"
SOURCES_PATH = HERE / "sources.json"

DEFAULT_NEWSLETTERS_DIR = Path.home() / "Documents" / "Projects" / "Hyo" / "newsletters"
DEFAULT_INTELLIGENCE_DIR = Path.home() / "Documents" / "Projects" / "Kai" / "intelligence"

# limits
MAX_CONTEXT_CHARS = 120_000       # ~30k tokens, comfortable for any frontier model
MAX_RECORDS_PER_TOPIC = 25        # after ranking, keep top N per topic bucket
HTTP_TIMEOUT = 180


# ---------------------------------------------------------------------------
# data loading + ranking
# ---------------------------------------------------------------------------

def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        raise FileNotFoundError(f"no JSONL at {path} — run gather.py first")
    records: list[dict] = []
    with path.open("r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def dedupe_records(records: list[dict]) -> list[dict]:
    """Collapse duplicates by URL. Keep the highest-scoring copy."""
    best: dict[str, dict] = {}
    for r in records:
        url = r.get("url", "").strip()
        if not url:
            continue
        prev = best.get(url)
        if prev is None or float(r.get("score", 0)) > float(prev.get("score", 0)):
            best[url] = r
    return list(best.values())


def rank_and_group(records: list[dict]) -> dict[str, list[dict]]:
    """Sort by score desc, then bucket by topic, then cap per bucket."""
    records = sorted(records, key=lambda r: float(r.get("score", 0)), reverse=True)
    grouped: dict[str, list[dict]] = {}
    for r in records:
        topic = r.get("topic", "other")
        grouped.setdefault(topic, []).append(r)
    return {t: items[:MAX_RECORDS_PER_TOPIC] for t, items in grouped.items()}


# ---------------------------------------------------------------------------
# context bundle
# ---------------------------------------------------------------------------

def format_record(r: dict) -> str:
    title = (r.get("title") or "").strip()
    summary = (r.get("summary") or "").strip()
    url = r.get("url", "")
    source = r.get("source", "")
    score = float(r.get("score", 0))
    meta = r.get("meta") or {}
    meta_bits = []
    for k in ("points", "comments", "ups", "stars_today", "change_24h_pct",
              "change_pct", "symbol", "series_id", "value"):
        if k in meta and meta[k] not in (None, ""):
            meta_bits.append(f"{k}={meta[k]}")
    meta_str = f" [{' '.join(meta_bits)}]" if meta_bits else ""
    line = f"- ({source} · score {score:.1f}{meta_str}) {title}"
    if summary:
        line += f"\n    {summary}"
    line += f"\n    {url}"
    return line


def build_context(grouped: dict[str, list[dict]], date_str: str) -> str:
    parts: list[str] = []
    parts.append(f"# Raw intelligence for {date_str}\n")
    parts.append(f"Total sources: {sum(len(v) for v in grouped.values())} records "
                 f"across {len(grouped)} topic buckets.\n")

    # Fixed topic order so the model sees macro + ai first (the most
    # important signal for a CEO's morning).
    order = ["ai", "macro", "tech", "crypto", "apps", "other"]
    seen: set[str] = set()

    def emit_topic(topic: str, items: list[dict]) -> None:
        if not items:
            return
        parts.append(f"\n## Topic: {topic}  ({len(items)} records)\n")
        for r in items:
            parts.append(format_record(r))

    for topic in order:
        if topic in grouped:
            emit_topic(topic, grouped[topic])
            seen.add(topic)
    for topic, items in grouped.items():
        if topic not in seen:
            emit_topic(topic, items)

    out = "\n".join(parts)
    if len(out) > MAX_CONTEXT_CHARS:
        out = out[:MAX_CONTEXT_CHARS] + "\n\n[...truncated at context limit...]\n"
    return out


# ---------------------------------------------------------------------------
# LLM backends
# ---------------------------------------------------------------------------

def _post_json(url: str, headers: dict, payload: dict, timeout: int) -> dict:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return json.loads(raw.decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:600]
        except Exception:
            pass
        raise RuntimeError(f"HTTP {exc.code} {exc.reason}: {detail}") from exc


def _find_claude_bin() -> str | None:
    """Probe common locations for the `claude` CLI binary.

    Scheduled tasks on macOS often run with a minimal PATH that excludes
    /usr/local/bin, /opt/homebrew/bin, and npm global install dirs. So we
    search explicitly before giving up.
    """
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


def call_claude_code(prompt: str, context: str, *, model: str, timeout: int) -> str:
    """Shell out to the Claude Code CLI. Uses Hyo's Max subscription.

    `claude -p "<text>"` runs a non-interactive prompt and prints the
    response to stdout. We feed the combined system prompt + context as
    a single user message. No streaming, no tool use, no file writes —
    Claude Code is used purely as a text transformation here.
    """
    bin_path = _find_claude_bin()
    if not bin_path:
        raise RuntimeError(
            "claude binary not found. Install via `npm i -g @anthropic-ai/claude-code` "
            "or set HYO_CLAUDE_BIN to the absolute path."
        )
    combined = (
        f"{prompt.strip()}\n\n"
        f"---\n\n"
        f"Use the context below to produce the finished newsletter markdown. "
        f"Output ONLY the newsletter markdown body — no commentary, no code "
        f"fences, no preamble. Start with the first header of the newsletter.\n\n"
        f"---\n\n"
        f"{context}"
    )
    # Use stdin rather than a command-line arg to avoid argv length limits
    # and shell quoting hazards on the enormous context payload.
    try:
        proc = subprocess.run(
            [bin_path, "-p", "--output-format", "text"],
            input=combined,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"claude-code timeout after {timeout}s") from exc
    if proc.returncode != 0:
        raise RuntimeError(
            f"claude-code exited {proc.returncode}: {proc.stderr.strip()[:500]}"
        )
    out = (proc.stdout or "").strip()
    if not out:
        raise RuntimeError("claude-code returned empty output")
    return out


def call_xai(prompt: str, context: str, *, model: str, timeout: int) -> str:
    key = os.environ.get("GROK_API_KEY", "").strip()
    if not key:
        raise RuntimeError("GROK_API_KEY not set")
    data = _post_json(
        "https://api.x.ai/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        payload={
            "model": model,
            "messages": [
                {"role": "system", "content": prompt},
                {"role": "user", "content": context},
            ],
            "temperature": 0.3,
            "max_tokens": 4000,
        },
        timeout=timeout,
    )
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as exc:
        raise RuntimeError(f"xai: unexpected response shape: {data}") from exc


def call_openai(prompt: str, context: str, *, model: str, timeout: int) -> str:
    # Try env var first, then key file
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        key_file = HERE.parent.parent / "nel" / "security" / "openai.key"
        if key_file.is_file():
            key = key_file.read_text().strip()
    if not key:
        raise RuntimeError("OPENAI_API_KEY not set and openai.key not found")
    data = _post_json(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        payload={
            "model": model,
            "messages": [
                {"role": "system", "content": prompt},
                {"role": "user", "content": context},
            ],
            "temperature": 0.3,
            "max_tokens": 4000,
        },
        timeout=timeout,
    )
    try:
        return data["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as exc:
        raise RuntimeError(f"openai: unexpected response shape: {data}") from exc


def call_anthropic(prompt: str, context: str, *, model: str, timeout: int) -> str:
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not key:
        raise RuntimeError("ANTHROPIC_API_KEY not set")
    data = _post_json(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        payload={
            "model": model,
            "max_tokens": 4000,
            "system": prompt,
            "messages": [
                {"role": "user", "content": context},
            ],
        },
        timeout=timeout,
    )
    try:
        return data["content"][0]["text"]
    except (KeyError, IndexError) as exc:
        raise RuntimeError(f"anthropic: unexpected response shape: {data}") from exc


BACKENDS = {
    "claude_code": (call_claude_code, "claude-code-cli"),
    "xai": (call_xai, "grok-4-fast"),
    "openai": (call_openai, "gpt-4o"),
    "anthropic": (call_anthropic, "claude-sonnet-4-5"),
}


def pick_backend(preferred: str | None) -> tuple[str, str]:
    """Return (backend_name, default_model).

    Auto priority:
      1. claude_code (if CLI binary is findable) — $0 incremental cost
      2. xAI (if GROK_API_KEY)
      3. Anthropic API (if ANTHROPIC_API_KEY)
      4. bundle mode
    """
    if preferred and preferred in BACKENDS:
        return preferred, BACKENDS[preferred][1]
    if _find_claude_bin():
        return "claude_code", BACKENDS["claude_code"][1]
    if os.environ.get("GROK_API_KEY", "").strip():
        return "xai", BACKENDS["xai"][1]
    # OpenAI: check env var or key file
    openai_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not openai_key:
        key_file = HERE.parent.parent / "nel" / "security" / "openai.key"
        if key_file.is_file():
            openai_key = key_file.read_text().strip()
    if openai_key:
        return "openai", BACKENDS["openai"][1]
    if os.environ.get("ANTHROPIC_API_KEY", "").strip():
        return "anthropic", BACKENDS["anthropic"][1]
    return "bundle", ""


# ---------------------------------------------------------------------------
# output writing
# ---------------------------------------------------------------------------

def write_markdown(text: str, path: Path, date_str: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    header = (
        f"---\n"
        f"date: {date_str}\n"
        f"kind: hyo-daily\n"
        f"generated: {dt.datetime.now(dt.timezone.utc).isoformat()}\n"
        f"---\n\n"
    )
    with path.open("w") as f:
        f.write(header)
        f.write(text.rstrip() + "\n")


def write_bundle(prompt: str, context: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        f.write("# Hyo Newsletter — Synthesis Input Bundle\n\n")
        f.write("This file is produced when synthesize.py runs without an API\n")
        f.write("key. Open it in a Cowork session (or any Claude chat) and ask:\n")
        f.write("  'Synthesize today\\'s Hyo newsletter from this file.'\n\n")
        f.write("---\n\n## SYSTEM PROMPT\n\n")
        f.write(prompt.strip() + "\n\n")
        f.write("---\n\n## CONTEXT\n\n")
        f.write(context.strip() + "\n")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def load_intelligence_dir_from_sources() -> Path:
    if not SOURCES_PATH.exists():
        return DEFAULT_INTELLIGENCE_DIR
    try:
        with SOURCES_PATH.open("r") as f:
            doc = json.load(f)
        d = (doc.get("config") or {}).get("output_dir")
        if d:
            return Path(os.path.expanduser(d))
    except Exception:
        pass
    return DEFAULT_INTELLIGENCE_DIR


def main() -> int:
    ap = argparse.ArgumentParser(description="Hyo newsletter synthesis stage")
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--backend",
                    choices=["claude_code", "xai", "anthropic", "bundle", "auto"],
                    default="auto")
    ap.add_argument("--model", help="Override default model")
    ap.add_argument("--bundle", action="store_true",
                    help="Force bundle mode (no API call)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print stats, do not call API or write final file")
    ap.add_argument("--out", help="Override output directory")
    args = ap.parse_args()

    date_str = args.date or dt.date.today().isoformat()

    intel_dir = load_intelligence_dir_from_sources()
    jsonl_path = intel_dir / f"{date_str}.jsonl"
    try:
        records = load_jsonl(jsonl_path)
    except FileNotFoundError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1

    records = dedupe_records(records)
    grouped = rank_and_group(records)
    context = build_context(grouped, date_str)

    if not PROMPT_PATH.exists():
        print(f"[error] prompt not found: {PROMPT_PATH}", file=sys.stderr)
        return 1
    prompt = PROMPT_PATH.read_text()

    out_dir = Path(args.out or os.environ.get("HYO_NEWSLETTERS_DIR")
                   or str(DEFAULT_NEWSLETTERS_DIR)).expanduser()
    md_path = out_dir / f"{date_str}.md"
    bundle_path = out_dir / f"{date_str}.input.md"

    print(f"[info] loaded {len(records)} unique records across "
          f"{len(grouped)} topics", file=sys.stderr)
    print(f"[info] context size: {len(context):,} chars", file=sys.stderr)

    # decide backend
    forced_bundle = args.bundle or args.backend == "bundle"
    if forced_bundle:
        backend, model = "bundle", ""
    else:
        backend, default_model = pick_backend(
            None if args.backend == "auto" else args.backend
        )
        model = args.model or default_model

    if args.dry_run:
        print(f"[dry-run] would synthesize via backend={backend} model={model}",
              file=sys.stderr)
        print(f"[dry-run] would write {md_path}", file=sys.stderr)
        return 0

    if backend == "bundle":
        write_bundle(prompt, context, bundle_path)
        print(f"[ok] wrote bundle (no API key found) → {bundle_path}")
        print("[hint] set GROK_API_KEY or ANTHROPIC_API_KEY to auto-synthesize",
              file=sys.stderr)
        return 0

    # Build ordered fallback chain: chosen backend → remaining backends
    backend_order = [backend]
    all_backends = ["claude_code", "xai", "openai", "anthropic"]
    for b in all_backends:
        if b != backend and b in BACKENDS:
            backend_order.append(b)

    t0 = time.time()
    for attempt_backend in backend_order:
        attempt_fn = BACKENDS[attempt_backend][0]
        attempt_model = args.model if (args.model and attempt_backend == backend) else BACKENDS[attempt_backend][1]
        try:
            result = attempt_fn(prompt, context, model=attempt_model, timeout=HTTP_TIMEOUT)
            write_markdown(result, md_path, date_str)
            elapsed = time.time() - t0
            print(f"[ok] synthesized in {elapsed:.1f}s via {attempt_backend}/{attempt_model}")
            print(f"[ok] wrote {md_path}")
            return 0
        except Exception as exc:  # noqa: BLE001
            print(f"[error] {attempt_backend} call failed: {exc}", file=sys.stderr)
            continue

    # All backends failed — write bundle as last resort
    write_bundle(prompt, context, bundle_path)
    print(f"[ok] wrote fallback bundle → {bundle_path}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
