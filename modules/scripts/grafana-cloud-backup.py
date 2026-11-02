"""Export Grafana configuration privately using its native read/export APIs."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tarfile
import tempfile
import urllib.parse
import urllib.request


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError("Grafana backup refused an HTTP redirect")


def export(fetch, destination):
    os.umask(0o077)
    destination = Path(destination)
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".export-", dir=destination) as temp:
        root = Path(temp)
        files = {}

        def save(name, data):
            content = (json.dumps(data, indent=2, sort_keys=True) + "\n").encode()
            (root / name).write_bytes(content)
            files[name] = hashlib.sha256(content).hexdigest()

        for name, endpoint in {
            "alert-rules.json": "/api/v1/provisioning/alert-rules/export?format=json",
            "alert-rules-api.json": "/api/v1/provisioning/alert-rules",
            "contact-points.json": "/api/v1/provisioning/contact-points/export?format=json&decrypt=true",
            "notification-policies.json": "/api/v1/provisioning/policies/export?format=json",
            "notification-policies-api.json": "/api/v1/provisioning/policies",
            "mute-timings.json": "/api/v1/provisioning/mute-timings/export?format=json",
            "mute-timings-api.json": "/api/v1/provisioning/mute-timings",
            "templates.json": "/api/v1/provisioning/templates",
            "datasources.json": "/api/datasources",
        }.items():
            save(name, fetch(endpoint))
        folders = fetch("/api/folders?limit=1000")
        if len(folders) >= 1000:
            raise RuntimeError("Folder listing exceeds backup page limit")
        save("folders.json", folders)
        for folder in folders:
            uid = urllib.parse.quote(folder["uid"], safe="")
            save(f"folder-{uid}-permissions.json", fetch(f"/api/folders/{uid}/permissions"))
        page = 1
        dashboards = 0
        while True:
            items = fetch(f"/api/search?type=dash-db&limit=1000&page={page}")
            if not items:
                break
            for item in items:
                uid = urllib.parse.quote(item["uid"], safe="")
                save(f"dashboard-{uid}.json", fetch(f"/api/dashboards/uid/{uid}"))
                save(f"dashboard-{uid}-permissions.json", fetch(f"/api/dashboards/uid/{uid}/permissions"))
                dashboards += 1
            page += 1
        save("manifest.json", {
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "dashboards": dashboards,
            "files": dict(files),
            "consistency": "Sequential API reads, not an atomic Cloud snapshot",
            "secrets": "Contact-point secrets included; datasource secrets require separate recovery",
        })
        archive = root / "grafana-cloud-state.tar.gz"
        with tarfile.open(archive, "w:gz") as handle:
            for name in sorted(files):
                handle.add(root / name, arcname=name)
        with tarfile.open(archive, "r:gz") as handle:
            for name in files:
                content = handle.extractfile(name).read()
                if hashlib.sha256(content).hexdigest() != files[name]:
                    raise RuntimeError("Grafana backup archive verification failed")
        os.replace(archive, destination / archive.name)
    return dashboards


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--token-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    origin = args.url.rstrip("/")
    parsed = urllib.parse.urlsplit(origin)
    if parsed.scheme != "https" or parsed.username or parsed.password or parsed.path:
        parser.error("--url must be an HTTPS origin without credentials")
    token = args.token_file.read_text().strip()
    opener = urllib.request.build_opener(NoRedirects())

    def fetch(endpoint):
        request = urllib.request.Request(origin + endpoint, headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
        })
        with opener.open(request, timeout=30) as response:
            return json.load(response)

    count = export(fetch, args.output)
    print(f"Verified Grafana configuration backup: {count} dashboards")


if __name__ == "__main__":
    main()
