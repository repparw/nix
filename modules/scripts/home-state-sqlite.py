"""Build self-contained SQLite snapshots in Alpha home-state exports.

Ordinary selected home roots are listed for Restic to read directly, with
detected SQLite databases, their journal sidecars, and configured excludes
written to a Restic exclude file. Only SQLite databases get validated online
snapshots or last verified copies. Publishing those small snapshots and the
direct-file lists is atomic.
"""

import argparse
from contextlib import closing
import ctypes
import errno
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
KNOWN_FILE = "known-databases.json"


def secure_open_under(root, relative, flags):
    """Open relative path under root without following symlinks inside root."""
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError(f"unsafe relative backup path: {relative}")
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in relative.parts[:-1]:
            child = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        opened = os.open(relative.parts[-1], flags | os.O_NOFOLLOW | os.O_NONBLOCK,
                         dir_fd=descriptor)
        mode = os.fstat(opened).st_mode
        expected = stat.S_ISDIR if flags & os.O_DIRECTORY else stat.S_ISREG
        if not expected(mode):
            os.close(opened)
            raise ValueError(f"backup path has unsupported file type: {root / relative}")
        return opened
    finally:
        os.close(descriptor)


def is_sqlite(root, relative):
    with os.fdopen(secure_open_under(root, relative, os.O_RDONLY), "rb") as source:
        return source.read(16) == MAGIC


def verify_snapshot(root, relative):
    path = root / relative
    if any(Path(str(path) + suffix).exists() for suffix in SIDECARS):
        raise ValueError(f"old SQLite snapshot has journal sidecars: {path}")
    # The private stage is root-owned. Refuse symlinked snapshot paths.
    if not is_sqlite(root, relative):
        raise ValueError(f"not a SQLite snapshot: {path}")
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)) as db:
        if db.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            raise ValueError(f"SQLite snapshot failed validation: {path}")


def sidecars_remove(path):
    for suffix in SIDECARS:
        (path.parent / (path.name + suffix)).unlink(missing_ok=True)


def escape_restic_pattern(path_str):
    """Escape glob metacharacters for Restic --exclude-file."""
    if "\n" in path_str:
        raise ValueError(f"newline in excluded path is unsupported by --exclude-file: {path_str!r}")
    out = []
    for ch in path_str:
        if ch in "\\*?[]":
            out.append("\\")
        out.append(ch)
    return "".join(out)


def snapshot_database(home, stage, relative):
    """VACUUM INTO includes committed WAL changes without stopping the writer."""
    source_fd = secure_open_under(home, relative, os.O_RDONLY)
    try:
        if os.read(source_fd, 16) != MAGIC:
            raise ValueError(f"SQLite source changed during backup: {home / relative}")
        source_stat = os.fstat(source_fd)
    finally:
        os.close(source_fd)
    staged = stage / relative
    if relative.parent != Path("."):
        secure_parent = secure_open_under(stage, relative.parent, os.O_RDONLY | os.O_DIRECTORY)
        os.close(secure_parent)
    original = staged.stat(follow_symlinks=False) if staged.exists() else source_stat
    descriptor, filename = tempfile.mkstemp(prefix=f".{staged.name}.snapshot-", dir=staged.parent)
    os.close(descriptor)
    temporary = Path(filename)
    try:
        if relative.parent == Path("."):
            parent = os.open(home, os.O_RDONLY | os.O_DIRECTORY)
        else:
            parent = secure_open_under(home, relative.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            escaped_destination = str(temporary).replace("'", "''")
            subprocess.run(
                ["sqlite3", "-readonly", "-nofollow", "-noinit", "-batch", "-cmd",
                 ".timeout 10000", f"./{relative.name}", f"VACUUM INTO '{escaped_destination}';"],
                cwd=f"/proc/self/fd/{parent}", pass_fds=(parent,),
                capture_output=True, text=True, check=True, timeout=120,
            )
        finally:
            os.close(parent)
        verify_snapshot(stage, temporary.relative_to(stage))
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


def load_persistent_known(persistent_dir):
    if persistent_dir is None:
        return set()
    known_path = persistent_dir / KNOWN_FILE
    if not known_path.is_file():
        return set()
    data = json.loads(known_path.read_text())
    if data.get("schemaVersion") != 1 or not isinstance(data.get("databases"), list):
        raise ValueError("unsupported persistent known-databases schema")
    return set(data["databases"])


def save_persistent_known(persistent_dir, databases):
    """Persist known SQLite paths only when the set changes (zero daily SSD writes)."""
    if persistent_dir is None:
        return
    desired = sorted(p.as_posix() for p in databases)
    known_path = persistent_dir / KNOWN_FILE
    if known_path.is_file():
        try:
            existing = json.loads(known_path.read_text())
            if existing.get("schemaVersion") == 1 and existing.get("databases") == desired:
                return
        except (OSError, ValueError):
            pass
    persistent_dir.mkdir(parents=True, exist_ok=True)
    payload = json.dumps({"schemaVersion": 1, "databases": desired}, indent=2) + "\n"
    descriptor, filename = tempfile.mkstemp(prefix=".known-databases-", dir=persistent_dir)
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(payload)
        os.chmod(filename, 0o600)
        os.replace(filename, known_path)
    finally:
        Path(filename).unlink(missing_ok=True)


def validate_critical(home, critical_paths, persistent_dir):
    """Verify critical state files (e.g. OpenTofu) in place without staging copies."""
    for item in critical_paths:
        relative = Path(item)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe critical home path: {item}")
        source = home / relative
        marker = (persistent_dir / ".critical-seen" / item.replace("/", "__")
                  if persistent_dir is not None else None)
        if source.exists() or source.is_symlink():
            lock_path = source.parent / f".{source.name}.lock.info"
            if lock_path.exists():
                raise RuntimeError(
                    f"home-state: {lock_path} exists; OpenTofu holds the state lock, retry once it finishes"
                )
            fd = secure_open_under(home, relative, os.O_RDONLY)
            with os.fdopen(fd, "rb") as handle:
                raw = handle.read()
            if not raw:
                raise ValueError(f"home-state: critical file {source} is empty")
            data = json.loads(raw.decode("utf-8"))
            if (not isinstance(data, dict)
                    or isinstance(data.get("version"), bool)
                    or not isinstance(data.get("version"), (int, float))
                    or isinstance(data.get("serial"), bool)
                    or not isinstance(data.get("serial"), (int, float))
                    or not isinstance(data.get("resources"), list)):
                raise ValueError(f"home-state: {source} is not a parseable OpenTofu state")
            if marker is not None and not marker.exists():
                marker.parent.mkdir(parents=True, exist_ok=True)
                marker.write_text(str(int(time.time())) + "\n")
        elif marker is not None and marker.exists():
            raise RuntimeError(
                f"home-state: {source} was backed up before but is now missing; not publishing a generation without it"
            )


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
        verify_snapshot(previous, relative)
        timestamp = previous_timestamp(previous, relative, entries)
        if timestamp is None:
            return None  # Cannot truthfully report the age of this recovery point.
        staged.parent.mkdir(parents=True, exist_ok=True)
        try:
            # Hardlink on the same tmpfs: uses zero extra RAM and preserves uid/gid.
            os.link(old, staged)
        except OSError as error:
            if error.errno != errno.EXDEV:
                raise
            shutil.copy2(old, staged, follow_symlinks=False)
            old_stat = old.stat(follow_symlinks=False)
            os.chown(staged, old_stat.st_uid, old_stat.st_gid)
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


def is_excluded(relative, excludes):
    prefixes = [path.strip("/") for path in excludes if path.strip("/")]
    name = relative.as_posix()
    return any(name == prefix or name.startswith(prefix + "/") for prefix in prefixes)


def still_selected(relative, selected, excludes=None):
    """Retain old database tracking only for paths still in backup scope."""
    if excludes and is_excluded(relative, excludes):
        return False
    if selected is None:
        return True
    name = relative.as_posix()
    for item in selected:
        prefix = item.rstrip("/")
        if name == prefix or name.startswith(prefix + "/"):
            return True
    return False


def selected_files(home, selected, excludes):
    """Enumerate curated files without copying them or following symlinks."""
    result = set()
    for item in selected:
        relative = Path(item)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe selected home path: {item}")
        source = home / relative
        if is_excluded(relative, excludes):
            continue
        if source.is_symlink() or source.is_file():
            result.add(relative)
        elif source.is_dir():
            for directory, dirs, files in os.walk(source, followlinks=False):
                parent = Path(directory).relative_to(home)
                keep = []
                for name in dirs:
                    child = parent / name
                    if is_excluded(child, excludes):
                        continue
                    if (home / child).is_symlink():
                        result.add(child)
                    else:
                        keep.append(name)
                dirs[:] = keep
                for name in files:
                    child = parent / name
                    if not is_excluded(child, excludes):
                        result.add(child)
    return result


def curated_roots(home, selected, excludes, databases, sidecars):
    """Return existing top-level curated roots for Restic --files-from-raw."""
    roots = []
    seen = set()
    for item in selected:
        relative = Path(item)
        if is_excluded(relative, excludes):
            continue
        if relative in seen:
            continue
        source = home / relative
        if source.is_symlink() or source.is_file():
            if relative in databases or relative in sidecars:
                continue
            seen.add(relative)
            roots.append(home / relative)
        elif source.is_dir():
            seen.add(relative)
            roots.append(home / relative)
    return sorted(roots)


def prepare(home, stage, previous=None, selected=None, excludes=None,
            persistent_dir=None, critical_paths=None):
    """Only SQLite needs a copy. Restic reads curated roots in place."""
    if selected is None:
        raise ValueError("curated home paths are required")
    excludes = excludes or []
    if critical_paths:
        validate_critical(home, critical_paths, persistent_dir)

    candidates = selected_files(home, selected, excludes)
    old_entries = load_previous(previous)
    persistent_known = load_persistent_known(persistent_dir)
    known = set()
    for name in set(old_entries) | persistent_known:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"unsafe previous SQLite path: {name}")
        if still_selected(relative, selected, excludes):
            known.add(relative)

    databases = set()
    for relative in candidates:
        source = home / relative
        if relative in known:
            databases.add(relative)
        elif not source.is_symlink():
            if relative.suffix.lower() in SQLITE_EXTENSIONS:
                # Extensions catch damaged headers even when magic is corrupt.
                databases.add(relative)
            else:
                try:
                    if is_sqlite(home, relative):
                        databases.add(relative)
                except (FileNotFoundError, OSError, ValueError):
                    # Vanished file, non-regular file, or symlinked parent dir:
                    # do not abort the whole export during discovery.
                    continue

    # Retire deleted databases discovered under selected directories.
    # Keep explicitly selected databases expected until removed from configuration.
    exact_paths = {Path(item) for item in selected if not item.endswith("/")}
    databases.update(known & exact_paths)

    # Exclude orphaned WAL files even when their database has been retired.
    sidecars = {Path(str(relative) + suffix)
                for relative in databases | known for suffix in SIDECARS}

    # Pass curated roots (directories and non-SQLite files) via --files-from-raw
    # so live directory churn (e.g. Chromium Sessions) cannot trigger Restic exit 3.
    roots = curated_roots(home, selected, excludes, databases, sidecars)
    (stage / ".home-files").write_bytes(
        b"".join(os.fsencode(path) + b"\0" for path in roots)
    )

    # Exclude snapshotted SQLite DBs, sidecars, and configured excludes via --exclude-file.
    exclude_paths = set()
    for prefix in excludes:
        cleaned = prefix.strip("/")
        if cleaned:
            exclude_paths.add(home / cleaned)
    for rel in databases | sidecars:
        exclude_paths.add(home / rel)
    exclude_lines = sorted(escape_restic_pattern(os.fsdecode(path)) for path in exclude_paths)
    (stage / ".home-excludes").write_text(
        "".join(line + "\n" for line in exclude_lines)
    )

    entries = {}
    for relative in sorted(databases):
        staged = stage / relative
        staged.parent.mkdir(parents=True, exist_ok=True)
        try:
            snapshot_database(home, stage, relative)
            entries[str(relative)] = {"status": "fresh", "verifiedAt": int(time.time())}
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired,
                sqlite3.DatabaseError, ValueError) as error:
            if isinstance(error, subprocess.CalledProcessError) and error.stderr:
                reason = error.stderr.strip()[-240:]
            else:
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
    save_persistent_known(persistent_dir, databases)


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


def main(argv):
    if len(argv) >= 2 and argv[1] == "--publish":
        publish(Path(argv[2]), Path(argv[3]))
        return
    parser = argparse.ArgumentParser()
    parser.add_argument("home", type=Path)
    parser.add_argument("stage", type=Path)
    parser.add_argument("previous", type=Path)
    parser.add_argument("selected", nargs="?", default=None)
    parser.add_argument("excludes", nargs="?", default="[]")
    parser.add_argument("--persistent-dir", type=Path, default=None)
    parser.add_argument("--critical", default="[]")
    args = parser.parse_args(argv[1:])
    selected = json.loads(args.selected) if args.selected is not None else None
    excludes = json.loads(args.excludes) if args.excludes else []
    critical = json.loads(args.critical) if args.critical else []
    prepare(
        args.home,
        args.stage,
        args.previous,
        selected=selected,
        excludes=excludes,
        persistent_dir=args.persistent_dir,
        critical_paths=critical,
    )


if __name__ == "__main__":
    main(sys.argv)
