#!/usr/bin/env python3
"""Private online backup. Each SQLite database is consistent independently."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import time


def backup(source, destination):
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if destination == source or source in destination.parents:
        raise ValueError("Backup destination must be outside the source tree")
    os.umask(0o077)
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    databases = []
    skipped = []
    for directory, dirs, files in os.walk(source, followlinks=False):
        relative = Path(directory).relative_to(source)
        target = destination / relative
        target.mkdir(mode=0o700, parents=True, exist_ok=True)
        for name in list(dirs):
            path = Path(directory) / name
            if path.is_symlink():
                (target / name).symlink_to(os.readlink(path))
                dirs.remove(name)
        for name in files:
            path = Path(directory) / name
            output = target / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                output.symlink_to(os.readlink(path))
                continue
            if not stat.S_ISREG(mode):
                skipped.append(str(path.relative_to(source)))
                continue
            with path.open("rb") as handle:
                is_database = handle.read(16) == b"SQLite format 3\x00"
            if is_database:
                deadline = time.monotonic() + 60

                def progress(_status, _remaining, _total):
                    if time.monotonic() > deadline:
                        raise TimeoutError("SQLite backup exceeded 60 seconds")

                with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as reader:
                    with closing(sqlite3.connect(output)) as writer:
                        reader.backup(writer, pages=256, progress=progress)
                        writer.execute("PRAGMA journal_mode=DELETE")
                        if writer.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                            raise RuntimeError("Backup failed SQLite integrity check")
                databases.append(str(path.relative_to(source)))
            else:
                # SQLite sidecars must never be replayed onto the backed-up DB.
                if any(name.endswith(suffix) and (path.parent / name[:-len(suffix)]).is_file()
                       for suffix in ("-wal", "-shm", "-journal")):
                    continue
                shutil.copyfile(path, output)
            output.chmod(0o600)
    (destination / "backup-manifest.json").write_text(json.dumps({
        "source": str(source), "sqlite_integrity": "ok", "databases": databases,
        "skipped_special_files": skipped,
        "consistency": "online, per database; ordinary files can change during copy",
    }, indent=2) + "\n")
    print(json.dumps({"backup": str(destination), "sqlite_databases": len(databases),
                      "integrity": "ok", "skipped_special_files": len(skipped)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    backup(args.source, args.destination)
