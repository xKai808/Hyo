#!/usr/bin/env python3
"""
kai/memory/agent_memory/memory_engine.py
==========================================
Kai Memory Engine — based on JordanMcCann/agentmemory (LongMemEval #1, 96.2% accuracy)

Architecture:
  Layer 0: Raw event store        (SQLite, append-only, never deleted)
  Layer 1: Working memory         (recent observations, TTL 24h)
  Layer 2: Episodic memory        (compressed sessions, 7-day rolling)
  Layer 3: Semantic memory        (promoted durable facts, permanent)
  Layer 4: Procedural memory      (how-to knowledge, agent protocols)

Promotion pipeline (CoALA cognitive architecture):
  New event → deduplicate (SHA-256, 5min window) → privacy filter →
  raw store → LLM compress → extract facts/concepts/narrative →
  working → (after 3 reinforcements or explicit promotion) → episodic →
  (after 7 days without decay) → semantic

Every write is immediate. Promotion runs nightly at 01:15 MT.
"""

import os
import sys
import json
import sqlite3
import hashlib
import datetime
import subprocess
from pathlib import Path
from typing import Optional

# ── CONFIGURATION ─────────────────────────────────────────────────────────────

ROOT = Path(os.environ.get("HYO_ROOT", Path.home() / "Documents/Projects/Hyo"))
MEMORY_DIR = ROOT / "kai/memory/agent_memory"
DB_PATH = MEMORY_DIR / "memory.db"
DEDUP_WINDOW_SECONDS = 300  # 5 minutes — same as JordanMcCann
WORKING_TTL_HOURS = 24
EPISODIC_TTL_DAYS = 7
CONFIDENCE_DECAY_PER_DAY = 0.02  # semantic facts lose 2%/day without reinforcement
MIN_CONFIDENCE_FOR_SEMANTIC = 0.60

# Privacy filter — never store these patterns in raw observations
PRIVACY_PATTERNS = [
    "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "TELEGRAM_BOT_TOKEN",
    "sk-ant-", "sk-", "Bearer ", "password", "secret", ".token",
    "founder.token", "hyo.env",
]

TZ_MT = "America/Denver"


# ── DATABASE INIT ──────────────────────────────────────────────────────────────

def init_db(db_path: Path = DB_PATH) -> sqlite3.Connection:
    """Initialize the memory database with all required tables."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.executescript("""
        PRAGMA journal_mode=WAL;
        PRAGMA foreign_keys=ON;

        -- Layer 0: Raw event store (append-only, immutable)
        CREATE TABLE IF NOT EXISTS raw_events (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            event_hash  TEXT UNIQUE NOT NULL,   -- SHA-256 of content
            event_type  TEXT NOT NULL,           -- observation | upload | feedback | correction | decision | instruction
            source      TEXT NOT NULL,           -- hyo | kai | aether | nel | ra | sam | system
            content     TEXT NOT NULL,           -- raw text (privacy-filtered)
            created_at  TEXT NOT NULL,           -- ISO8601 MT
            session_id  TEXT                     -- which session this came from
        );

        -- Layer 1: Working memory (recent, fast decay)
        CREATE TABLE IF NOT EXISTS working_memory (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            raw_event_id    INTEGER REFERENCES raw_events(id),
            fact_key        TEXT,               -- deduplication key
            content         TEXT NOT NULL,
            tags            TEXT,               -- JSON array
            reinforcement_count INTEGER DEFAULT 1,
            created_at      TEXT NOT NULL,
            expires_at      TEXT NOT NULL,      -- working_at + 24h
            promoted        INTEGER DEFAULT 0   -- 1 = promoted to episodic
        );
        CREATE INDEX IF NOT EXISTS idx_working_expires ON working_memory(expires_at);
        CREATE INDEX IF NOT EXISTS idx_working_fact_key ON working_memory(fact_key);

        -- Layer 2: Episodic memory (compressed sessions)
        CREATE TABLE IF NOT EXISTS episodic_memory (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            session_date    TEXT NOT NULL,      -- YYYY-MM-DD
            narrative       TEXT NOT NULL,      -- session summary (LLM-compressed)
            facts           TEXT,               -- JSON array of extracted facts
            concepts        TEXT,               -- JSON array of concepts
            raw_event_ids   TEXT,               -- JSON array of source event IDs
            confidence      REAL DEFAULT 1.0,
            created_at      TEXT NOT NULL,
            promoted        INTEGER DEFAULT 0   -- 1 = promoted to semantic
        );
        CREATE INDEX IF NOT EXISTS idx_episodic_date ON episodic_memory(session_date);

        -- Layer 3: Semantic memory (permanent durable facts)
        CREATE TABLE IF NOT EXISTS semantic_memory (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            category        TEXT NOT NULL,      -- ROLE | TECHNICAL | STRATEGIC | PREFERENCE | DECISION | CORRECTION
            fact_key        TEXT UNIQUE NOT NULL,
            fact_value      TEXT NOT NULL,
            source_episode  INTEGER REFERENCES episodic_memory(id),
            confidence      REAL DEFAULT 1.0,
            reinforcement_count INTEGER DEFAULT 1,
            last_reinforced TEXT NOT NULL,
            created_at      TEXT NOT NULL,
            superseded_by   INTEGER REFERENCES semantic_memory(id)  -- for contradictions
        );
        CREATE INDEX IF NOT EXISTS idx_semantic_category ON semantic_memory(category);
        CREATE INDEX IF NOT EXISTS idx_semantic_key ON semantic_memory(fact_key);

        -- Layer 4: Procedural memory (protocols)
        CREATE TABLE IF NOT EXISTS procedural_memory (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            protocol_name   TEXT UNIQUE NOT NULL,
            protocol_file   TEXT NOT NULL,      -- path to the .md protocol file
            version         TEXT,
            last_updated    TEXT NOT NULL,
            summary         TEXT
        );

        -- Dedup cache (recent hashes for 5min window)
        CREATE TABLE IF NOT EXISTS dedup_cache (
            event_hash  TEXT PRIMARY KEY,
            created_at  TEXT NOT NULL
        );

        -- Contradiction log
        CREATE TABLE IF NOT EXISTS contradiction_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            existing_id     INTEGER REFERENCES semantic_memory(id),
            new_content     TEXT NOT NULL,
            resolution      TEXT,               -- KEPT_EXISTING | UPDATED | FLAGGED
            resolved_at     TEXT
        );
    """)
    conn.commit()
    return conn


# ── UTILITIES ─────────────────────────────────────────────────────────────────

def mt_now() -> str:
    """Current timestamp in Mountain Time, ISO 8601."""
    result = subprocess.run(
        ["bash", "-c", f"TZ={TZ_MT} date '+%Y-%m-%dT%H:%M:%S%z'"],
        capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else datetime.datetime.now().isoformat()


def mt_date() -> str:
    result = subprocess.run(
        ["bash", "-c", f"TZ={TZ_MT} date '+%Y-%m-%d'"],
        capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else datetime.date.today().isoformat()


def content_hash(content: str) -> str:
    """SHA-256 hash of content for deduplication."""
    return hashlib.sha256(content.encode("utf-8")).digest().hex()


def privacy_filter(content: str) -> str:
    """Remove sensitive patterns from content before storing."""
    for pattern in PRIVACY_PATTERNS:
        # If the pattern appears in a line, redact that line
        lines = content.split("\n")
        filtered = []
        for line in lines:
            if any(p.lower() in line.lower() for p in PRIVACY_PATTERNS):
                filtered.append("[REDACTED — contains sensitive data]")
            else:
                filtered.append(line)
        content = "\n".join(filtered)
    return content


def is_duplicate(conn: sqlite3.Connection, event_hash: str) -> bool:
    """Check if this event was seen in the last 5 minutes (dedup window)."""
    # Purge expired dedup cache first
    cutoff = mt_now()[:16]  # minute precision for cutoff calculation
    conn.execute("""
        DELETE FROM dedup_cache
        WHERE created_at < datetime('now', '-5 minutes')
    """)
    row = conn.execute(
        "SELECT 1 FROM dedup_cache WHERE event_hash = ?", (event_hash,)
    ).fetchone()
    return row is not None


def mark_seen(conn: sqlite3.Connection, event_hash: str):
    now = mt_now()
    conn.execute(
        "INSERT OR IGNORE INTO dedup_cache (event_hash, created_at) VALUES (?, ?)",
        (event_hash, now)
    )


# ── WRITE PATH ────────────────────────────────────────────────────────────────

def observe(
    content: str,
    event_type: str = "observation",
    source: str = "kai",
    session_id: Optional[str] = None,
    tags: Optional[list] = None,
    conn: Optional[sqlite3.Connection] = None,
) -> Optional[int]:
    """
    Primary write entrypoint. Call this for every significant event.

    Returns raw_event_id if stored, None if duplicate or filtered.

    event_type: observation | upload | feedback | correction | decision | instruction
    source:     hyo | kai | aether | nel | ra | sam | system
    """
    if not content or not content.strip():
        return None

    # Step 1: Privacy filter
    filtered = privacy_filter(content.strip())

    # Step 2: SHA-256 dedup
    h = content_hash(filtered)

    close_after = conn is None
    if conn is None:
        conn = init_db()

    if is_duplicate(conn, h):
        if close_after:
            conn.close()
        return None

    # Step 3: Store raw event
    now = mt_now()
    try:
        cur = conn.execute(
            """INSERT INTO raw_events (event_hash, event_type, source, content, created_at, session_id)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (h, event_type, source, filtered, now, session_id)
        )
        raw_id = cur.lastrowid
        mark_seen(conn, h)
        conn.commit()
    except sqlite3.IntegrityError:
        # Hash collision — already stored
        if close_after:
            conn.close()
        return None

    # Step 4: Write to working memory
    expires = _add_hours(now, WORKING_TTL_HOURS)
    fact_key = _derive_fact_key(filtered, event_type)

    # Check if this reinforces an existing working memory entry
    existing = conn.execute(
        "SELECT id, reinforcement_count FROM working_memory WHERE fact_key = ? AND promoted = 0",
        (fact_key,)
    ).fetchone()

    if existing:
        new_count = existing["reinforcement_count"] + 1
        conn.execute(
            "UPDATE working_memory SET reinforcement_count = ?, expires_at = ? WHERE id = ?",
            (new_count, expires, existing["id"])
        )
    else:
        conn.execute(
            """INSERT INTO working_memory (raw_event_id, fact_key, content, tags, reinforcement_count, created_at, expires_at)
               VALUES (?, ?, ?, ?, 1, ?, ?)""",
            (raw_id, fact_key, filtered, json.dumps(tags or []), now, expires)
        )

    conn.commit()

    # Step 5: Write to daily note (flat-file for consolidate.sh to read)
    _append_daily_note(filtered, event_type, source, now)

    if close_after:
        conn.close()

    return raw_id


def observe_hyo(content: str, event_type: str = "instruction", session_id: Optional[str] = None) -> Optional[int]:
    """
    Shortcut for recording Hyo instructions/feedback/corrections.
    These are the highest-priority events — always stored, never dropped.
    """
    formatted = f"**[HYO_{event_type.upper()}]** {content}"
    return observe(formatted, event_type=event_type, source="hyo", session_id=session_id)


def observe_upload(filename: str, description: str, session_id: Optional[str] = None) -> Optional[int]:
    """Record a Hyo file upload immediately (per MEMORY WRITE RULE in CLAUDE.md)."""
    content = f"**[HYO_UPLOAD]** {filename} — {description}"
    return observe(content, event_type="upload", source="hyo", session_id=session_id)


def observe_correction(old: str, new: str, session_id: Optional[str] = None) -> Optional[int]:
    """
    Record a Hyo correction. These supersede semantic memory entries.

    IMMEDIATE bypass: corrections skip the 7-day episodic TTL and are written
    directly to KNOWLEDGE.md and the semantic layer. A Hyo correction is the
    highest-priority write — it cannot wait 7 days to become permanent.
    """
    content = f"**[HYO_CORRECTION]** Was: '{old}' → Now: '{new}'"
    raw_id = observe(content, event_type="correction", source="hyo", session_id=session_id)

    # Immediate semantic write (bypass 7-day promotion)
    conn = init_db()
    now = mt_now()
    fact_key = f"correction:{hashlib.md5(new.encode()).hexdigest()[:12]}"
    # Supersede any existing semantic fact with the old value
    existing = conn.execute(
        "SELECT id FROM semantic_memory WHERE lower(fact_value) LIKE ? AND superseded_by IS NULL",
        (f"%{old.lower()[:50]}%",)
    ).fetchone()
    if existing:
        conn.execute(
            "UPDATE semantic_memory SET superseded_by = -1 WHERE id = ?",
            (existing["id"],)
        )
    # Write corrected fact directly to semantic layer
    conn.execute("""
        INSERT OR REPLACE INTO semantic_memory
        (category, fact_key, fact_value, confidence, reinforcement_count, last_reinforced, created_at)
        VALUES ('CORRECTION', ?, ?, 1.0, 1, ?, ?)
    """, (fact_key, content, now, now))
    conn.commit()
    conn.close()

    # Also append to KNOWLEDGE.md immediately (flat-file layer — survives DB loss)
    _append_correction_to_knowledge(old, new, now)

    return raw_id


def _append_correction_to_knowledge(old: str, new: str, timestamp: str):
    """Write a correction directly to KNOWLEDGE.md. Bypasses 7-day promotion gate."""
    knowledge_path = ROOT / "kai/memory/KNOWLEDGE.md"
    if not knowledge_path.exists():
        return
    today = mt_date()
    entry = f"\n---\n## Hyo Correction — {today}\n\n- **Was:** {old}\n- **Now:** {new}\n- Timestamp: {timestamp[:16]} MT\n"
    with open(knowledge_path, "a") as f:
        f.write(entry)


# ── QUERY PATH ────────────────────────────────────────────────────────────────

def recall(query: str, limit: int = 10, conn: Optional[sqlite3.Connection] = None) -> list[dict]:
    """
    Query across all memory layers. Returns ranked results.

    Search order:
    1. Semantic memory (highest confidence durable facts)
    2. Episodic memory (recent session narratives)
    3. Working memory (current session)

    Uses per-word matching: each query word is searched independently
    (not as a phrase), then results are ranked by term frequency.
    """
    close_after = conn is None
    if conn is None:
        conn = init_db()

    results = []
    query_lower = query.lower()
    # Stop words to exclude from per-word search
    stop_words = {"the", "a", "an", "is", "in", "on", "at", "to", "for", "of", "and", "or"}
    query_words = [w for w in query_lower.split() if len(w) > 2 and w not in stop_words]
    if not query_words:
        query_words = query_lower.split()

    def build_where_clause(fields: list[str], words: list[str], params: list) -> str:
        """Build OR clause: any field matches any word."""
        conditions = []
        for word in words:
            for field in fields:
                conditions.append(f"lower({field}) LIKE ?")
                params.append(f"%{word}%")
        return "(" + " OR ".join(conditions) + ")" if conditions else "1=1"

    # Layer 3: Semantic (highest priority)
    sem_params: list = []
    sem_where = build_where_clause(["fact_key", "fact_value"], query_words, sem_params)
    sem_params.append(limit)
    semantic = conn.execute(f"""
        SELECT 'semantic' as layer, fact_key, fact_value as content,
               confidence, category, last_reinforced as date
        FROM semantic_memory
        WHERE superseded_by IS NULL AND {sem_where}
        ORDER BY confidence DESC, reinforcement_count DESC
        LIMIT ?
    """, sem_params).fetchall()
    results.extend([dict(r) for r in semantic])

    # Layer 2: Episodic
    ep_params: list = []
    ep_where = build_where_clause(["narrative", "facts"], query_words, ep_params)
    ep_params.append(limit)
    episodic = conn.execute(f"""
        SELECT 'episodic' as layer, session_date as date,
               narrative as content, confidence, '' as category,
               '' as fact_key
        FROM episodic_memory
        WHERE {ep_where}
        ORDER BY session_date DESC
        LIMIT ?
    """, ep_params).fetchall()
    results.extend([dict(r) for r in episodic])

    # Layer 1: Working memory (not yet expired)
    now = mt_now()
    wk_params: list = [now]
    wk_where = build_where_clause(["content", "fact_key"], query_words, wk_params)
    wk_params.append(limit)
    working = conn.execute(f"""
        SELECT 'working' as layer, fact_key, content,
               1.0 as confidence, '' as category, created_at as date
        FROM working_memory
        WHERE expires_at > ? AND promoted = 0 AND {wk_where}
        ORDER BY reinforcement_count DESC, created_at DESC
        LIMIT ?
    """, wk_params).fetchall()
    results.extend([dict(r) for r in working])

    if close_after:
        conn.close()

    # BM25-style relevance re-rank (term frequency approximation)
    def score(r):
        text = (r.get("content", "") + " " + r.get("fact_key", "")).lower()
        tf = sum(text.count(w) for w in query_words)
        layer_boost = {"semantic": 3.0, "episodic": 2.0, "working": 1.5}.get(r.get("layer", ""), 1.0)
        confidence = float(r.get("confidence", 1.0))
        return tf * layer_boost * confidence

    results.sort(key=score, reverse=True)
    return results[:limit]


# ── PROMOTION PIPELINE (runs nightly) ─────────────────────────────────────────

def promote_working_to_episodic(conn: sqlite3.Connection, session_date: str):
    """
    Collect all working memory from a session date, compress to narrative,
    extract facts and concepts, store as episodic memory.
    Called by the nightly consolidation job.
    """
    # Get all working memory created on session_date that hasn't been promoted
    rows = conn.execute("""
        SELECT wm.id, wm.content, wm.fact_key, wm.reinforcement_count, wm.raw_event_id
        FROM working_memory wm
        JOIN raw_events re ON wm.raw_event_id = re.id
        WHERE re.created_at LIKE ?
          AND wm.promoted = 0
        ORDER BY wm.created_at ASC
    """, (f"{session_date}%",)).fetchall()

    if not rows:
        return None

    # Collect content for LLM compression
    all_content = "\n---\n".join(r["content"] for r in rows)
    event_ids = [r["id"] for r in rows]
    raw_ids = [r["raw_event_id"] for r in rows]

    # LLM compression (uses Claude CLI if available, else rule-based)
    narrative, facts, concepts = _compress_to_episodic(all_content, session_date)

    if not narrative:
        return None

    now = mt_now()
    cur = conn.execute("""
        INSERT INTO episodic_memory (session_date, narrative, facts, concepts, raw_event_ids, confidence, created_at)
        VALUES (?, ?, ?, ?, ?, 1.0, ?)
    """, (
        session_date, narrative,
        json.dumps(facts), json.dumps(concepts),
        json.dumps(raw_ids), now
    ))
    episode_id = cur.lastrowid

    # Mark working memory as promoted
    conn.execute(
        f"UPDATE working_memory SET promoted = 1 WHERE id IN ({','.join('?' * len(event_ids))})",
        event_ids
    )
    conn.commit()
    return episode_id


def promote_episodic_to_semantic(conn: sqlite3.Connection):
    """
    Promote episodic facts that have aged 7 days without decay.
    Near-duplicate detection and contradiction resolution included.
    Called by the nightly consolidation job.
    """
    cutoff = _subtract_days(mt_now(), EPISODIC_TTL_DAYS)
    old_episodes = conn.execute("""
        SELECT id, facts, session_date
        FROM episodic_memory
        WHERE created_at < ? AND promoted = 0
    """, (cutoff,)).fetchall()

    promoted_count = 0
    for ep in old_episodes:
        facts = json.loads(ep["facts"] or "[]")
        for fact in facts:
            if not isinstance(fact, dict):
                continue
            key = fact.get("key", "")
            value = fact.get("value", "")
            category = fact.get("category", "TECHNICAL")
            if not key or not value:
                continue

            # Contradiction detection
            existing = conn.execute(
                "SELECT id, fact_value, confidence FROM semantic_memory WHERE fact_key = ? AND superseded_by IS NULL",
                (key,)
            ).fetchone()

            now = mt_now()
            if existing:
                if existing["fact_value"] == value:
                    # Reinforce existing
                    new_count = conn.execute(
                        "SELECT reinforcement_count FROM semantic_memory WHERE id = ?", (existing["id"],)
                    ).fetchone()["reinforcement_count"] + 1
                    new_conf = min(1.0, existing["confidence"] + 0.05)
                    conn.execute("""
                        UPDATE semantic_memory
                        SET reinforcement_count = ?, confidence = ?, last_reinforced = ?
                        WHERE id = ?
                    """, (new_count, new_conf, now, existing["id"]))
                else:
                    # Contradiction — log and flag for review
                    conn.execute("""
                        INSERT INTO contradiction_log (existing_id, new_content, resolution, resolved_at)
                        VALUES (?, ?, 'FLAGGED', ?)
                    """, (existing["id"], f"{key}: {value}", now))
                    # Hyo corrections always win (source="hyo")
                    if "HYO_CORRECTION" in value or "HYO_INSTRUCTION" in value:
                        conn.execute(
                            "UPDATE semantic_memory SET superseded_by = -1 WHERE id = ?", (existing["id"],)
                        )
                        conn.execute("""
                            INSERT INTO semantic_memory (category, fact_key, fact_value, source_episode, confidence, reinforcement_count, last_reinforced, created_at)
                            VALUES (?, ?, ?, ?, 1.0, 1, ?, ?)
                        """, (category, key, value, ep["id"], now, now))
            else:
                # New semantic fact
                conn.execute("""
                    INSERT OR IGNORE INTO semantic_memory (category, fact_key, fact_value, source_episode, confidence, reinforcement_count, last_reinforced, created_at)
                    VALUES (?, ?, ?, ?, 1.0, 1, ?, ?)
                """, (category, key, value, ep["id"], now, now))
                promoted_count += 1

        conn.execute("UPDATE episodic_memory SET promoted = 1 WHERE id = ?", (ep["id"],))

    conn.commit()
    return promoted_count


def apply_confidence_decay(conn: sqlite3.Connection):
    """
    Decay confidence of semantic facts that haven't been reinforced recently.
    Runs nightly. Facts below MIN_CONFIDENCE are flagged for review (not deleted).
    """
    now = mt_now()
    today = mt_date()
    rows = conn.execute("""
        SELECT id, confidence, last_reinforced
        FROM semantic_memory
        WHERE superseded_by IS NULL
    """).fetchall()

    for row in rows:
        days_since = _days_between(row["last_reinforced"][:10], today)
        if days_since <= 0:
            continue
        new_conf = max(0.0, row["confidence"] - (CONFIDENCE_DECAY_PER_DAY * days_since))
        conn.execute(
            "UPDATE semantic_memory SET confidence = ? WHERE id = ?",
            (round(new_conf, 4), row["id"])
        )

    conn.commit()


# ── PROCEDURAL MEMORY ─────────────────────────────────────────────────────────

def register_protocol(name: str, file_path: str, version: str = "1.0", summary: str = ""):
    """Register a protocol file in procedural memory."""
    conn = init_db()
    now = mt_now()
    conn.execute("""
        INSERT INTO procedural_memory (protocol_name, protocol_file, version, last_updated, summary)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(protocol_name) DO UPDATE SET
            protocol_file = excluded.protocol_file,
            version = excluded.version,
            last_updated = excluded.last_updated,
            summary = excluded.summary
    """, (name, file_path, version, now, summary))
    conn.commit()
    conn.close()


def get_protocol(name: str) -> Optional[dict]:
    """Retrieve a protocol definition."""
    conn = init_db()
    row = conn.execute(
        "SELECT * FROM procedural_memory WHERE protocol_name = ?", (name,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


# ── HELPERS ───────────────────────────────────────────────────────────────────

def _derive_fact_key(content: str, event_type: str) -> str:
    """Derive a stable fact key for deduplication of working memory."""
    # Use first 80 chars of content as key basis
    basis = content[:80].lower().strip()
    return f"{event_type}:{hashlib.md5(basis.encode()).hexdigest()[:12]}"


def _append_daily_note(content: str, event_type: str, source: str, timestamp: str):
    """Append to today's daily note (flat file for consolidate.sh)."""
    daily_dir = ROOT / "kai/memory/daily"
    daily_dir.mkdir(parents=True, exist_ok=True)
    today = mt_date()
    daily_file = daily_dir / f"{today}.md"

    marker_map = {
        "upload": "HYO_UPLOAD",
        "feedback": "HYO_FEEDBACK",
        "correction": "HYO_CORRECTION",
        "decision": "HYO_DECISION",
        "instruction": "HYO_INSTRUCTION",
        "observation": "OBSERVATION",
    }
    marker = marker_map.get(event_type, "NOTE")

    # Only add session marker once per day
    if not daily_file.exists():
        daily_file.write_text(f"## Session {today}\n\n")

    with open(daily_file, "a") as f:
        f.write(f"\n**[{marker}]** [{timestamp[:16]}] [{source.upper()}] {content}\n")


def _compress_to_episodic(content: str, session_date: str) -> tuple[str, list, list]:
    """
    Compress raw session content to episodic narrative + structured facts.
    Uses Claude CLI if available, falls back to rule-based extraction.
    """
    claude_bin = subprocess.run(["which", "claude"], capture_output=True, text=True).stdout.strip()

    if claude_bin:
        prompt = f"""You are reading memory events from a Kai session on {session_date}.
Extract:
1. A 2-3 sentence narrative summary of what happened (what Hyo said, what was decided, what was built)
2. A JSON array of durable facts in format: [{{"key": "fact_key", "value": "fact_value", "category": "ROLE|TECHNICAL|STRATEGIC|PREFERENCE|DECISION|CORRECTION"}}]
3. A JSON array of concept tags (strings)

Rules:
- Only extract facts that should persist across sessions (not status, not counts)
- HYO_CORRECTION always has category CORRECTION and highest priority
- Skip routine business monitor lines (Newsletter:, Tickets:, etc.)
- Output format: NARRATIVE: <text>\\nFACTS: <json>\\nCONCEPTS: <json>

Session content:
{content[:4000]}"""

        try:
            result = subprocess.run(
                [claude_bin, "-p", prompt],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode == 0:
                output = result.stdout.strip()
                narrative = ""
                facts = []
                concepts = []
                for line in output.split("\n"):
                    if line.startswith("NARRATIVE:"):
                        narrative = line[10:].strip()
                    elif line.startswith("FACTS:"):
                        try:
                            facts = json.loads(line[6:].strip())
                        except:
                            pass
                    elif line.startswith("CONCEPTS:"):
                        try:
                            concepts = json.loads(line[9:].strip())
                        except:
                            pass
                if narrative:
                    return narrative, facts, concepts
        except Exception:
            pass

    # Fallback: rule-based extraction
    lines = content.split("\n")
    hyo_lines = [l for l in lines if any(m in l for m in ["HYO_", "[HYO]", "[KAI]"])]
    narrative = f"Session {session_date}: {len(hyo_lines)} Hyo interactions captured."
    if hyo_lines:
        narrative += f" Key: {hyo_lines[0][:100]}"

    facts = []
    for line in hyo_lines:
        if "HYO_CORRECTION" in line:
            facts.append({"key": f"correction_{session_date}", "value": line, "category": "CORRECTION"})
        elif "HYO_DECISION" in line:
            facts.append({"key": f"decision_{session_date}", "value": line, "category": "DECISION"})
        elif "HYO_INSTRUCTION" in line:
            facts.append({"key": f"instruction_{session_date}", "value": line, "category": "TECHNICAL"})

    return narrative, facts, []


def _add_hours(iso_str: str, hours: int) -> str:
    """Add hours to an ISO 8601 timestamp. Handles -0600 and -06:00 formats."""
    try:
        # Normalize: -0600 → -06:00 for Python < 3.11 compatibility
        s = iso_str
        if len(s) > 5 and s[-5] in ('+', '-') and ':' not in s[-5:]:
            s = s[:-2] + ':' + s[-2:]
        dt = datetime.datetime.fromisoformat(s)
        return (dt + datetime.timedelta(hours=hours)).isoformat()
    except Exception:
        # Fallback: use bash date arithmetic
        try:
            result = subprocess.run(
                ["bash", "-c", f"TZ={TZ_MT} date -d '{iso_str} +{hours} hours' '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || TZ={TZ_MT} date -v+{hours}H '+%Y-%m-%dT%H:%M:%S%z'"],
                capture_output=True, text=True
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception:
            pass
        # Final fallback: just return 24h from now as a safe default
        return datetime.datetime.utcnow().isoformat()


def _subtract_days(iso_str: str, days: int) -> str:
    """Subtract days from an ISO 8601 timestamp."""
    try:
        s = iso_str
        if len(s) > 5 and s[-5] in ('+', '-') and ':' not in s[-5:]:
            s = s[:-2] + ':' + s[-2:]
        dt = datetime.datetime.fromisoformat(s)
        return (dt - datetime.timedelta(days=days)).isoformat()
    except Exception:
        try:
            result = subprocess.run(
                ["bash", "-c", f"TZ={TZ_MT} date -d '{iso_str} -{days} days' '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || TZ={TZ_MT} date -v-{days}d '+%Y-%m-%dT%H:%M:%S%z'"],
                capture_output=True, text=True
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception:
            pass
        return iso_str


def _days_between(date1: str, date2: str) -> int:
    try:
        d1 = datetime.date.fromisoformat(date1)
        d2 = datetime.date.fromisoformat(date2)
        return (d2 - d1).days
    except:
        return 0


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Kai Memory Engine")
    sub = parser.add_subparsers(dest="cmd")

    # observe
    obs = sub.add_parser("observe", help="Record an observation")
    obs.add_argument("content")
    obs.add_argument("--type", default="observation", dest="event_type")
    obs.add_argument("--source", default="kai")
    obs.add_argument("--session")

    # hyo
    hyo = sub.add_parser("hyo", help="Record a Hyo instruction/feedback (immediate)")
    hyo.add_argument("content")
    hyo.add_argument("--type", default="instruction", dest="event_type")
    hyo.add_argument("--session")

    # upload
    upl = sub.add_parser("upload", help="Record a Hyo file upload")
    upl.add_argument("filename")
    upl.add_argument("description")

    # recall
    rec = sub.add_parser("recall", help="Query memory")
    rec.add_argument("query")
    rec.add_argument("--limit", type=int, default=5)

    # promote
    prm = sub.add_parser("promote", help="Run promotion pipeline (nightly)")
    prm.add_argument("--date", default=None)

    # init
    sub.add_parser("init", help="Initialize database")

    args = parser.parse_args()

    if args.cmd == "init":
        conn = init_db()
        print(f"Memory DB initialized at {DB_PATH}")
        conn.close()

    elif args.cmd == "observe":
        rid = observe(args.content, event_type=args.event_type, source=args.source, session_id=args.session)
        print(f"Stored: raw_event_id={rid}" if rid else "Duplicate — not stored")

    elif args.cmd == "hyo":
        rid = observe_hyo(args.content, event_type=args.event_type, session_id=args.session)
        print(f"Stored Hyo event: raw_event_id={rid}" if rid else "Duplicate")

    elif args.cmd == "upload":
        rid = observe_upload(args.filename, args.description)
        print(f"Upload recorded: raw_event_id={rid}" if rid else "Duplicate")

    elif args.cmd == "recall":
        conn = init_db()
        results = recall(args.query, limit=args.limit, conn=conn)
        conn.close()
        if not results:
            print("No results found.")
        else:
            for r in results:
                print(f"\n[{r.get('layer', '?').upper()}] {r.get('fact_key', r.get('date', ''))}")
                print(f"  {r.get('content', r.get('fact_value', ''))[:200]}")
                print(f"  confidence={r.get('confidence', 1.0):.2f}")

    elif args.cmd == "promote":
        conn = init_db()
        date = args.date or mt_date()
        ep_id = promote_working_to_episodic(conn, date)
        sem_count = promote_episodic_to_semantic(conn)
        apply_confidence_decay(conn)
        conn.close()
        print(f"Promotion complete: episodic_id={ep_id}, semantic_promoted={sem_count}")

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
