#!/usr/bin/env python3
"""
tickets-db.py — SQLite backend for the Hyo ticket system
=========================================================
Replaces tickets.jsonl with a proper SQLite database.

WHY:
  tickets.jsonl grew to 55MB because notes arrays had no cap and were never archived.
  Every git add -A risked staging 55MB. Context injection was impossible — you can't
  inject 14M tokens. SQLite allows search_tickets() to inject top-10 relevant tickets
  (~2K tokens) instead of the whole file.

COMMANDS:
  migrate              — one-time import of tickets.jsonl → tickets.db
  create               — create a ticket (args: JSON on stdin or flags)
  update <id>          — update status/note/field
  close <id>           — close with evidence
  search <query>       — BM25 full-text search, returns top 10 JSON
  query                — filter by agent/status/priority
  export               — write tickets.db → tickets.jsonl (for git history / backup)
  stats                — count by status/priority/agent

SCHEMA:
  tickets table: all standard fields
  tickets_fts: FTS5 virtual table for BM25 search over title + notes + summary
  notes stored as JSON array in text column, capped at 20 (enforced by trigger)

Usage:
  python3 bin/tickets-db.py migrate
  python3 bin/tickets-db.py search "run_analysis line 108"
  python3 bin/tickets-db.py query --agent aether --status OPEN
  python3 bin/tickets-db.py stats
"""

import sqlite3
import json
import sys
import os
import argparse
import re
from datetime import datetime

HYO_ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
JSONL_PATH = os.path.join(HYO_ROOT, "kai/tickets/tickets.jsonl")
DB_PATH    = os.path.join(HYO_ROOT, "kai/tickets/tickets.db")
TZ_CMD     = "America/Denver"

def ts():
    import subprocess
    try:
        r = subprocess.run(
            ["date", "+%Y-%m-%dT%H:%M:%S%z"],
            capture_output=True, text=True, timeout=3,
            env={**os.environ, "TZ": TZ_CMD}
        )
        return r.stdout.strip()
    except Exception:
        return datetime.utcnow().isoformat() + "Z"


def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_schema(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS tickets (
            id                TEXT PRIMARY KEY,
            owner             TEXT NOT NULL DEFAULT 'kai',
            title             TEXT NOT NULL,
            priority          TEXT NOT NULL DEFAULT 'P2',
            status            TEXT NOT NULL DEFAULT 'OPEN',
            ticket_type       TEXT NOT NULL DEFAULT 'operational',
            weakness          TEXT,
            system            TEXT DEFAULT '1',
            blocked_by        TEXT,
            created_by        TEXT DEFAULT 'kai',
            created_at        TEXT NOT NULL,
            updated_at        TEXT NOT NULL,
            closed_at         TEXT,
            sla_deadline      TEXT,
            evidence          TEXT,
            summary           TEXT,
            notes_json        TEXT NOT NULL DEFAULT '[]',
            gate_verdicts     TEXT DEFAULT '{}',
            phase1_questions  TEXT DEFAULT '{}',
            simulation_passed INTEGER DEFAULT 0,
            verification_passed INTEGER DEFAULT 0
        );

        -- FTS5 standalone table for BM25 full-text search
        -- Standalone (not content-backed) for reliability with bulk inserts.
        -- notes_text is the flattened plain-text of the notes_json array.
        CREATE VIRTUAL TABLE IF NOT EXISTS tickets_fts USING fts5(
            id,
            title,
            notes_text,
            summary,
            owner
        );

        -- Keep FTS in sync with tickets table on new inserts
        -- (notes_text uses notes_json as raw text; close enough for BM25)
        CREATE TRIGGER IF NOT EXISTS tickets_ai AFTER INSERT ON tickets BEGIN
            INSERT INTO tickets_fts(id, title, notes_text, summary, owner)
            VALUES (new.id, new.title, COALESCE(new.notes_json,''),
                    COALESCE(new.summary,''), new.owner);
        END;

        -- On delete, remove from FTS
        CREATE TRIGGER IF NOT EXISTS tickets_ad AFTER DELETE ON tickets BEGIN
            DELETE FROM tickets_fts WHERE id = old.id;
        END;

        -- Notes cap enforcement: trim to 20 entries on update
        CREATE TRIGGER IF NOT EXISTS cap_notes AFTER UPDATE OF notes_json ON tickets
        WHEN json_array_length(new.notes_json) > 20
        BEGIN
            UPDATE tickets
            SET notes_json = (
                SELECT json_group_array(value)
                FROM (
                    SELECT value FROM json_each(new.notes_json)
                    ORDER BY rowid DESC LIMIT 20
                )
            )
            WHERE id = new.id;
        END;
    """)
    conn.commit()


def migrate(conn):
    """Import tickets.jsonl → tickets.db. Idempotent — skips existing IDs."""
    if not os.path.exists(JSONL_PATH):
        print(f"ERROR: {JSONL_PATH} not found")
        sys.exit(1)

    imported = 0
    skipped  = 0
    errors   = 0

    with open(JSONL_PATH, "r") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                t = json.loads(line)
            except json.JSONDecodeError as e:
                print(f"  SKIP line {lineno}: JSON error — {e}")
                errors += 1
                continue

            ticket_id = t.get("id", "")
            if not ticket_id:
                errors += 1
                continue

            # Check if already imported
            existing = conn.execute(
                "SELECT id FROM tickets WHERE id = ?", (ticket_id,)
            ).fetchone()
            if existing:
                skipped += 1
                continue

            # Normalise notes: cap at last 20
            raw_notes = t.get("notes", [])
            if isinstance(raw_notes, list) and len(raw_notes) > 20:
                raw_notes = raw_notes[-20:]
            notes_json = json.dumps(raw_notes, ensure_ascii=False)

            conn.execute("""
                INSERT OR IGNORE INTO tickets
                (id, owner, title, priority, status, ticket_type, weakness,
                 system, blocked_by, created_by, created_at, updated_at,
                 closed_at, sla_deadline, evidence, summary, notes_json,
                 gate_verdicts, phase1_questions, simulation_passed,
                 verification_passed)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                ticket_id,
                t.get("owner", "kai"),
                t.get("title", "(no title)"),
                t.get("priority", "P2"),
                t.get("status", "OPEN"),
                t.get("ticket_type", "operational"),
                t.get("weakness"),
                str(t.get("system", "1")),
                t.get("blocked_by"),
                t.get("created_by", "kai"),
                t.get("created_at", ts()),
                t.get("updated_at", ts()),
                t.get("closed_at"),
                t.get("sla_deadline"),
                t.get("evidence"),
                t.get("summary"),
                notes_json,
                json.dumps(t.get("gate_verdicts", {}), ensure_ascii=False),
                json.dumps(t.get("phase1_questions", {}), ensure_ascii=False),
                1 if t.get("simulation_passed") else 0,
                1 if t.get("verification_passed") else 0,
            ))
            imported += 1

    conn.commit()
    print(f"Migration complete: {imported} imported, {skipped} skipped (already exist), {errors} errors")
    db_size = os.path.getsize(DB_PATH)
    print(f"Database size: {db_size / 1024:.1f} KB ({db_size:,} bytes)")
    jsonl_size = os.path.getsize(JSONL_PATH) if os.path.exists(JSONL_PATH) else 0
    print(f"JSONL was:     {jsonl_size / 1024:.1f} KB")
    print(f"Size reduction: {(1 - db_size/max(jsonl_size,1))*100:.0f}%")


def search_tickets(conn, query: str, limit: int = 10, status_filter: str = None) -> list:
    """
    BM25 full-text search over tickets. Returns top-N results as dicts.
    This is the function agents call to inject relevant tickets into context.
    Output is ~200 tokens per ticket (title + status + priority + last note).
    At limit=10: ~2K tokens total — replaces 14M token JSONL injection.
    """
    sql = """
        SELECT t.id, t.title, t.owner, t.priority, t.status, t.ticket_type,
               t.created_at, t.updated_at, t.notes_json, t.evidence,
               bm25(tickets_fts) as score
        FROM tickets_fts
        JOIN tickets t USING (id)
        WHERE tickets_fts MATCH ?
    """
    params = [query]
    if status_filter:
        sql += " AND t.status = ?"
        params.append(status_filter)
    sql += " ORDER BY bm25(tickets_fts) LIMIT ?"
    params.append(limit)

    rows = conn.execute(sql, params).fetchall()
    results = []
    for row in rows:
        notes = json.loads(row["notes_json"] or "[]")
        last_note = notes[-1]["text"] if notes else None
        results.append({
            "id": row["id"],
            "title": row["title"],
            "owner": row["owner"],
            "priority": row["priority"],
            "status": row["status"],
            "type": row["ticket_type"],
            "updated": row["updated_at"][:10] if row["updated_at"] else None,
            "last_note": last_note,
            "evidence": row["evidence"],
            "bm25_score": round(row["score"], 3),
        })
    return results


def cmd_search(args):
    conn = get_conn()
    init_schema(conn)
    query = " ".join(args.query)
    results = search_tickets(conn, query, limit=args.limit,
                              status_filter=args.status)
    if not results:
        print(f"No results for: {query}")
        return
    print(f"Top {len(results)} results for '{query}':")
    for r in results:
        print(f"\n  [{r['priority']}] {r['id']} — {r['title']}")
        print(f"  owner={r['owner']} status={r['status']} updated={r['updated']}")
        if r["last_note"]:
            print(f"  last note: {r['last_note'][:120]}")
    conn.close()


def cmd_query(args):
    conn = get_conn()
    init_schema(conn)
    sql = "SELECT id, owner, title, priority, status, ticket_type, updated_at FROM tickets WHERE 1=1"
    params = []
    if args.agent:
        sql += " AND owner = ?"
        params.append(args.agent)
    if args.status:
        sql += " AND status = ?"
        params.append(args.status)
    if args.priority:
        sql += " AND priority = ?"
        params.append(args.priority)
    if args.overdue:
        sql += " AND sla_deadline < ?"
        params.append(ts())
    sql += " ORDER BY priority ASC, updated_at DESC"
    rows = conn.execute(sql, params).fetchall()
    print(f"Found {len(rows)} ticket(s):")
    for row in rows:
        print(f"  [{row['priority']}] {row['id']} ({row['status']}) — {row['title'][:70]}")
    conn.close()


def cmd_stats(args):
    conn = get_conn()
    init_schema(conn)
    total = conn.execute("SELECT COUNT(*) FROM tickets").fetchone()[0]
    print(f"Total tickets: {total}")
    print("\nBy status:")
    for row in conn.execute("SELECT status, COUNT(*) as n FROM tickets GROUP BY status ORDER BY n DESC"):
        print(f"  {row['status']}: {row['n']}")
    print("\nBy priority (open only):")
    for row in conn.execute("SELECT priority, COUNT(*) as n FROM tickets WHERE status IN ('OPEN','ACTIVE','BLOCKED') GROUP BY priority ORDER BY priority"):
        print(f"  {row['priority']}: {row['n']}")
    print("\nBy agent (open only):")
    for row in conn.execute("SELECT owner, COUNT(*) as n FROM tickets WHERE status IN ('OPEN','ACTIVE','BLOCKED') GROUP BY owner ORDER BY n DESC LIMIT 10"):
        print(f"  {row['owner']}: {row['n']}")
    db_size = os.path.getsize(DB_PATH)
    print(f"\nDatabase size: {db_size / 1024:.1f} KB")
    conn.close()


def cmd_create(args):
    conn = get_conn()
    init_schema(conn)
    today = datetime.now().strftime("%Y%m%d")
    # Generate ID
    count = conn.execute(
        "SELECT COUNT(*) FROM tickets WHERE owner = ? AND created_at LIKE ?",
        (args.agent, f"{datetime.now().strftime('%Y-%m-%d')}%")
    ).fetchone()[0]
    ticket_id = f"TASK-{today}-{args.agent}-{(count+1):03d}"
    # Check duplicate title
    dup = conn.execute(
        "SELECT id FROM tickets WHERE title = ? AND status NOT IN ('CLOSED','ARCHIVED')",
        (args.title,)
    ).fetchone()
    if dup:
        print(f"DUPLICATE: ticket with same title already exists: {dup['id']}")
        conn.close()
        return
    now = ts()
    conn.execute("""
        INSERT INTO tickets (id, owner, title, priority, status, ticket_type,
            weakness, created_by, created_at, updated_at, notes_json)
        VALUES (?,?,?,?,?,?,?,?,?,?,'[]')
    """, (ticket_id, args.agent, args.title, args.priority, "OPEN",
          args.type, args.weakness, "kai", now, now))
    conn.commit()
    print(f"Created {ticket_id} ({args.priority}) → {args.agent}: {args.title}")
    conn.close()


def cmd_update(args):
    conn = get_conn()
    init_schema(conn)
    row = conn.execute("SELECT * FROM tickets WHERE id = ?", (args.id,)).fetchone()
    if not row:
        print(f"ERROR: Ticket {args.id} not found")
        conn.close()
        sys.exit(1)
    now = ts()
    notes = json.loads(row["notes_json"] or "[]")
    if args.note:
        notes.append({"timestamp": now, "text": args.note})
        if len(notes) > 20:
            notes = notes[-20:]
    updates = {"updated_at": now, "notes_json": json.dumps(notes)}
    if args.status:
        updates["status"] = args.status
        if args.status in ("CLOSED", "ARCHIVED"):
            updates["closed_at"] = now
    if args.evidence:
        updates["evidence"] = args.evidence
    set_clause = ", ".join(f"{k} = ?" for k in updates)
    conn.execute(
        f"UPDATE tickets SET {set_clause} WHERE id = ?",
        list(updates.values()) + [args.id]
    )
    conn.commit()
    print(f"Updated {args.id}")
    conn.close()


def cmd_export(args):
    """Export tickets.db → tickets.jsonl for backup / git history."""
    conn = get_conn()
    init_schema(conn)
    rows = conn.execute("SELECT * FROM tickets ORDER BY created_at").fetchall()
    out_path = args.output or JSONL_PATH
    with open(out_path, "w") as f:
        for row in rows:
            d = dict(row)
            d["notes"] = json.loads(d.pop("notes_json", "[]"))
            d["gate_verdicts"] = json.loads(d.pop("gate_verdicts", "{}") or "{}")
            d["phase1_questions"] = json.loads(d.pop("phase1_questions", "{}") or "{}")
            d["simulation_passed"] = bool(d["simulation_passed"])
            d["verification_passed"] = bool(d["verification_passed"])
            f.write(json.dumps(d, ensure_ascii=False) + "\n")
    print(f"Exported {len(rows)} tickets → {out_path}")
    conn.close()


def main():
    parser = argparse.ArgumentParser(description="Hyo ticket database (SQLite)")
    sub = parser.add_subparsers(dest="cmd")

    # migrate
    sub.add_parser("migrate", help="Import tickets.jsonl → tickets.db")

    # search
    p_search = sub.add_parser("search", help="BM25 full-text search")
    p_search.add_argument("query", nargs="+")
    p_search.add_argument("--limit", type=int, default=10)
    p_search.add_argument("--status", default=None)

    # query
    p_query = sub.add_parser("query", help="Filter tickets")
    p_query.add_argument("--agent")
    p_query.add_argument("--status")
    p_query.add_argument("--priority")
    p_query.add_argument("--overdue", action="store_true")

    # stats
    sub.add_parser("stats", help="Count tickets by status/priority/agent")

    # create
    p_create = sub.add_parser("create", help="Create a ticket")
    p_create.add_argument("--agent", required=True)
    p_create.add_argument("--title", required=True)
    p_create.add_argument("--priority", default="P2", choices=["P0","P1","P2","P3"])
    p_create.add_argument("--type", default="operational",
                          choices=["operational","improvement","bug"])
    p_create.add_argument("--weakness", default=None)

    # update
    p_update = sub.add_parser("update", help="Update a ticket")
    p_update.add_argument("id")
    p_update.add_argument("--status")
    p_update.add_argument("--note")
    p_update.add_argument("--evidence")

    # export
    p_export = sub.add_parser("export", help="Export tickets.db → tickets.jsonl")
    p_export.add_argument("--output", default=None)

    args = parser.parse_args()

    if args.cmd == "migrate":
        conn = get_conn()
        init_schema(conn)
        migrate(conn)
        conn.close()
    elif args.cmd == "search":
        cmd_search(args)
    elif args.cmd == "query":
        cmd_query(args)
    elif args.cmd == "stats":
        cmd_stats(args)
    elif args.cmd == "create":
        cmd_create(args)
    elif args.cmd == "update":
        cmd_update(args)
    elif args.cmd == "export":
        cmd_export(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
