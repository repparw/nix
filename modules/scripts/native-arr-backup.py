"""Request native Arr backups and validate the resulting SQLite ZIP exports."""

from contextlib import closing
import json
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile
import time
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
from zipfile import BadZipFile, ZipFile

import yaml


def archive_versions(config):
    found = {}
    for path in Path(config["backupDir"]).glob(config["pattern"]):
        if path.is_symlink() or not path.is_file():
            continue
        metadata = path.stat()
        if metadata.st_size:
            found[path] = (metadata.st_ino, metadata.st_mtime_ns,
                           metadata.st_ctime_ns, metadata.st_size)
    return found


def validate_archive(path, kind):
    with ZipFile(path) as archive:
        bad_file = archive.testzip()
        if bad_file is not None:
            raise BadZipFile("native backup failed its ZIP checksum")
        files = {Path(info.filename).name: info for info in archive.infolist()
                 if not info.is_dir()}
        expected_config = "config.yaml" if kind == "bazarr" else "config.xml"
        databases = [info for name, info in files.items() if name.endswith(".db")]
        if expected_config not in files or not databases:
            raise RuntimeError("native backup is missing configuration or a database")
        if kind == "bazarr" and "bazarr.db" not in files:
            raise RuntimeError("Bazarr native backup is missing bazarr.db")
        with tempfile.TemporaryDirectory(prefix="native-backup-check-") as temporary:
            for index, info in enumerate(databases):
                if not info.file_size:
                    raise RuntimeError("native backup contains an empty database")
                database_path = Path(temporary) / f"database-{index}.db"
                with archive.open(info) as source, database_path.open("wb") as target:
                    shutil.copyfileobj(source, target)
                with closing(sqlite3.connect(database_path.as_uri() + "?mode=ro", uri=True)) as database:
                    if database.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                        raise RuntimeError("native backup database failed integrity_check")


def create_backup(config):
    kind = config["kind"]
    if kind == "bazarr":
        settings = yaml.safe_load(Path(config["configFile"]).read_text())
        api_key = settings["auth"]["apikey"]
        url_base = settings.get("general", {}).get("base_url", "")
    else:
        settings = ET.parse(config["configFile"]).getroot()
        api_key = settings.findtext("ApiKey")
        url_base = settings.findtext("UrlBase", "")
    if not (isinstance(api_key, str) and api_key.strip()
            and api_key.isascii() and api_key.isprintable()):
        raise RuntimeError("native backup API key is missing or malformed")
    base = config["url"].rstrip("/") + "/" + url_base.strip("/")
    base = base.rstrip("/")

    def request(route, data=None):
        headers = {"X-Api-Key": api_key, "Accept": "application/json"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        with urlopen(Request(base + route, headers=headers, data=data), timeout=30) as response:
            body = response.read()
        return json.loads(body) if body else None

    before = archive_versions(config)
    deadline = time.monotonic() + config.get("timeoutSeconds", 600)
    if kind == "bazarr":
        request("/api/system/backups", b"")
    else:
        command_route = f'/api/{config["apiVersion"]}/command'
        command = request(command_route, json.dumps({"name": "Backup"}).encode())
        if not isinstance(command, dict) or type(command.get("id")) is not int:
            raise RuntimeError("native backup API returned no command ID")
        while True:
            result = request(command_route + "/" + str(command["id"]))
            status = result.get("status") if isinstance(result, dict) else None
            if status == "completed":
                break
            if status not in ("queued", "started"):
                raise RuntimeError("native backup command did not complete successfully")
            if time.monotonic() >= deadline:
                raise TimeoutError("native backup command timed out")
            time.sleep(1)

    while True:
        after = archive_versions(config)
        refreshed = [path for path, metadata in after.items() if before.get(path) != metadata]
        for path in sorted(refreshed, key=lambda p: after[p][1], reverse=True):
            try:
                validate_archive(path, kind)
            except BadZipFile:
                # Bazarr acknowledges the queued request before writing the ZIP.
                continue
            if len(refreshed) != 1 or path in before:
                raise RuntimeError("ambiguous native backup output; preserving all manual archives")
            managed = Path(config["managedDir"])
            if managed.is_symlink():
                raise RuntimeError("managed backup directory must not be a symlink")
            managed.mkdir(mode=0o700, parents=True, exist_ok=True)
            destination = managed / path.name
            if destination.exists():
                raise RuntimeError("managed archive already exists; preserving both backups")
            path.rename(destination)
            os.utime(destination, None)
            cutoff = time.time() - 28 * 86400
            for previous in managed.glob(config["pattern"]):
                if previous.is_symlink() or not previous.is_file():
                    continue
                if previous.stat().st_mtime < cutoff:
                    previous.unlink()
            print(f"Native {config['app']} backup verified: {path.name}", flush=True)
            return
        if time.monotonic() >= deadline:
            raise TimeoutError("native backup produced no fresh valid archive")
        time.sleep(1)


if __name__ == "__main__":
    create_backup(json.loads(Path(sys.argv[1]).read_text()))
