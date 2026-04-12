#!/usr/bin/env python3
"""
gather.py — Hyo Daily Newsletter, stage 1 (gather)

ZERO external dependencies. Python 3.9+ standard library only.
No pip, no venv, no feedparser, no requests, no bs4, no pyyaml.

Reads sources.json, pulls free public data from the configured
sources, normalizes every record to one schema, and writes
newline-delimited JSON to:

    {output_dir}/YYYY-MM-DD.jsonl

...while appending everything to the rolling CEO-brain file:

    {output_dir}/{rolling_file}     (default: all.jsonl)

Every source is wrapped in try/except — one source failing never
kills the run. The script exits 0 even on per-source failures so
cron doesn't spam error mail. A non-zero exit only means a
config/filesystem error that the operator needs to fix.

Usage:
    python3 gather.py                    # normal run for today
    python3 gather.py --date 2026-04-09  # backfill a specific date
    python3 gather.py --dry-run          # don't write anything
    python3 gather.py --sources other.json

Cron (Mini, 03:00 MDT daily):
    0 3 * * * cd ~/Documents/Projects/Hyo/newsletter && \\
              /usr/bin/env python3 gather.py >> gather.log 2>&1
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import html
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# config defaults
# ---------------------------------------------------------------------------

HERE = Path(__file__).resolve().parent
SOURCES_PATH = HERE / "sources.json"

DEFAULT_OUTPUT_DIR = Path.home() / "Documents" / "Projects" / "Kai" / "intelligence"
DEFAULT_ROLLING = "all.jsonl"
DEFAULT_UA = "hyo-newsletter/0.2 (+https://hyo.world)"
DEFAULT_TIMEOUT = 20
BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)


# ---------------------------------------------------------------------------
# record schema
# ---------------------------------------------------------------------------

@dataclass
class Record:
    source: str
    topic: str
    title: str
    url: str
    summary: str
    score: float
    timestamp: str
    published: str = ""
    meta: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------
# utilities
# ---------------------------------------------------------------------------

def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def clean_text(s: str | None, limit: int = 600) -> str:
    if not s:
        return ""
    s = _TAG_RE.sub("", s)
    s = html.unescape(s)
    s = _WS_RE.sub(" ", s).strip()
    return s[:limit]


def safe_host(url: str) -> str:
    try:
        return urllib.parse.urlparse(url).netloc or ""
    except Exception:
        return ""


def http_get(
    url: str,
    *,
    ua: str,
    timeout: int,
    params: dict | None = None,
    headers: dict | None = None,
    retries: int = 2,
) -> bytes:
    """GET a URL and return raw bytes (gzip-decoded if needed)."""
    if params:
        q = urllib.parse.urlencode(params, doseq=True)
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}{q}"
    hdrs = {
        "User-Agent": ua,
        "Accept": "application/json, text/html;q=0.9, */*;q=0.8",
        "Accept-Encoding": "gzip",
    }
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs)

    last: Exception | None = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = resp.read()
                if resp.headers.get("Content-Encoding", "").lower() == "gzip":
                    data = gzip.decompress(data)
                return data
        except (urllib.error.HTTPError, urllib.error.URLError, socket.timeout) as exc:
            last = exc
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
        except Exception as exc:  # noqa: BLE001
            last = exc
            break
    raise RuntimeError(f"GET failed: {url} :: {last}")


def http_get_json(url: str, **kw) -> Any:
    return json.loads(http_get(url, **kw).decode("utf-8", errors="replace"))


def http_get_text(url: str, **kw) -> str:
    return http_get(url, **kw).decode("utf-8", errors="replace")


# ---------------------------------------------------------------------------
# minimal RSS/Atom parser (stdlib xml.etree)
# ---------------------------------------------------------------------------

_NS = {
    "atom": "http://www.w3.org/2005/Atom",
    "dc": "http://purl.org/dc/elements/1.1/",
    "content": "http://purl.org/rss/1.0/modules/content/",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rss1": "http://purl.org/rss/1.0/",
}


def _etext(el: ET.Element | None) -> str:
    if el is None:
        return ""
    return (el.text or "").strip()


def parse_feed(raw: bytes) -> list[dict]:
    """Parse RSS 2.0, RDF/RSS 1.0, or Atom into a list of {title, link, summary, published}."""
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        return []

    items: list[dict] = []
    tag = root.tag.lower()

    # RSS 2.0: <rss><channel><item/></channel></rss>
    if tag.endswith("rss"):
        channel = root.find("channel")
        if channel is None:
            return []
        for item in channel.findall("item"):
            title = _etext(item.find("title"))
            link = _etext(item.find("link"))
            desc = _etext(item.find("description"))
            pub = _etext(item.find("pubDate"))
            items.append({"title": title, "link": link, "summary": desc, "published": pub})

    # Atom: <feed><entry/></feed>
    elif tag.endswith("feed"):
        for entry in root.findall("atom:entry", _NS):
            title = _etext(entry.find("atom:title", _NS))
            link = ""
            link_el = entry.find("atom:link", _NS)
            if link_el is not None:
                link = link_el.get("href", "") or _etext(link_el)
            summary = _etext(entry.find("atom:summary", _NS)) or _etext(entry.find("atom:content", _NS))
            pub = _etext(entry.find("atom:published", _NS)) or _etext(entry.find("atom:updated", _NS))
            items.append({"title": title, "link": link, "summary": summary, "published": pub})

    # RDF / RSS 1.0: <rdf:RDF><item/></rdf:RDF>
    elif tag.endswith("rdf"):
        for item in root.findall("rss1:item", _NS):
            title = _etext(item.find("rss1:title", _NS))
            link = _etext(item.find("rss1:link", _NS))
            desc = _etext(item.find("rss1:description", _NS))
            pub = _etext(item.find("dc:date", _NS))
            items.append({"title": title, "link": link, "summary": desc, "published": pub})

    return items


# ---------------------------------------------------------------------------
# minimal HTMLParser for GitHub trending
# ---------------------------------------------------------------------------

class _TrendingParser(HTMLParser):
    """Walks github.com/trending and collects {repo, desc, stars_today} rows."""

    def __init__(self):
        super().__init__()
        self.rows: list[dict] = []
        self._in_article = False
        self._depth = 0
        self._cur: dict = {}
        # state trackers for nested capture
        self._capture: str | None = None   # "repo" | "desc" | "stars"
        self._buf: list[str] = []
        self._float_sm_right = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class", "") or ""

        if tag == "article" and "Box-row" in cls:
            self._in_article = True
            self._depth = 1
            self._cur = {"repo": "", "desc": "", "stars_today": 0}
            return

        if not self._in_article:
            return

        self._depth += 1

        # repo is the <a> inside <h2 class="h3 lh-condensed"> (the first <a> we see with href="/o/r")
        if tag == "a" and not self._cur.get("repo"):
            href = a.get("href", "")
            if href.startswith("/") and href.count("/") == 2 and not href.startswith("/trending"):
                self._cur["repo"] = href.lstrip("/")

        # description is the first <p> we see inside the article
        if tag == "p" and not self._cur.get("desc"):
            self._capture = "desc"
            self._buf = []

        # stars today: span with class "d-inline-block float-sm-right"
        if tag == "span" and "float-sm-right" in cls:
            self._float_sm_right = True
            self._capture = "stars"
            self._buf = []

    def handle_endtag(self, tag):
        if not self._in_article:
            return
        self._depth -= 1

        if self._capture == "desc" and tag == "p":
            self._cur["desc"] = clean_text(" ".join(self._buf), 400)
            self._capture = None
            self._buf = []

        if self._capture == "stars" and tag == "span":
            txt = "".join(self._buf)
            n = re.sub(r"[^\d]", "", txt)
            try:
                self._cur["stars_today"] = int(n) if n else 0
            except ValueError:
                self._cur["stars_today"] = 0
            self._capture = None
            self._buf = []
            self._float_sm_right = False

        if tag == "article" and self._depth <= 0:
            if self._cur.get("repo"):
                self.rows.append(self._cur)
            self._in_article = False
            self._cur = {}
            self._depth = 0

    def handle_data(self, data):
        if self._capture:
            self._buf.append(data)


def parse_github_trending(html_text: str) -> list[dict]:
    p = _TrendingParser()
    try:
        p.feed(html_text)
    except Exception:
        pass
    return p.rows


# ---------------------------------------------------------------------------
# per-source fetchers
# ---------------------------------------------------------------------------

def fetch_hn_algolia(src: dict, cfg: dict) -> list[Record]:
    data = http_get_json(src["url"], ua=cfg["ua"], timeout=cfg["timeout"])
    out: list[Record] = []
    for hit in data.get("hits", [])[: cfg["limit"]]:
        title = hit.get("title") or hit.get("story_title") or ""
        link = hit.get("url") or f"https://news.ycombinator.com/item?id={hit.get('objectID','')}"
        if not title:
            continue
        pts = int(hit.get("points") or 0)
        cmts = int(hit.get("num_comments") or 0)
        score = min(10.0, (pts / 30.0) + (cmts / 60.0))
        out.append(Record(
            source=src["name"], topic=src["topic"],
            title=clean_text(title, 240), url=link,
            summary=f"HN: {pts} pts, {cmts} comments",
            score=round(score, 2),
            timestamp=now_iso(),
            published=hit.get("created_at") or "",
            meta={"points": pts, "comments": cmts, "host": safe_host(link)},
        ))
    return out


def fetch_rss(src: dict, cfg: dict) -> list[Record]:
    raw = http_get(src["url"], ua=cfg["ua"], timeout=cfg["timeout"])
    entries = parse_feed(raw)
    out: list[Record] = []
    for e in entries[: cfg["limit"]]:
        title, link = e.get("title", ""), e.get("link", "")
        if not title or not link:
            continue
        out.append(Record(
            source=src["name"], topic=src["topic"],
            title=clean_text(title, 240), url=link,
            summary=clean_text(e.get("summary", ""), 500),
            score=5.0,
            timestamp=now_iso(),
            published=e.get("published", ""),
            meta={"host": safe_host(link)},
        ))
    return out


def fetch_reddit(src: dict, cfg: dict) -> list[Record]:
    sub = src["subreddit"]
    period = src.get("period", "day")
    limit = min(int(src.get("limit", 25)), cfg["limit"])
    url = f"https://www.reddit.com/r/{sub}/top.json"
    try:
        data = http_get_json(
            url, ua=cfg["ua"], timeout=cfg["timeout"],
            params={"t": period, "limit": limit},
            headers={"User-Agent": cfg["ua"]},
        )
    except RuntimeError as exc:
        if "429" in str(exc) or "403" in str(exc):
            time.sleep(3)
            data = http_get_json(
                url, ua=BROWSER_UA, timeout=cfg["timeout"],
                params={"t": period, "limit": limit},
                headers={"User-Agent": BROWSER_UA},
            )
        else:
            raise
    out: list[Record] = []
    for child in data.get("data", {}).get("children", []):
        d = child.get("data", {})
        title = d.get("title", "")
        if not title:
            continue
        permalink = f"https://www.reddit.com{d.get('permalink','')}"
        ups = int(d.get("ups") or 0)
        cmts = int(d.get("num_comments") or 0)
        score = min(10.0, (ups / 800.0) + (cmts / 250.0))
        published = ""
        if d.get("created_utc"):
            try:
                published = dt.datetime.fromtimestamp(
                    d["created_utc"], tz=dt.timezone.utc
                ).isoformat()
            except Exception:
                published = ""
        out.append(Record(
            source=src["name"], topic=src["topic"],
            title=clean_text(title, 240), url=permalink,
            summary=clean_text(d.get("selftext", ""), 500)
                    or f"r/{sub}: {ups} ups, {cmts} comments",
            score=round(score, 2),
            timestamp=now_iso(),
            published=published,
            meta={"ups": ups, "comments": cmts, "subreddit": sub, "host": "reddit.com"},
        ))
    return out


def fetch_github_trending(src: dict, cfg: dict) -> list[Record]:
    period = src.get("period", "daily")
    url = f"https://github.com/trending?since={period}"
    html_text = http_get_text(url, ua=BROWSER_UA, timeout=cfg["timeout"])
    rows = parse_github_trending(html_text)
    out: list[Record] = []
    for row in rows[: cfg["limit"]]:
        repo = row.get("repo", "")
        if not repo:
            continue
        stars = int(row.get("stars_today") or 0)
        score = min(10.0, stars / 80.0)
        out.append(Record(
            source=src["name"], topic=src["topic"],
            title=repo,
            url=f"https://github.com/{repo}",
            summary=row.get("desc") or f"{stars} stars today",
            score=round(score, 2),
            timestamp=now_iso(),
            meta={"stars_today": stars, "host": "github.com"},
        ))
    return out


def fetch_coingecko(src: dict, cfg: dict) -> list[Record]:
    url = "https://api.coingecko.com/api/v3/coins/markets"
    params = {
        "vs_currency": src.get("vs_currency", "usd"),
        "order": "market_cap_desc",
        "per_page": str(min(int(src.get("per_page", 25)), cfg["limit"])),
        "page": "1",
        "price_change_percentage": "24h",
    }
    data = http_get_json(url, ua=cfg["ua"], timeout=cfg["timeout"], params=params)
    out: list[Record] = []
    for coin in data:
        name = coin.get("name", "")
        symbol = (coin.get("symbol") or "").upper()
        price = coin.get("current_price")
        change = coin.get("price_change_percentage_24h") or 0.0
        title = f"{name} ({symbol}) {'+' if change >= 0 else ''}{change:.2f}% @ ${price}"
        score = min(10.0, abs(change) / 2.0)
        out.append(Record(
            source=src["name"], topic=src["topic"],
            title=title,
            url=f"https://www.coingecko.com/en/coins/{coin.get('id','')}",
            summary=f"Market cap ${coin.get('market_cap',0):,} · Vol ${coin.get('total_volume',0):,}",
            score=round(score, 2),
            timestamp=now_iso(),
            meta={
                "symbol": symbol, "price_usd": price,
                "change_24h_pct": change, "market_cap": coin.get("market_cap"),
            },
        ))
    return out


def fetch_yahoo_quote(src: dict, cfg: dict) -> list[Record]:
    """Yahoo v7/finance/quote now requires a crumb cookie and 401s without
    one. Skip it entirely. Use v8/finance/chart which is public and fast,
    iterating per symbol with aggressive per-call timeouts so one bad
    symbol can't sink the whole run."""
    symbols = src.get("symbols", [])
    if not symbols:
        return []
    per_timeout = min(int(cfg["timeout"]), 6)
    out: list[Record] = []
    for sym in symbols:
        try:
            alt = http_get_json(
                f"https://query1.finance.yahoo.com/v8/finance/chart/{urllib.parse.quote(sym)}",
                ua=BROWSER_UA, timeout=per_timeout, retries=0,
                params={"interval": "1d", "range": "5d"},
                headers={"User-Agent": BROWSER_UA},
            )
        except Exception:
            continue

        results = (alt.get("chart") or {}).get("result") or []
        if not results:
            continue
        meta = results[0].get("meta") or {}
        price = meta.get("regularMarketPrice")
        prev = meta.get("chartPreviousClose") or meta.get("previousClose")
        if price is None or prev is None or prev == 0:
            continue
        try:
            change = (float(price) - float(prev)) / float(prev) * 100.0
        except (TypeError, ValueError, ZeroDivisionError):
            continue
        name = meta.get("symbol") or sym
        out.append(Record(
            source=src["name"], topic=src["topic"],
            title=f"{name} {'+' if change >= 0 else ''}{change:.2f}% @ {price}",
            url=f"https://finance.yahoo.com/quote/{urllib.parse.quote(sym)}",
            summary=f"Previous close {prev} · currency {meta.get('currency','?')}",
            score=round(min(10.0, abs(change) / 1.5), 2),
            timestamp=now_iso(),
            meta={"symbol": sym, "price": price, "prev_close": prev,
                  "change_pct": change, "currency": meta.get("currency")},
        ))
    return out


def fetch_fred(src: dict, cfg: dict) -> list[Record]:
    key = os.environ.get("FRED_API_KEY", "").strip()
    if not key:
        return []
    series_id = src["series_id"]
    url = "https://api.stlouisfed.org/fred/series/observations"
    data = http_get_json(
        url, ua=cfg["ua"], timeout=cfg["timeout"],
        params={"series_id": series_id, "api_key": key,
                "file_type": "json", "sort_order": "desc", "limit": "2"},
    )
    obs = data.get("observations", [])
    if not obs:
        return []
    latest = obs[0]
    prev = obs[1] if len(obs) > 1 else None
    try:
        latest_val = float(latest.get("value", "nan"))
    except ValueError:
        return []
    delta = None
    if prev:
        try:
            delta = latest_val - float(prev.get("value", "nan"))
        except ValueError:
            delta = None
    title = f"FRED {series_id}: {latest_val}"
    if delta is not None:
        title += f" ({'+' if delta >= 0 else ''}{delta:.3f})"
    return [Record(
        source=src["name"], topic=src["topic"],
        title=title,
        url=f"https://fred.stlouisfed.org/series/{series_id}",
        summary=f"Observation {latest.get('date','?')}: {latest_val}",
        score=5.0,
        timestamp=now_iso(),
        published=latest.get("date", ""),
        meta={"series_id": series_id, "value": latest_val, "delta": delta},
    )]


FETCHERS = {
    "hn_algolia": fetch_hn_algolia,
    "rss": fetch_rss,
    "reddit": fetch_reddit,
    "github_trending": fetch_github_trending,
    "coingecko": fetch_coingecko,
    "yahoo_quote": fetch_yahoo_quote,
    "fred": fetch_fred,
}


# ---------------------------------------------------------------------------
# main pipeline
# ---------------------------------------------------------------------------

def load_sources(path: Path) -> tuple[list[dict], dict]:
    with path.open("r") as f:
        doc = json.load(f)
    return doc.get("sources", []), doc.get("config", {})


def write_jsonl(records: list[Record], path: Path, *, append: bool) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = "a" if append else "w"
    count = 0
    with path.open(mode) as f:
        for rec in records:
            f.write(json.dumps(asdict(rec), ensure_ascii=False) + "\n")
            count += 1
    return count


def main() -> int:
    ap = argparse.ArgumentParser(description="Hyo newsletter gather stage (stdlib-only).")
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--dry-run", action="store_true", help="Don't write any files")
    ap.add_argument("--sources", default=str(SOURCES_PATH))
    ap.add_argument("--only", help="Run only sources whose name contains this substring")
    args = ap.parse_args()

    try:
        sources, gcfg = load_sources(Path(args.sources))
    except FileNotFoundError:
        print(f"[error] sources file not found: {args.sources}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"[error] bad json in sources file: {exc}", file=sys.stderr)
        return 1

    output_dir = Path(os.path.expanduser(
        gcfg.get("output_dir") or str(DEFAULT_OUTPUT_DIR)
    ))
    rolling = gcfg.get("rolling_file") or DEFAULT_ROLLING
    run_cfg = {
        "ua": gcfg.get("user_agent") or DEFAULT_UA,
        "timeout": int(gcfg.get("request_timeout") or DEFAULT_TIMEOUT),
        "limit": int(gcfg.get("max_items_per_source") or 50),
    }

    date_str = args.date or dt.date.today().isoformat()
    daily_path = output_dir / f"{date_str}.jsonl"
    rolling_path = output_dir / rolling

    if args.only:
        sources = [s for s in sources if args.only in s.get("name", "")]

    all_records: list[Record] = []
    stats: list[tuple[str, int, str]] = []
    t0 = time.time()

    for src in sources:
        name = src.get("name", "?")
        stype = src.get("type")
        fn = FETCHERS.get(stype)
        if not fn:
            stats.append((name, 0, f"skip:unknown_type={stype}"))
            continue
        src_t0 = time.time()
        try:
            recs = fn(src, run_cfg)
            all_records.extend(recs)
            stats.append((name, len(recs), f"ok in {time.time()-src_t0:.1f}s"))
        except Exception as exc:  # noqa: BLE001
            stats.append((name, 0, f"fail:{type(exc).__name__}:{str(exc)[:120]}"))

    if args.dry_run:
        print(f"[dry-run] would write {len(all_records)} records → {daily_path}")
        print(f"[dry-run] would append {len(all_records)} records → {rolling_path}")
    else:
        try:
            n_daily = write_jsonl(all_records, daily_path, append=False)
            n_roll = write_jsonl(all_records, rolling_path, append=True)
        except OSError as exc:
            print(f"[error] write failed: {exc}", file=sys.stderr)
            return 1
        print(f"[ok] wrote {n_daily} records → {daily_path}")
        print(f"[ok] appended {n_roll} records → {rolling_path}")

    print(f"\nRun took {time.time()-t0:.1f}s", file=sys.stderr)
    print("Source summary:", file=sys.stderr)
    for name, count, status in stats:
        print(f"  {name:<30} {count:>4}  {status}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
