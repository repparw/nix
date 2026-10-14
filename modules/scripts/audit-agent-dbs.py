#!/usr/bin/env python3
"""Read bounded SQLite metadata summaries without exposing conversation bodies."""

import argparse
from contextlib import closing
import json
import math
import sqlite3
import time
from pathlib import Path


def audit(path, timeout):
    result = {"path": str(path)}
    if not path.is_file():
        return {**result, "status": "missing"}
    result["file_bytes"] = path.stat().st_size
    result["sidecar_bytes"] = {
        suffix: Path(str(path) + suffix).stat().st_size
        for suffix in ("-wal", "-shm")
        if Path(str(path) + suffix).is_file()
    }
    deadline = time.monotonic() + timeout
    try:
        with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)) as db:
            db.execute("PRAGMA query_only = ON")
            db.execute("PRAGMA busy_timeout = 1000")
            db.set_progress_handler(lambda: time.monotonic() > deadline, 10000)
            db.execute("BEGIN")
            tables = {
                row[0]
                for row in db.execute("SELECT name FROM sqlite_schema WHERE type = 'table'")
            }
            result["tables"] = sorted(tables)
            result["page_bytes"] = db.execute("PRAGMA page_size").fetchone()[0]
            result["free_pages"] = db.execute("PRAGMA freelist_count").fetchone()[0]
            result["reusable_bytes"] = result["page_bytes"] * result["free_pages"]
            summaries = {}
            if {"session", "message", "part"} <= tables:
                summaries["sessions"] = dict(
                    zip(
                        ("total", "archived", "updated_before_30_days", "oldest", "newest"),
                        db.execute("""
                            SELECT count(*), sum(time_archived IS NOT NULL),
                              sum(time_updated < (strftime('%s','now','-30 days') * 1000)),
                              datetime(min(time_updated)/1000, 'unixepoch'),
                              datetime(max(time_updated)/1000, 'unixepoch') FROM session
                        """).fetchone(),
                    )
                )
                summaries["sessions_without_messages"] = db.execute("""
                    SELECT count(*) FROM session s
                    WHERE NOT EXISTS (SELECT 1 FROM message m WHERE m.session_id = s.id)
                """).fetchone()[0]
                for table in ("message", "part", "event"):
                    if table in tables:
                        summaries[table + "_rows"] = db.execute(
                            f'SELECT count(*) FROM "{table}"'
                        ).fetchone()[0]
            if {"projection_threads", "projection_thread_messages"} <= tables:
                summaries["threads"] = dict(
                    zip(
                        ("total", "archived", "deleted", "updated_before_30_days", "oldest", "newest"),
                        db.execute("""
                            SELECT count(*), sum(archived_at IS NOT NULL),
                              sum(deleted_at IS NOT NULL),
                              sum(julianday(updated_at) < julianday('now','-30 days')),
                              min(updated_at), max(updated_at) FROM projection_threads
                        """).fetchone(),
                    )
                )
                summaries["threads_without_messages"] = db.execute("""
                    SELECT count(*) FROM projection_threads t
                    WHERE NOT EXISTS (
                      SELECT 1 FROM projection_thread_messages m WHERE m.thread_id = t.thread_id
                    )
                """).fetchone()[0]
                summaries["message_rows"] = db.execute(
                    "SELECT count(*) FROM projection_thread_messages"
                ).fetchone()[0]
                if "orchestration_events" in tables:
                    summaries["event_rows"] = db.execute(
                        "SELECT count(*) FROM orchestration_events"
                    ).fetchone()[0]
            result["summary"] = summaries
            result["status"] = "ok" if summaries else "unrecognized schema"
    except sqlite3.Error as error:
        result["status"] = "incomplete"
        result["error"] = str(error)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--timeout", type=float, default=30, help="SQLite work limit per file in seconds")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be positive")
    paths = args.paths or [
        Path.home() / ".t3/userdata/state.sqlite",
        Path.home() / ".local/share/opencode/opencode.db",
        Path.home() / ".local/share/opencode/opencode-stable.db",
    ]
    results = [audit(path.expanduser(), args.timeout) for path in paths]
    print(json.dumps(results, indent=2))
    return int(any(result["status"] not in ("ok", "missing") for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
