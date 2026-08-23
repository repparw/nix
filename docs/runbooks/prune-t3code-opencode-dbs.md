---
type: Runbook
title: Prune t3code and opencode Databases
description: Reclaim space from the t3code state DB and opencode session DB without losing chat history.
when: Read when ~/.t3/userdata or ~/.local/share/opencode grows to multiple GB, or SQLite lock errors appear under concurrent access.
resource: modules/aspects/ai/t3code.nix
tags: [runbook, maintenance, t3code, opencode, sqlite]
---

# Prune t3code and opencode Databases

t3code (`modules/aspects/ai/t3code.nix`) and the shared opencode server both
store data in SQLite files that grow without bound. Neither application has a
time-based retention mechanism as of t3code 0.0.33 / opencode 1.18.18. The
bloat is almost entirely internal event-sourcing duplicates; actual chat
history is small by comparison.

## Data layout

| Path | Contents | History? |
| --- | --- | --- |
| `~/.t3/userdata/state.sqlite` | `orchestration_events` (append-only event store), projections, receipts | Conversations live in `projection_thread_messages` (~30 MB); events are replays |
| `~/.local/share/opencode/opencode-stable.db` | `event` table (streaming-update replays), plus `session`/`message`/`part` | Chat history is `message` + `part`; `event` rows are duplicates |
| `~/.t3/userdata/logs/provider/` | Per-thread provider logs named `events.<thread-uuid>.log` | No |
| `~/.t3/userdata/server-runtime.json` | Lease file proving which process owns port 3773 | No |

What t3code cleans up on its own: deleting a thread cascades to projection
tables and attachments, and the `ProviderSessionReaper` evicts live in-memory
sessions idle for 30 minutes. What it never cleans up: `orchestration_events`,
`orchestration_command_receipts`, provider logs, and opencode's `event` table.

## Known upstream issue

Running the desktop app while `t3code-web.service` owns the state directory
spawns a second embedded backend against the same SQLite file and causes
`database is locked` errors. Track pingdotgg/t3code issues #6097 (no desktop
attach-to-server mode exists; verified in 0.0.33) and PR #6098 (startup
preflight). Until resolved, use the web UI at `http://127.0.0.1:3773` instead
of the desktop app, or launch the desktop with a separate `T3CODE_HOME`.

## Procedure

### 1. Stop the services

```console
$ systemctl --user stop t3code-web.service opencode-web.service
```

Writes must be quiesced before deleting rows or vacuuming.

### 2. Delete dead weight (no history impact)

```console
$ rm -f ~/.t3/userdata/state.sqlite.bak ~/.local/share/opencode/opencode.db
$ find ~/.t3/userdata/logs -type f -mtime +7 -delete
```

`opencode.db` is the abandoned pre-"stable" database; confirm it has not been
modified recently (`ls -la`) before deleting.

### 3. Prune old event-store rows (keeps all chat text)

Keep a 30-day window of replay events; rendered threads stay complete because
they read from projections/message tables:

```console
$ sqlite3 ~/.t3/userdata/state.sqlite \
    "DELETE FROM orchestration_events WHERE occurred_at < datetime('now','-30 days');"
```

```console
$ sqlite3 ~/.local/share/opencode/opencode-stable.db \
    "DELETE FROM event
     WHERE type IN ('message.part.updated.1','message.updated.1')
       AND json_extract(data,'$.sessionID') IN (
         SELECT id FROM session
         WHERE time_updated < (strftime('%s','now','-30 days') * 1000));"
```

Optional, if the activity feed in old threads matters less than space:

```console
$ sqlite3 ~/.t3/userdata/state.sqlite \
    "DELETE FROM projection_thread_activities WHERE created_at < datetime('now','-90 days');"
```

Check the column list with `.schema` first; schema names have changed between
versions.

### 4. Vacuum and checkpoint

Both operations take about a minute per GB:

```console
$ sqlite3 ~/.t3/userdata/state.sqlite "VACUUM; PRAGMA wal_checkpoint(TRUNCATE);"
$ sqlite3 ~/.local/share/opencode/opencode-stable.db "VACUUM; PRAGMA wal_checkpoint(TRUNCATE);"
```

### 5. Restart and verify

```console
$ systemctl --user start opencode-web.service t3code-web.service
$ curl -sf http://127.0.0.1:4096/ >/dev/null && echo opencode ok
$ curl -sf http://127.0.0.1:3773/api/auth/session >/dev/null && echo t3 ok
```

Then spot-check that recent thread titles still resolve:

```console
$ sqlite3 -readonly ~/.t3/userdata/state.sqlite \
    "SELECT substr(title,1,60) FROM projection_threads ORDER BY rowid DESC LIMIT 5;"
```

## Results from August 2026

Deleted 420k orchestration events and 37k opencode replay events plus backups
and stale logs. `state.sqlite` went 3.4 GB → 2.3 GB, `opencode-stable.db`
3.65 GB → 2.58 GB, and `~/.t3/userdata/logs` 723 MB → ~30 MB. Expect regrowth
on the same order within weeks of heavy agent use; re-run as needed.
