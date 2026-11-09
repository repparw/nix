"""Replace raw SQLite files in an rsync home-state stage with consistent snapshots.

Scan by SQLite magic rather than extension: Chromium, Codex and OpenCode use
both conventional .db/.sqlite names and names such as "Web Data". The live
source must be read with SQLite, since an rsync copy of a WAL database can be
missing committed transactions or contain mismatched sidecars.
"""

import os
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile

MAGIC = b"SQLite format 3\0"
SIDECARS = ("-wal", "-shm", "-journal")


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


def snapshot_database(source, staged):
    """Use SQLite's online VACUUM INTO to include committed WAL transactions."""
    original = staged.stat(follow_symlinks=False)
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
        with sqlite3.connect(temporary.as_uri() + "?mode=ro", uri=True) as snapshot:
            if snapshot.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                raise ValueError(f"SQLite snapshot failed validation: {source}")
        # Retain the metadata captured by rsync for restores.
        os.chown(temporary, original.st_uid, original.st_gid)
        shutil.copystat(staged, temporary, follow_symlinks=False)
        os.replace(temporary, staged)
        # The new database is self-contained. Old WAL/SHM/journal sidecars
        # copied by rsync must not be restored alongside it.
        for suffix in SIDECARS:
            (staged.parent / (staged.name + suffix)).unlink(missing_ok=True)
    finally:
        temporary.unlink(missing_ok=True)


def prepare(home, stage):
    databases = []
    # os.walk does not follow directory symlinks. Ignore file symlinks too;
    # rsync preserves them and they are not databases copied by this backup.
    for directory, _, files in os.walk(stage, followlinks=False):
        for filename in files:
            staged = Path(directory) / filename
            if not stat.S_ISREG(staged.lstat().st_mode):
                continue
            if is_sqlite(staged):
                databases.append(staged.relative_to(stage))
    for relative in sorted(databases):
        source = home / relative
        # This fails the export instead of publishing an old raw copy if a
        # live source vanished, changed type, or cannot be snapshotted.
        if not is_sqlite(source):
            raise ValueError(f"SQLite source changed during backup: {source}")
        snapshot_database(source, stage / relative)
    print(f"home-state: snapshotted {len(databases)} SQLite databases", file=sys.stderr)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]), Path(sys.argv[2]))
