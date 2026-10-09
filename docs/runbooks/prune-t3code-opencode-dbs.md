---
type: Runbook
title: Audit and reclaim T3 Code and OpenCode database space
description: Inspect SQLite usage and preserve conversation history before choosing a cleanup operation.
when: Read when ~/.t3/userdata or ~/.local/share/opencode grows, or SQLite lock errors appear under concurrent access.
resource: modules/scripts/audit-agent-dbs.py
tags: [runbook, maintenance, t3code, opencode, sqlite]
---

# Audit and reclaim T3 Code and OpenCode database space

Audit the installed schema and database ownership before choosing what to remove.
A filename, an old modification time, or an archived session does not prove that
its history is disposable. Preserve active sessions and history that has not
been reviewed.

## 1. Identify the databases and their owners

Run these commands from the repository with Python 3, SQLite, and `fuser`
available. If needed, enter a shell using the repository's pinned inputs:

```sh
nix shell --inputs-from . nixpkgs#python3 nixpkgs#sqlite nixpkgs#psmisc
python3 modules/scripts/audit-agent-dbs.py
fuser -v -- "$HOME/.t3/userdata/state.sqlite" \
  "$HOME/.t3/userdata/state.sqlite-wal" \
  "$HOME/.local/share/opencode/opencode.db" \
  "$HOME/.local/share/opencode/opencode.db-wal" \
  "$HOME/.local/share/opencode/opencode-stable.db"
```

The audit opens existing files in SQLite read-only mode, reads a consistent
transaction per database, and prints counts rather than titles or conversation
bodies. Each database has a 30-second SQL work limit. Missing files remain
missing. An unfamiliar schema or interrupted query produces a nonzero exit
status; investigate before using partial results. SQLite may create its normal
WAL coordination files for read-only connections. Do not use `immutable=1` on a
live database, because that can ignore current WAL contents.

Check other users' processes if `fuser` reports insufficient permissions. No
visible file owner is not proof that a database is obsolete.

On Alpha on 2026-10-08, OpenCode 1.18.34 held `opencode.db` open. The older
`opencode-stable.db` held separate history. Keep both until the archived history
has been exported or reviewed. Inspect actual schemas before writing queries:

```sh
sqlite3 -readonly "$HOME/.t3/userdata/state.sqlite" '.schema'
sqlite3 -readonly "$HOME/.local/share/opencode/opencode.db" '.schema'
sqlite3 -readonly "$HOME/.local/share/opencode/opencode-stable.db" '.schema'
```

## 2. Review candidates without deleting rows

The audit reports old and empty sessions as review candidates. Neither category
means that deletion is safe. Check the application's session list for ongoing
work, child sessions, and useful history. T3 can still refer to provider sessions
in either OpenCode database through `projection_thread_sessions.provider_session_id`.

Use read-only ID comparisons to check whether the older database contains
sessions missing from the live database:

```sh
sqlite3 -readonly "$HOME/.local/share/opencode/opencode.db" <<'SQL'
PRAGMA query_only = ON;
ATTACH DATABASE 'file:/home/repparw/.local/share/opencode/opencode-stable.db?mode=ro' AS old;
SELECT count(*) AS sessions_missing_from_live
FROM old.session s
WHERE NOT EXISTS (SELECT 1 FROM main.session n WHERE n.id = s.id);
SQL
```

Adjust the absolute archive path for another user. Matching session IDs alone
do not prove that every message or part matches. Compare those records too
before treating a database as a duplicate.

For reviewed unwanted sessions, use the application's supported delete action.
Archiving a session preserves history and may reclaim no space. Check child
sessions and provider references before deleting a parent. Keep the old database
if the installed application cannot safely export or remove its sessions.

Do not delete `orchestration_events`, command receipts, or OpenCode `event` rows
with raw SQL based only on age. T3 0.0.44 reads orchestration events in migrations
and approval reconstruction. Rendered messages remaining in projection tables
does not establish that replay or recovery still works. A future event-retention
procedure needs version-specific upstream support and restore verification.

## 3. Back up before maintenance

Use SQLite's backup command to include committed WAL contents in a consistent
snapshot. A plain copy of a live database can omit recent changes. Keep backups
private because they contain conversation history and application credentials.
For example, back up T3 and verify the resulting database:

```sh
umask 077
backup_dir="$HOME/backups/agent-dbs-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
sqlite3 -readonly "$HOME/.t3/userdata/state.sqlite" \
  ".backup \"$backup_dir/state.sqlite\""
sqlite3 -readonly "$backup_dir/state.sqlite" 'PRAGMA quick_check;'
```

Expect `ok`. Repeat for each OpenCode database before modifying it. Check that
the backup has the same relevant session and message counts as the snapshot you
intend to preserve. Record its path and keep enough free disk space for both the
backup and any SQLite rebuild. Use the [service backup restore runbook](restore-service-backups.md)
when testing recovery. Do not remove the only backup because its filename ends
in `.bak`.

## 4. Reclaim pages only when the audit finds free pages

`reusable_bytes` reports SQLite pages already available for reuse inside the
file. Those pages are the initial estimate for space that a vacuum can reclaim.
If the count is zero, a large file alone does not justify a vacuum. A checkpoint
can still truncate a WAL after writers stop.

During maintenance downtime, stop the services and any standalone desktop or
CLI process that owns the same databases:

```sh
systemctl --user stop t3code-web.service opencode-web.service
```

Repeat the ownership check from step 1. Do not continue while another process
has a database or its WAL open. For each confirmed database, checkpoint first.
Run `VACUUM` only after a reviewed deletion or a nonzero free-page count:

```sh
sqlite3 "$HOME/.t3/userdata/state.sqlite" 'PRAGMA wal_checkpoint(TRUNCATE);'
# Optional, if there are free pages and enough temporary disk space:
sqlite3 "$HOME/.t3/userdata/state.sqlite" 'VACUUM; PRAGMA quick_check;'
```

Repeat only for the OpenCode database that needs maintenance. Do not unlink WAL
or SHM files by hand. SQLite manages those files.

## 5. Restart and check history

```sh
systemctl --user start opencode-web.service t3code-web.service
curl -fsS http://127.0.0.1:4096/ >/dev/null
curl -fsS http://127.0.0.1:3773/api/auth/session >/dev/null
python3 modules/scripts/audit-agent-dbs.py
```

Open several preserved sessions, including an older session and a recent one.
Confirm that messages load and that an intended resumable session can resume.
An HTTP response alone does not verify conversation history.

## Audit on 2026-10-08

The read-only Alpha audit found these values. Re-run the audit for current counts.

| Database | File size | Sessions or threads | Messages | Free pages |
| --- | ---: | ---: | ---: | ---: |
| T3 `state.sqlite` | 3.95 GiB | 589 | 32,432 | 0 |
| Live `opencode.db` | 2.22 GiB | 260 | 11,513 | 0 |
| Older `opencode-stable.db` | 2.70 GiB | 1,501 | 70,274 | 0 |

All 1,501 older OpenCode sessions, 70,274 messages, and 275,565 parts had IDs
absent from the live database. Two older session IDs remained referenced by T3.
The live OpenCode database had no empty sessions. The older database had three
empty sessions without children or T3 references; those remain unreviewed
candidates. T3 had ten threads without messages, which also require review of
their other state. No database or conversation rows were deleted. No vacuum
was warranted by the free-page counts.
