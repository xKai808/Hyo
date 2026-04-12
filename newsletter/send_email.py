#!/usr/bin/env python3
"""
send_email.py — Aurora Public email dispatcher.

Reads the manifest.json produced by aurora_public.py for a given date,
loads each subscriber's markdown brief, renders a clean HTML + plain
text pair, and dispatches them to subscriber inboxes. On success, stamps
`lastSent` and `lastBriefId` on the subscriber record.

Two backends:

  * resend — POST to https://api.resend.com/emails (requires RESEND_API_KEY)
  * smtp   — stdlib smtplib, STARTTLS (requires SMTP_HOST, SMTP_PORT,
             SMTP_USER, SMTP_PASS, SMTP_FROM)

Backend selection:

  1. --backend flag (explicit)
  2. $AURORA_EMAIL_BACKEND env var
  3. RESEND_API_KEY present → resend
  4. SMTP_HOST present → smtp
  5. otherwise dry-run (prints the plan, exits 0)

Stdlib only. No pip, no venv.

Usage:
    python3 send_email.py                        # today, all
    python3 send_email.py --date 2026-04-12
    python3 send_email.py --sub sub_abc123       # only one subscriber
    python3 send_email.py --dry-run              # never actually send
    python3 send_email.py --backend smtp

Env vars:
    AURORA_EMAIL_BACKEND     resend | smtp
    AURORA_FROM_EMAIL        "Aurora <aurora@hyo.world>" (default)
    RESEND_API_KEY           for resend backend
    SMTP_HOST, SMTP_PORT     for smtp backend
    SMTP_USER, SMTP_PASS
    SMTP_FROM
    HYO_SUBSCRIBERS_FILE     override subscribers.jsonl path
    HYO_PUBLIC_OUT_DIR       override briefs output dir
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import smtplib
import ssl
import sys
import urllib.request
import urllib.error
from email.message import EmailMessage
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

# Reuse render.py's markdown → html so Aurora emails look like the site.
try:
    import render  # type: ignore
    HAVE_RENDER = True
except Exception:
    HAVE_RENDER = False

HYO_ROOT = Path(os.environ.get("HYO_ROOT", HERE.parent)).resolve()
SUBSCRIBERS = Path(
    os.environ.get("HYO_SUBSCRIBERS_FILE", HERE / "subscribers.jsonl")
)
PUBLIC_OUT = Path(
    os.environ.get("HYO_PUBLIC_OUT_DIR", HERE / "out" / "public")
)

DEFAULT_FROM = os.environ.get("AURORA_FROM_EMAIL", "Aurora <aurora@hyo.world>")
TUNE_BASE   = os.environ.get("AURORA_TUNE_URL_BASE",   "https://hyo.world/aurora/tune/")
UNSUB_BASE  = os.environ.get("AURORA_UNSUB_URL_BASE",  "https://hyo.world/aurora/unsub/")


# ---------------------------------------------------------------------------
# subscribers (read/write shared with aurora_public.py)
# ---------------------------------------------------------------------------

def load_subscribers() -> list[dict]:
    if not SUBSCRIBERS.exists():
        return []
    out: list[dict] = []
    with SUBSCRIBERS.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def save_subscribers(subs: list[dict]) -> None:
    tmp = SUBSCRIBERS.with_suffix(".jsonl.tmp")
    with tmp.open("w") as f:
        for s in subs:
            f.write(json.dumps(s) + "\n")
    tmp.replace(SUBSCRIBERS)


# ---------------------------------------------------------------------------
# frontmatter parsing (reuses render.py when available)
# ---------------------------------------------------------------------------

def split_frontmatter(text: str) -> tuple[dict, str]:
    if HAVE_RENDER:
        return render.split_frontmatter(text)
    meta: dict = {}
    if not text.startswith("---\n"):
        return meta, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return meta, text
    block = text[4:end]
    body = text[end + 5:]
    for line in block.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip('"')
    return meta, body


# ---------------------------------------------------------------------------
# very small markdown → html fallback (used if render.py unavailable)
# ---------------------------------------------------------------------------

_INLINE_BOLD = re.compile(r"\*\*([^*]+)\*\*")
_INLINE_ITAL = re.compile(r"(?<![\*\w])\*([^*\n]+)\*(?!\*)")
_INLINE_CODE = re.compile(r"`([^`]+)`")
_INLINE_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def _inline_html(s: str) -> str:
    s = (s.replace("&", "&amp;")
          .replace("<", "&lt;")
          .replace(">", "&gt;"))
    s = _INLINE_CODE.sub(r"<code>\1</code>", s)
    s = _INLINE_BOLD.sub(r"<strong>\1</strong>", s)
    s = _INLINE_ITAL.sub(r"<em>\1</em>", s)
    s = _INLINE_LINK.sub(r'<a href="\2">\1</a>', s)
    return s


def _tiny_markdown_to_html(text: str) -> str:
    """Minimal fallback. Prefer render.py for real output."""
    out: list[str] = []
    para: list[str] = []

    def flush():
        if para:
            out.append("<p>" + "<br>".join(_inline_html(l) for l in para) + "</p>")
            para.clear()

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line:
            flush()
            continue
        if line.startswith("## "):
            flush()
            out.append(f"<h2>{_inline_html(line[3:])}</h2>")
        elif line.startswith("# "):
            flush()
            out.append(f"<h1>{_inline_html(line[2:])}</h1>")
        elif line.startswith("> "):
            flush()
            out.append(f"<blockquote>{_inline_html(line[2:])}</blockquote>")
        elif line.startswith("- ") or line.startswith("* "):
            para.append(line)
        else:
            para.append(line)
    flush()
    return "\n".join(out)


# ---------------------------------------------------------------------------
# email template
# ---------------------------------------------------------------------------

EMAIL_CSS = """
  body { margin:0; padding:0; background:#0a0a12; color:#e8e4d9;
         font-family: 'Inter', -apple-system, sans-serif;
         font-size:16px; line-height:1.65; }
  .wrap { max-width: 580px; margin:0 auto; padding: 32px 24px 48px; }
  .hero { font-family: 'Syne', Georgia, serif; font-size: 22px;
          color:#f6c98a; letter-spacing: -0.01em; margin-bottom: 8px; }
  .date { font-family: 'DM Mono', monospace; color:#8a8678;
          font-size: 12px; text-transform: uppercase;
          letter-spacing: 0.12em; margin-bottom: 28px; }
  .body { color:#e8e4d9; }
  .body h1, .body h2 { font-family:'Syne',Georgia,serif;
                        color:#f6c98a; margin-top: 24px; }
  .body p { margin: 0 0 16px; }
  .body em { color:#f6c98a; }
  .body a { color:#e8b877; text-decoration: underline; }
  .body blockquote { border-left: 2px solid #e8b877;
                      padding: 2px 0 2px 14px;
                      color:#cac5b4; margin: 16px 0; }
  .foot { margin-top: 40px; padding-top: 20px;
          border-top: 1px solid #262230;
          font-family:'DM Mono', monospace;
          font-size: 11px; color:#666156; line-height: 1.7; }
  .foot a { color:#8a8678; text-decoration: underline; }
"""


def render_html_email(body_md: str, meta: dict, sub: dict) -> str:
    date = meta.get("date", "")
    # Prefer render.py's parser if available — it handles more edge cases.
    if HAVE_RENDER:
        try:
            body_html = render.md_to_html_body(body_md)
        except Exception:
            body_html = _tiny_markdown_to_html(body_md)
    else:
        body_html = _tiny_markdown_to_html(body_md)

    tune_url  = TUNE_BASE  + sub.get("id", "")
    unsub_url = UNSUB_BASE + sub.get("id", "")

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aurora · {date}</title>
<style>{EMAIL_CSS}</style>
</head>
<body>
  <div class="wrap">
    <div class="hero">Aurora &#9737;</div>
    <div class="date">{date}</div>
    <div class="body">
{body_html}
    </div>
    <div class="foot">
      Aurora read the world for you this morning.<br>
      <a href="{tune_url}">tune what she watches</a> ·
      <a href="{unsub_url}">pause or unsubscribe</a>
    </div>
  </div>
</body>
</html>
"""


def render_plain_email(body_md: str, meta: dict, sub: dict) -> str:
    date = meta.get("date", "")
    tune_url  = TUNE_BASE  + sub.get("id", "")
    unsub_url = UNSUB_BASE + sub.get("id", "")
    return (
        f"Aurora \u2609  {date}\n\n"
        f"{body_md.strip()}\n\n"
        f"---\n"
        f"Aurora read the world for you this morning.\n"
        f"Tune: {tune_url}\n"
        f"Pause or unsubscribe: {unsub_url}\n"
    )


# ---------------------------------------------------------------------------
# delivery backends
# ---------------------------------------------------------------------------

def pick_backend(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("AURORA_EMAIL_BACKEND", "").strip().lower()
    if env:
        return env
    if os.environ.get("RESEND_API_KEY"):
        return "resend"
    if os.environ.get("SMTP_HOST"):
        return "smtp"
    return "dry"


def send_resend(to: str, subject: str, html: str, text: str, sender: str) -> dict:
    api_key = os.environ.get("RESEND_API_KEY", "")
    if not api_key:
        raise RuntimeError("RESEND_API_KEY not set")
    payload = json.dumps({
        "from": sender,
        "to": [to],
        "subject": subject,
        "html": html,
        "text": text,
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace") or "{}")
            return {"ok": True, "id": data.get("id"), "raw": data}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        return {"ok": False, "error": f"HTTP {e.code}: {body}"}
    except urllib.error.URLError as e:
        return {"ok": False, "error": f"URL error: {e}"}


def send_smtp(to: str, subject: str, html: str, text: str, sender: str) -> dict:
    host = os.environ.get("SMTP_HOST", "")
    port = int(os.environ.get("SMTP_PORT", "587"))
    user = os.environ.get("SMTP_USER", "")
    pw   = os.environ.get("SMTP_PASS", "")
    frm  = os.environ.get("SMTP_FROM", sender)
    if not host:
        raise RuntimeError("SMTP_HOST not set")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"]    = frm
    msg["To"]      = to
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")

    try:
        with smtplib.SMTP(host, port, timeout=30) as s:
            s.ehlo()
            s.starttls(context=ssl.create_default_context())
            s.ehlo()
            if user:
                s.login(user, pw)
            s.send_message(msg)
        return {"ok": True, "id": None}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ---------------------------------------------------------------------------
# main loop
# ---------------------------------------------------------------------------

def _default_subject(meta: dict, sub: dict) -> str:
    s = meta.get("subject_line", "").strip().strip('"').strip("'")
    if s:
        return s
    return f"Aurora \u2609  {meta.get('date', dt.date.today().isoformat())}"


def dispatch(manifest_path: Path, backend: str, dry: bool,
             only_sub: str | None) -> int:
    if not manifest_path.exists():
        print(f"[send_email] no manifest at {manifest_path}", file=sys.stderr)
        return 2
    manifest = json.loads(manifest_path.read_text())

    subs_by_id = {s["id"]: s for s in load_subscribers()}

    ok_count = 0
    err_count = 0
    for r in manifest.get("results", []):
        sub_id = r.get("id")
        if only_sub and sub_id != only_sub:
            continue
        if r.get("error") or not r.get("path"):
            print(f"[send_email] skip {sub_id}: no brief")
            err_count += 1
            continue

        brief_path = Path(r["path"])
        if not brief_path.exists():
            print(f"[send_email] skip {sub_id}: missing file {brief_path}")
            err_count += 1
            continue

        # Preview mode (sub_preview) is not a real subscriber; skip send.
        sub = subs_by_id.get(sub_id)
        if sub is None:
            print(f"[send_email] skip {sub_id}: not in subscribers.jsonl (preview?)")
            continue

        text = brief_path.read_text()
        meta, body = split_frontmatter(text)
        subject = _default_subject(meta, sub)
        html = render_html_email(body, meta, sub)
        plain = render_plain_email(body, meta, sub)
        to = sub.get("email", "")

        if not to:
            print(f"[send_email] skip {sub_id}: no email")
            err_count += 1
            continue

        if dry or backend == "dry":
            print(f"[send_email] DRY → {to} · subject={subject!r} · {len(html)} html · {len(plain)} text")
            ok_count += 1
            continue

        sender = DEFAULT_FROM
        if backend == "resend":
            result = send_resend(to, subject, html, plain, sender)
        elif backend == "smtp":
            result = send_smtp(to, subject, html, plain, sender)
        else:
            print(f"[send_email] unknown backend {backend!r}", file=sys.stderr)
            return 2

        if result.get("ok"):
            ok_count += 1
            print(f"[send_email] sent {sub_id} → {to} · id={result.get('id')}")
            # stamp lastSent / lastBriefId on the live record
            sub["lastSent"]    = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            sub["lastBriefId"] = f"{manifest.get('date')}/{sub_id}"
            hist = sub.setdefault("history", [])
            hist.append({
                "date":    manifest.get("date"),
                "briefId": sub["lastBriefId"],
                "subject": subject,
            })
            subs_by_id[sub_id] = sub
        else:
            err_count += 1
            print(f"[send_email] FAIL {sub_id} → {to}: {result.get('error')}", file=sys.stderr)

    # persist updated subscriber state (only if we actually sent anything live)
    if not dry and backend != "dry":
        save_subscribers(list(subs_by_id.values()))

    print(f"[send_email] done · ok={ok_count} · err={err_count}")
    return 0 if err_count == 0 else 2


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--sub",  help="only send to a single subscriber id")
    ap.add_argument("--backend", help="resend | smtp | dry")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    date = args.date or dt.date.today().isoformat()
    manifest = PUBLIC_OUT / date / "manifest.json"

    backend = pick_backend(args.backend)
    if backend == "dry" and not args.dry_run:
        print("[send_email] no backend configured — running as dry-run. "
              "Set RESEND_API_KEY or SMTP_HOST to send for real.")
    return dispatch(manifest, backend=backend, dry=args.dry_run,
                    only_sub=args.sub)


if __name__ == "__main__":
    sys.exit(main())
