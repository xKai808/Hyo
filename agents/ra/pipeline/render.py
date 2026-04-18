#!/usr/bin/env python3
"""
render.py — Hyo Daily Newsletter, stage 3 (render)

Reads a markdown newsletter produced by synthesize.py and renders it
to a single standalone HTML file with Hyo styling (Syne display font,
DM Mono body font, HUMAN-side dark palette). The output is a single
file — no external CSS, no JS, safe to open locally or ship to
hyo.world/daily/YYYY-MM-DD.

ZERO external dependencies. Python 3.9+ stdlib only. No markdown
library, no jinja — a purpose-built tiny markdown parser and
string-formatted HTML template. The parser handles exactly the
subset that the synthesis prompt produces:

    # / ## / ### / #### headers
    paragraphs
    bullet lists (-, *)
    numbered lists (1. 2. ...)
    **bold**
    *italic*
    `inline code`
    [link](url)
    > blockquotes
    --- horizontal rules
    ```fenced code blocks```
    YAML-ish frontmatter (stripped + parsed for title/date)

Usage:
    python3 render.py                          # today
    python3 render.py --date 2026-04-09        # specific day
    python3 render.py --in some.md --out some.html
"""

from __future__ import annotations

import argparse
import datetime as dt
import html as _html
import os
import re
import sys
from pathlib import Path

DEFAULT_NEWSLETTERS_DIR = Path.home() / "Documents" / "Projects" / "Hyo" / "newsletters"


# ---------------------------------------------------------------------------
# frontmatter
# ---------------------------------------------------------------------------

def split_frontmatter(text: str) -> tuple[dict, str]:
    meta: dict[str, str] = {}
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
            meta[k.strip()] = v.strip()
    return meta, body


# ---------------------------------------------------------------------------
# inline formatting
# ---------------------------------------------------------------------------

_INLINE_CODE_RE = re.compile(r"`([^`]+)`")
_BOLD_RE = re.compile(r"\*\*([^*]+)\*\*")
_ITALIC_RE = re.compile(r"(?<![\*\w])\*([^*\n]+)\*(?!\*)")
_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def render_inline(text: str) -> str:
    """Escape + apply inline markdown -> HTML. Order matters."""
    # protect inline code first so its contents aren't touched
    code_slots: list[str] = []

    def _code_sub(m: re.Match) -> str:
        code_slots.append(_html.escape(m.group(1)))
        return f"\x00CODE{len(code_slots)-1}\x00"

    text = _INLINE_CODE_RE.sub(_code_sub, text)

    # escape everything else
    text = _html.escape(text, quote=False)

    # links (after escape, since titles are plain text anyway)
    def _link_sub(m: re.Match) -> str:
        label, url = m.group(1), m.group(2)
        # url was escaped by _html.escape — undo for the href only
        href = url.replace("&amp;", "&")
        return f'<a href="{_html.escape(href, quote=True)}">{label}</a>'

    text = _LINK_RE.sub(_link_sub, text)
    text = _BOLD_RE.sub(r"<strong>\1</strong>", text)
    text = _ITALIC_RE.sub(r"<em>\1</em>", text)

    # restore code
    for i, c in enumerate(code_slots):
        text = text.replace(f"\x00CODE{i}\x00", f"<code>{c}</code>", 1)

    return text


# ---------------------------------------------------------------------------
# block parser
# ---------------------------------------------------------------------------

_HEADER_RE = re.compile(r"^(#{1,6})\s+(.*)$")
_BULLET_RE = re.compile(r"^[\-\*]\s+(.*)$")
_NUMLIST_RE = re.compile(r"^(\d+)\.\s+(.*)$")
_BLOCKQUOTE_RE = re.compile(r"^>\s?(.*)$")
_HR_RE = re.compile(r"^-{3,}\s*$")
_FENCE_RE = re.compile(r"^```(.*)$")


def strip_preamble_code_blocks(md: str) -> str:
    """Strip fenced code blocks that appear before the first heading.

    synthesize.py outputs a structured ```yaml block containing entity/topic
    data before the prose newsletter. That block is machine-readable metadata —
    it should never be rendered to the reader. This strips it along with any
    other code blocks in the pre-heading preamble.

    Gate question: does the rendered HTML start with a <pre> block instead of
    a heading? YES → this function wasn't called or the strip failed.
    """
    first_heading = re.search(r"^#+\s", md, re.MULTILINE)
    if not first_heading:
        return md
    preamble = md[: first_heading.start()]
    content = md[first_heading.start() :]
    # Remove all fenced code blocks from the preamble
    cleaned_preamble = re.sub(r"```[^\n]*\n[\s\S]*?```\n?", "", preamble)
    return cleaned_preamble + content


def md_to_html_body(md: str) -> str:
    md = strip_preamble_code_blocks(md)
    lines = md.splitlines()
    i = 0
    out: list[str] = []

    def close_list(kind: str | None):
        if kind == "ul":
            out.append("</ul>")
        elif kind == "ol":
            out.append("</ol>")
        elif kind == "bq":
            out.append("</blockquote>")

    list_kind: str | None = None
    paragraph_buf: list[str] = []

    def flush_paragraph():
        nonlocal paragraph_buf
        if paragraph_buf:
            text = " ".join(paragraph_buf).strip()
            if text:
                out.append(f"<p>{render_inline(text)}</p>")
            paragraph_buf = []

    def end_block():
        nonlocal list_kind
        flush_paragraph()
        close_list(list_kind)
        list_kind = None

    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()

        # fenced code block
        m = _FENCE_RE.match(stripped)
        if m:
            end_block()
            lang = m.group(1).strip()
            i += 1
            code_lines: list[str] = []
            while i < len(lines) and not _FENCE_RE.match(lines[i].rstrip()):
                code_lines.append(lines[i])
                i += 1
            i += 1  # skip closing fence
            code = _html.escape("\n".join(code_lines))
            cls = f' class="lang-{_html.escape(lang)}"' if lang else ""
            out.append(f"<pre><code{cls}>{code}</code></pre>")
            continue

        # blank line
        if not stripped.strip():
            end_block()
            i += 1
            continue

        # horizontal rule
        if _HR_RE.match(stripped):
            end_block()
            out.append("<hr/>")
            i += 1
            continue

        # header
        m = _HEADER_RE.match(stripped)
        if m:
            end_block()
            level = len(m.group(1))
            text = render_inline(m.group(2).strip())
            out.append(f"<h{level}>{text}</h{level}>")
            i += 1
            continue

        # bullet list
        m = _BULLET_RE.match(stripped)
        if m:
            flush_paragraph()
            if list_kind != "ul":
                close_list(list_kind)
                out.append("<ul>")
                list_kind = "ul"
            out.append(f"<li>{render_inline(m.group(1).strip())}</li>")
            i += 1
            continue

        # numbered list
        m = _NUMLIST_RE.match(stripped)
        if m:
            flush_paragraph()
            if list_kind != "ol":
                close_list(list_kind)
                out.append("<ol>")
                list_kind = "ol"
            out.append(f"<li>{render_inline(m.group(2).strip())}</li>")
            i += 1
            continue

        # blockquote
        m = _BLOCKQUOTE_RE.match(stripped)
        if m:
            flush_paragraph()
            if list_kind != "bq":
                close_list(list_kind)
                out.append("<blockquote>")
                list_kind = "bq"
            out.append(f"<p>{render_inline(m.group(1).strip())}</p>")
            i += 1
            continue

        # default: paragraph accumulator
        if list_kind is not None:
            close_list(list_kind)
            list_kind = None
        paragraph_buf.append(stripped.strip())
        i += 1

    end_block()
    return "\n".join(out)


# ---------------------------------------------------------------------------
# HTML template (Hyo dark palette)
# ---------------------------------------------------------------------------

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{title}</title>
<meta name="description" content="Ra Brief — {date}" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet" />
<style>
  *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
  :root {{
    --bg:         #0c0d14;
    --bg-card:    #12141e;
    --fg:         #e8e2d6;
    --fg-body:    rgba(232,226,214,0.88);
    --muted:      rgba(232,226,214,0.50);
    --accent:     #d4a853;
    --accent-soft:rgba(212,168,83,0.15);
    --rule:       rgba(212,168,83,0.12);
    --code-bg:    rgba(232,226,214,0.05);
    --font-body:  'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    --font-mono:  'JetBrains Mono', ui-monospace, 'Cascadia Mono', monospace;
  }}

  html {{ scroll-behavior: smooth; }}
  html, body {{ background: var(--bg); color: var(--fg); font-family: var(--font-body); -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }}
  body {{ min-height: 100vh; display: flex; justify-content: center; padding: 72px 28px 140px; }}
  main {{ width: 100%; max-width: 680px; }}

  /* Header */
  header.meta {{ padding-bottom: 36px; margin-bottom: 52px; border-bottom: 1px solid var(--rule); }}
  header.meta .eyebrow {{ font-family: var(--font-mono); font-size: 11px; font-weight: 500; letter-spacing: 0.22em; text-transform: uppercase; color: var(--accent); }}
  header.meta h1 {{ font-weight: 800; font-size: clamp(36px, 5.5vw, 52px); line-height: 1.05; letter-spacing: -0.025em; margin-top: 16px; color: var(--fg); }}
  header.meta .sub {{ font-size: 14px; letter-spacing: 0.01em; color: var(--muted); margin-top: 16px; font-weight: 400; }}

  /* Article typography */
  article h1, article h2, article h3, article h4 {{ font-weight: 700; letter-spacing: -0.02em; color: var(--fg); line-height: 1.15; }}
  article h1 {{ font-size: 28px; margin-top: 48px; margin-bottom: 18px; }}
  article h2 {{ font-size: 22px; margin-top: 52px; margin-bottom: 16px; padding-top: 24px; border-top: 1px solid var(--rule); }}
  article h3 {{ font-size: 17px; margin-top: 36px; margin-bottom: 12px; }}
  article h4 {{ font-family: var(--font-mono); font-size: 12px; font-weight: 500; text-transform: uppercase; letter-spacing: 0.12em; color: var(--accent); margin-top: 32px; margin-bottom: 12px; }}

  article p {{ font-size: 16px; line-height: 1.8; margin-bottom: 20px; color: var(--fg-body); font-weight: 400; }}
  article a {{ color: var(--accent); text-decoration: none; border-bottom: 1px solid rgba(212,168,83,0.3); transition: border-color 0.2s, color 0.2s; }}
  article a:hover {{ border-bottom-color: var(--accent); color: #e8c070; }}
  article strong {{ color: var(--fg); font-weight: 600; }}
  article em {{ color: var(--fg-body); font-style: italic; }}

  article ul, article ol {{ margin: 0 0 24px 24px; }}
  article li {{ font-size: 16px; line-height: 1.8; margin-bottom: 10px; color: var(--fg-body); font-weight: 400; }}
  article li::marker {{ color: var(--accent); }}

  article blockquote {{ border-left: 3px solid var(--accent); padding: 8px 0 8px 20px; margin: 24px 0; background: var(--accent-soft); border-radius: 0 8px 8px 0; }}
  article blockquote p {{ margin-bottom: 8px; color: var(--fg-body); font-style: italic; }}

  article code {{ font-family: var(--font-mono); background: var(--code-bg); padding: 2px 7px; border-radius: 4px; font-size: 14px; color: var(--accent); }}
  article pre {{ background: var(--bg-card); padding: 20px 24px; border-radius: 10px; overflow-x: auto; margin: 24px 0; border: 1px solid var(--rule); }}
  article pre code {{ background: none; padding: 0; font-size: 13px; color: var(--fg); line-height: 1.65; }}

  article hr {{ border: none; border-top: 1px solid var(--rule); margin: 48px 0; }}

  /* Footer */
  footer.sig {{ margin-top: 80px; padding-top: 28px; border-top: 1px solid var(--rule); display: flex; justify-content: space-between; align-items: center; }}
  footer.sig .left {{ display: flex; align-items: center; gap: 10px; }}
  footer.sig .dot {{ width: 6px; height: 6px; border-radius: 50%; background: var(--accent); display: inline-block; animation: blink 2.2s infinite; }}
  footer.sig .label {{ font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: var(--muted); }}
  footer.sig .brand {{ font-family: var(--font-mono); font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: var(--muted); }}
  @keyframes blink {{ 0%, 100% {{ opacity: 1; }} 50% {{ opacity: 0.15; }} }}

  /* Selection */
  ::selection {{ background: var(--accent-soft); color: var(--fg); }}

  @media (max-width: 560px) {{
    body {{ padding: 40px 20px 80px; }}
    header.meta h1 {{ font-size: 32px; }}
    article h2 {{ font-size: 19px; }}
    article p, article li {{ font-size: 15px; line-height: 1.75; }}
  }}
</style>
</head>
<body>
<main>
  <header class="meta">
    <div class="eyebrow">Ra · hyo.world</div>
    <h1>{title}</h1>
    <div class="sub">{date} · morning brief</div>
  </header>
  <article>
{body}
  </article>
  <footer class="sig">
    <span class="left"><span class="dot"></span><span class="label">System online</span></span>
    <span class="brand">hyo.world</span>
  </footer>
</main>
</body>
</html>
"""


def render_markdown_file(md_text: str) -> tuple[str, dict]:
    meta, body_md = split_frontmatter(md_text)
    title = meta.get("title") or f"Hyo Daily — {meta.get('date', dt.date.today().isoformat())}"
    date = meta.get("date", dt.date.today().isoformat())
    body_html = md_to_html_body(body_md)
    full = TEMPLATE.format(
        title=_html.escape(title),
        date=_html.escape(date),
        body=body_html,
    )
    return full, meta


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Render Hyo newsletter markdown -> HTML")
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--in", dest="in_path", help="Markdown input path override")
    ap.add_argument("--out", dest="out_path", help="HTML output path override")
    args = ap.parse_args()

    date_str = args.date or dt.date.today().isoformat()
    out_dir = Path(os.environ.get("HYO_NEWSLETTERS_DIR")
                   or str(DEFAULT_NEWSLETTERS_DIR)).expanduser()

    md_path = Path(args.in_path) if args.in_path else out_dir / f"{date_str}.md"
    html_path = Path(args.out_path) if args.out_path else out_dir / f"{date_str}.html"

    if not md_path.exists():
        print(f"[error] markdown not found: {md_path}", file=sys.stderr)
        return 1

    md_text = md_path.read_text()
    html_text, meta = render_markdown_file(md_text)

    html_path.parent.mkdir(parents=True, exist_ok=True)
    html_path.write_text(html_text)

    print(f"[ok] rendered → {html_path}")
    if meta:
        print(f"[info] frontmatter: {meta}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
