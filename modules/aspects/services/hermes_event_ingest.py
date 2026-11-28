"""Shared durable intake for validated Hermes fleet events.

The source-specific triage modules own validation, fingerprints, and dispatch.
This module owns the byte limit, unprivileged receipt storage, and exact-ID ACK.
"""

import json
import os
from pathlib import Path
import secrets
import tempfile


def decode_event(raw, max_bytes, validate):
    if len(raw) > max_bytes:
        raise ValueError("event exceeds size limit")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate event fields")
            result[key] = value
        return result

    return validate(json.loads(raw, object_pairs_hook=pairs))


def private_dir(path):
    path.mkdir(mode=0o700, exist_ok=True)
    if path.is_symlink() or not path.is_dir():
        raise ValueError("invalid private directory")
    os.chmod(path, 0o700)
    directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def ingest_event(home, raw, namespace, decode):
    event = decode(raw)
    if home.is_symlink() or not home.is_dir():
        raise ValueError("Hermes home is unavailable")
    # The root-owned host command may write only as the unprivileged Hermes user.
    # Enter before dropping privileges: private ancestors can be inaccessible.
    owner = home.stat()
    if os.geteuid() == 0:
        if owner.st_uid == 0:
            raise ValueError("Hermes home must have an unprivileged owner")
        os.chdir(home)
        home = Path(".")
        os.setgroups([])
        os.setgid(owner.st_gid)
        os.setuid(owner.st_uid)

    queue = home / namespace
    private_dir(queue)
    inbox = queue / "inbox"
    private_dir(inbox)
    receipts = queue / "receipts"
    private_dir(receipts)
    destination = inbox / (event["event_id"] + ".json")
    receipt = receipts / destination.name
    canonical = json.dumps(event, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()

    # Use a relative path after privilege drop; mkstemp resolves private ancestors
    # to an absolute path, which may no longer be accessible.
    temporary = inbox / (".ingest-" + secrets.token_hex(16))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(canonical)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, receipt)
        except FileExistsError:
            if receipt.is_symlink() or receipt.read_bytes() != canonical:
                raise ValueError("event identity collision")
        try:
            os.link(receipt, destination)
        except FileExistsError:
            if destination.is_symlink() or destination.read_bytes() != canonical:
                raise ValueError("event identity collision")
        for directory in (receipts, inbox):
            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
    finally:
        os.unlink(temporary)
    return {"event_id": event["event_id"]}
