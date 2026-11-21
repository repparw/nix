"""Build self-contained SQLite snapshots in Alpha home-state exports.

Ordinary selected home files are listed for Restic to read directly.
Only SQLite databases get validated online snapshots or last verified copies.
Publishing those small snapshots and the direct-file list is atomic.
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
SQLITE_EXTENSIONS = {".db", ".sqlite", ".sqlite3"}
SIDECARS = ("-wal", "-shm", "-journal")
STATUS = ".export-status.json"


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


def publish_status(stage, entries):
    failures = [dict(path=name, **entry) for name, entry in sorted(entries.items())
                if entry["status"] != "fresh"]
    status = "degraded" if failures else "complete"
    report = {
        "schemaVersion": 1,
        "status": status,
        "generatedAt": int(time.time()),
        "databases": entries,
        "failures": failures,
    }
    (stage / STATUS).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    marker = stage / ".export-complete"
    if failures:
        marker.unlink(missing_ok=True)
    else:
        marker.write_text(str(int(time.time())) + "\n")
    print(f"home-state: {len(entries) - len(failures)} SQLite snapshots fresh, "
          f"{len(failures)} degraded", file=sys.stderr)


def still_selected(relative, selected):
    """Retain old database tracking only for paths still in backup scope."""
    if selected is None:
        return True
    name = relative.as_posix()
    return any(
        name == item.rstrip("/") or (item.endswith("/") and name.startswith(item))
        for item in selected
    )


def selected_files(home, selected, excludes):
    """Enumerate curated files without copying them or following symlinks."""
    prefixes = [path.strip("/") for path in excludes]

    def excluded(relative):
        name = relative.as_posix()
        return any(name == prefix or name.startswith(prefix + "/")
                   for prefix in prefixes)

    result = set()
    for item in selected:
        relative = Path(item)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe selected home path: {item}")
        source = home / relative
        if excluded(relative):
            continue
        if source.is_symlink() or source.is_file():
            result.add(relative)
        elif source.is_dir():
            for directory, dirs, files in os.walk(source, followlinks=False):
                parent = Path(directory).relative_to(home)
                keep = []
                for name in dirs:
                    child = parent / name
                    if excluded(child):
                        continue
                    if (home / child).is_symlink():
                        result.add(child)
                    else:
                        keep.append(name)
                dirs[:] = keep
                for name in files:
                    child = parent / name
                    if not excluded(child):
                        result.add(child)
    return result


def prepare(home, stage, previous=None, selected=None, excludes=None):
    """Only SQLite needs a copy. Restic reads ordinary files in place."""
    if selected is None:
        raise ValueError("curated home paths are required")
    candidates = selected_files(home, selected, excludes or [])
    old_entries = load_previous(previous)
    known = set()
    for name in old_entries:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe previous SQLite path: {name}")
        if still_selected(relative, selected):
            known.add(relative)

    databases = set()
    for relative in candidates:
        source = home / relative
        if relative in known:
            databases.add(relative)
        elif (not source.is_symlink() and source.is_file()
              and (relative.suffix.lower() in SQLITE_EXTENSIONS or is_sqlite(source))):
            # Extensions catch damaged headers; magic finds extensionless databases.
            databases.add(relative)

    # Retire deleted databases discovered under selected directories.
    # Keep explicitly selected databases expected until removed from configuration.
    exact_paths = {Path(item) for item in selected if not item.endswith("/")}
    databases.update(known & exact_paths)

    # Exclude orphaned WAL files even when their database has been retired.
    sidecars = {Path(str(relative) + suffix)
                for relative in databases | known for suffix in SIDECARS}
    ordinary = sorted(candidates - databases - sidecars)
    # NUL delimiters and --files-from-raw preserve spaces, glob characters,
    # and even newlines in paths. No copies of these files are staged.
    (stage / ".home-files").write_bytes(
        b"".join(os.fsencode(home / relative) + b"\0" for relative in ordinary)
    )

    entries = {}
    for relative in sorted(databases):
        source = home / relative
        staged = stage / relative
        staged.parent.mkdir(parents=True, exist_ok=True)
        try:
            snapshot_database(source, staged)
            entries[str(relative)] = {"status": "fresh", "verifiedAt": int(time.time())}
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired,
                sqlite3.DatabaseError, ValueError) as error:
            reason = str(error)[-240:]
            timestamp = preserve_old(previous, relative, staged, old_entries)
            if timestamp is None:
                staged.unlink(missing_ok=True)
                kind = "missing"
            else:
                kind = "stale"
            sidecars_remove(staged)
            entries[str(relative)] = {"status": kind, "verifiedAt": timestamp, "error": reason}
            print(f"home-state: SQLite {kind}: {relative}: {reason}", file=sys.stderr)
    publish_status(stage, entries)


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
    else:
        selected = json.loads(sys.argv[4]) if len(sys.argv) > 4 else None
        excludes = json.loads(sys.argv[5]) if len(sys.argv) > 5 else []
        prepare(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
                selected=selected, excludes=excludes)
