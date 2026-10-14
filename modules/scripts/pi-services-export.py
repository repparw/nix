"""Publish a private Pi services copy with transaction-consistent SQLite files."""

import json
from contextlib import closing
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile


EXCLUDED = {"dns/listener.conf", "dns/resolved.conf"}


def secure_open(path, flags):
    """Pin each directory and reject links replaced after path validation."""
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
            raise ValueError(f"backup file type changed: {path.name}")
        return opened
    finally:
        os.close(descriptor)


def is_sqlite(path):
    with os.fdopen(secure_open(path, os.O_RDONLY), "rb") as stream:
        return stream.read(16) == b"SQLite format 3\x00"


def snapshot_database(source, destination):
    parent = secure_open(source.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        escaped_destination = str(destination).replace("'", "''")
        # A pinned directory plus SQLite's NOFOLLOW flag prevents the database
        # being swapped for a privileged external symlink between checks.
        subprocess.run(['sqlite3', '-readonly', '-nofollow', '-noinit', '-batch',
                        '-cmd', '.timeout 10000', f'./{source.name}',
                        f"VACUUM INTO '{escaped_destination}';"],
                       cwd=f'/proc/self/fd/{parent}', pass_fds=(parent,),
                       check=True, timeout=120)
    finally:
        os.close(parent)
    with closing(sqlite3.connect(destination.as_uri() + '?mode=ro', uri=True)) as snapshot:
        if snapshot.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise ValueError(f"SQLite snapshot failed validation: {source.name}")


def prepare(source, state, uid, gid):
    source = source.resolve(strict=True)
    # An empty or accidentally moved live tree must not erase Alpha's backup.
    if not (source / "hass/home-assistant_v2.db").is_file():
        raise ValueError("required Home Assistant database is missing")
    state.mkdir(mode=0o711, parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix="snapshot-", dir=state))
    pending = state / f".current-{temporary.name}"
    databases = []
    files = 0

    def copy(path, relative, ancestors):
        nonlocal files
        if relative.as_posix() in EXCLUDED:
            return
        resolved = path.resolve(strict=True)
        if not (resolved.is_relative_to(source) or resolved.is_relative_to("/nix/store")
                or relative.as_posix() == "dns/hosts" and resolved == Path("/etc/hosts")):
            raise ValueError(f"backup link escapes permitted source: {relative}")
        attributes = resolved.stat()
        output = temporary / relative
        if stat.S_ISDIR(attributes.st_mode):
            if resolved in ancestors:
                raise ValueError(f"backup directory link cycle: {relative}")
            output.mkdir(mode=0o700)
            descriptor = secure_open(resolved, os.O_RDONLY | os.O_DIRECTORY)
            try:
                for name in sorted(os.listdir(descriptor)):
                    copy(resolved / name, relative / name, ancestors | {resolved})
            finally:
                os.close(descriptor)
        elif stat.S_ISREG(attributes.st_mode):
            for suffix in ("-wal", "-shm", "-journal"):
                if path.name.endswith(suffix):
                    base = path.with_name(path.name.removesuffix(suffix))
                    if base.is_file() and is_sqlite(base):
                        return
            if is_sqlite(resolved):
                snapshot_database(resolved, output)
                databases.append(relative.as_posix())
            else:
                with os.fdopen(secure_open(resolved, os.O_RDONLY), 'rb') as reader:
                    with output.open('wb') as writer:
                        shutil.copyfileobj(reader, writer)
            os.chmod(output, 0o600 | (attributes.st_mode & 0o100))
            files += 1
        else:
            raise ValueError(f"unsupported backup file: {relative}")

    try:
        for child in sorted(source.iterdir()):
            copy(child, Path(child.name), {source})
        manifest = temporary / ".pi-services-export.json"
        manifest.write_text(json.dumps(dict(sqlite=databases, excluded=sorted(EXCLUDED))) + "\n")
        os.chmod(manifest, 0o600)
        # Keep staging root-owned until all privileged reads have completed.
        for directory, directories, names in os.walk(temporary):
            for name in directories + names:
                os.chown(Path(directory) / name, uid, gid)
        os.chown(temporary, uid, gid)
        current = state / "current"
        previous = current.resolve() if current.is_symlink() else None
        pending.symlink_to(temporary.name)
        os.replace(pending, current)
    except BaseException:
        pending.unlink(missing_ok=True)
        shutil.rmtree(temporary)
        raise
    if previous is not None and previous.parent == state and previous.name.startswith("snapshot-"):
        shutil.rmtree(previous)
    print(f"prepared {files} files and {len(databases)} SQLite snapshots", file=sys.stderr)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
