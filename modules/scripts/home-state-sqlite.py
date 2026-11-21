"""Build and retry self-contained SQLite snapshots in Alpha home-state exports.

Raw rsync copies of WAL databases are not restore-safe. Each detected database
must be replaced with a validated online snapshot, or a previously verified
snapshot with its original verification time and degraded status. Never ship a
raw copy after a snapshot failure. Publishing is an atomic directory exchange.
"""

import ctypes
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time

MAGIC = b"SQLite format 3\0"
SIDECARS = ("-wal", "-shm", "-journal")
STATUS = ".export-status.json"
RETRY = ".sqlite-retry-needed"


def secure_open(path, flags):
    """Open a regular file/directory without following symlinks in its path."""
    path = path.absolute()
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:-1]:
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        opened = os.open(path.name, flags | os.O_NOFOLLOW | os.O_NONBLOCK,
                         dir_fd=descriptor)
        mode = os.fstat(opened).st_mode
        expected = stat.S_ISDIR if flags & os.O_DIRECTORY else stat.S_ISREG
        if not expected(mode):
            os.close(opened)
            raise ValueError(f"backup path has unsupported file type: {path}")
        return opened
    finally:
        os.close(descriptor)


def is_sqlite(path):
    with os.fdopen(secure_open(path, os.O_RDONLY), "rb") as source:
        return source.read(16) == MAGIC


def verify_snapshot(path):
    if any(Path(str(path) + suffix).exists() for suffix in SIDECARS):
        raise ValueError(f"old SQLite snapshot has journal sidecars: {path}")
    # The private stage is root-owned. Refuse symlinked snapshot paths.
    if not is_sqlite(path):
        raise ValueError(f"not a SQLite snapshot: {path}")
    with sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True) as db:
        if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise ValueError(f"SQLite snapshot failed validation: {path}")


def sidecars_remove(path):
    for suffix in SIDECARS:
        (path.parent / (path.name + suffix)).unlink(missing_ok=True)


def snapshot_database(source, staged):
    """VACUUM INTO includes committed WAL changes without stopping the writer."""
    source_fd = secure_open(source, os.O_RDONLY)
    try:
        if os.read(source_fd, 16) != MAGIC:
            raise ValueError(f"SQLite source changed during backup: {source}")
        source_stat = os.fstat(source_fd)
    finally:
        os.close(source_fd)
    secure_parent = secure_open(staged.parent, os.O_RDONLY | os.O_DIRECTORY)
    os.close(secure_parent)
    original = staged.stat(follow_symlinks=False) if staged.exists() else source_stat
    descriptor, filename = tempfile.mkstemp(prefix=f".{staged.name}.snapshot-", dir=staged.parent)
    os.close(descriptor)
    temporary = Path(filename)
    try:
        parent = secure_open(source.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            escaped_destination = str(temporary).replace("'", "''")
            subprocess.run(
                ["sqlite3", "-readonly", "-nofollow", "-noinit", "-batch", "-cmd",
                 ".timeout 10000", f"./{source.name}", f"VACUUM INTO '{escaped_destination}';"],
                cwd=f"/proc/self/fd/{parent}", pass_fds=(parent,), check=True, timeout=120,
            )
        finally:
            os.close(parent)
        verify_snapshot(temporary)
        os.chown(temporary, original.st_uid, original.st_gid)
        if staged.exists():
            shutil.copystat(staged, temporary, follow_symlinks=False)
        else:
            os.chmod(temporary, stat.S_IMODE(source_stat.st_mode))
        os.replace(temporary, staged)
        sidecars_remove(staged)
    finally:
        temporary.unlink(missing_ok=True)


def load_previous(previous):
    if previous is None or not (previous / STATUS).is_file():
        return {}
    data = json.loads((previous / STATUS).read_text())
    if data.get("schemaVersion") != 1:
        raise ValueError("unsupported prior SQLite status schema")
    return data["databases"]


def previous_timestamp(previous, relative, entries):
    old = entries.get(str(relative))
    if old:
        return old.get("verifiedAt")
    marker = previous / ".export-complete"
    return int(marker.stat().st_mtime) if marker.is_file() else None


def preserve_old(previous, relative, staged, entries):
    if previous is None:
        return None
    old = previous / relative
    try:
        verify_snapshot(old)
        timestamp = previous_timestamp(previous, relative, entries)
        if timestamp is None:
            return None  # Cannot truthfully report the age of this recovery point.
        staged.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old, staged, follow_symlinks=False)
        sidecars_remove(staged)
        return timestamp
    except (OSError, sqlite3.DatabaseError, ValueError):
        return None


def publish_status(stage, entries, retry=False):
    failures = [dict(path=name, **entry) for name, entry in sorted(entries.items())
                if entry["status"] != "fresh"]
    # A targeted retry does not refresh non-SQLite files or validate critical
    # state against all sources. Only a subsequent full export may say complete.
    pending_full_export = retry and not failures
    status = "degraded" if failures or pending_full_export else "complete"
    report = {
        "schemaVersion": 1,
        "status": status,
        "generatedAt": int(time.time()),
        "databases": entries,
        "failures": failures,
        "recoveryPending": pending_full_export,
    }
    (stage / STATUS).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    if failures:
        (stage / RETRY).touch()
    else:
        (stage / RETRY).unlink(missing_ok=True)
    if failures or pending_full_export:
        (stage / ".export-complete").unlink(missing_ok=True)
    print(f"home-state: {len(entries) - len(failures)} SQLite snapshots fresh, "
          f"{len(failures)} degraded", file=sys.stderr)


def prepare(home, stage, previous=None, retry=False):
    old_entries = load_previous(stage if retry else previous)
    if retry:
        entries = dict(old_entries)
        paths = [Path(name) for name, entry in old_entries.items()
                 if entry["status"] != "fresh"]
    else:
        entries = {}
        paths = []
        for directory, _, files in os.walk(stage, followlinks=False):
            for filename in files:
                staged = Path(directory) / filename
                if not stat.S_ISREG(staged.lstat().st_mode):
                    continue
                if is_sqlite(staged):
                    paths.append(staged.relative_to(stage))
        # Previously tracked databases must not silently disappear if rsync
        # skips a source, or its header changes. Preserve the last verified
        # snapshot, and keep the export degraded until fresh again.
        known = set(paths)
        for name in old_entries:
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError(f"unsafe previous SQLite path: {name}")
            if relative not in known:
                paths.append(relative)
                known.add(relative)
    for relative in sorted(paths):
        source = home / relative
        staged = stage / relative
        try:
            snapshot_database(source, staged)
            entries[str(relative)] = {"status": "fresh", "verifiedAt": int(time.time())}
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired,
                sqlite3.DatabaseError, ValueError) as error:
            reason = str(error)[-240:]
            if retry:
                old = old_entries[str(relative)]
                timestamp = old.get("verifiedAt") if old["status"] == "stale" else None
            else:
                timestamp = preserve_old(previous, relative, staged, old_entries)
            if timestamp is None:
                staged.unlink(missing_ok=True)
                kind = "missing"
            else:
                kind = "stale"
            sidecars_remove(staged)
            entries[str(relative)] = {"status": kind, "verifiedAt": timestamp, "error": reason}
            print(f"home-state: SQLite {kind}: {relative}: {reason}", file=sys.stderr)
    publish_status(stage, entries, retry=retry)


def publish(stage, destination):
    """Atomically replace a populated published directory with a staged one."""
    if not destination.exists():
        os.replace(stage, destination)
        return
    libc = ctypes.CDLL(None, use_errno=True)
    fn = libc.renameat2
    fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p,
                   ctypes.c_uint]
    fn.restype = ctypes.c_int
    if fn(-100, os.fsencode(stage), -100, os.fsencode(destination), 2) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(destination))


if __name__ == "__main__":
    if sys.argv[1] == "--publish":
        publish(Path(sys.argv[2]), Path(sys.argv[3]))
    elif sys.argv[1] == "--retry":
        prepare(Path(sys.argv[2]), Path(sys.argv[3]), retry=True)
    else:
        prepare(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
