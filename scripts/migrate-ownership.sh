#!/usr/bin/env bash
set -euo pipefail

# Migration script for file ownership from root (PUID=0) to native service users
# Run as root: sudo -A bash migrate-ownership.sh

echo "=== Migrating file ownership from root to service users ==="

# Helper function
migrate() {
    local user="$1"
    local group="$2"
    shift 2
    for path in "$@"; do
        if [ -e "$path" ]; then
            echo "  $path -> $user:$group"
            chown -R "$user:$group" "$path"
        else
            echo "  SKIP (not found): $path"
        fi
    done
}

echo ""
echo "--- Arr services ---"
migrate bazarr bazarr \
    /home/containers/config/bazarr

migrate prowlarr prowlarr \
    /home/containers/config/prowlarr

migrate qbittorrent qbittorrent \
    /home/containers/config/qbittorrent \
    /home/containers/config/downloading \
    /home/containers/data/torrents

migrate radarr radarr \
    /home/containers/config/radarr

migrate sonarr sonarr \
    /home/containers/config/sonarr

echo ""
echo "--- Authelia ---"
migrate authelia-main authelia-main \
    /home/containers/config/authelia/config \
    /home/containers/config/authelia/secrets

echo ""
echo "--- Changedetection ---"
migrate changedetection changedetection \
    /home/containers/config/changedetection

echo ""
echo "--- FreshRSS ---"
migrate freshrss freshrss \
    /home/containers/config/freshrss

echo ""
echo "--- Jellyfin ---"
migrate jellyfin jellyfin \
    /home/containers/config/jellyfin

echo ""
echo "--- ntfy ---"
migrate ntfy-sh ntfy-sh \
    /home/containers/config/ntfy

echo ""
echo "--- Paperless ---"
migrate paperless paperless \
    /home/containers/data/paper \
    /home/containers/config/paper

echo ""
echo "--- Traefik ---"
migrate traefik traefik \
    /home/containers/config/traefik/certs

echo ""
echo "--- Shared data directories ---"
# These are accessed by multiple services, set to a shared group or keep as-is
# radarr, sonarr, bazarr all need /data and /data/seagate
if [ -d /home/containers/data ]; then
    echo "  Setting /home/containers/data permissions (shared by arr services)"
    chgrp -R media /home/containers/data
    chmod -R g+rwX /home/containers/data
fi
if [ -d /mnt/seagate ]; then
    echo "  Setting /mnt/seagate permissions (shared by arr services)"
    chgrp -R media /mnt/seagate
    chmod -R g+rwX /mnt/seagate
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next steps:"
echo "  1. Stop podman containers: systemctl --user stop podman.service"
echo "  2. Rebuild system: nh os switch"
echo "  3. Verify services start correctly"
