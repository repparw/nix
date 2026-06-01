#!/usr/bin/env bash
set -euo pipefail

# Migration script for file permissions when using containers with privateUsers=pick.
# Container service users don't exist on the host, so we use broad permissions.
# Run as root: sudo -A bash migrate-ownership.sh

echo "=== Setting file permissions for native containers ==="

# Config dirs: containers need read access
chmod_config() {
    for path in "$@"; do
        if [ -e "$path" ]; then
            echo "  $path -> a+rX"
            chmod -R a+rX "$path"
        else
            echo "  SKIP (not found): $path"
        fi
    done
}

# Data dirs: containers need read+write access
chmod_data() {
    for path in "$@"; do
        if [ -e "$path" ]; then
            echo "  $path -> a+rwX"
            chmod -R a+rwX "$path"
        else
            echo "  SKIP (not found): $path"
        fi
    done
}

echo ""
echo "--- Arr services ---"
chmod_config \
    /home/containers/config/bazarr \
    /home/containers/config/prowlarr \
    /home/containers/config/qbittorrent \
    /home/containers/config/radarr \
    /home/containers/config/sonarr

chmod_data \
    /home/containers/config/downloading \
    /home/containers/data/torrents

echo ""
echo "--- Authelia ---"
chmod_config \
    /home/containers/config/authelia/config \
    /home/containers/config/authelia/secrets

echo ""
echo "--- Changedetection ---"
chmod_data \
    /home/containers/config/changedetection

echo ""
echo "--- FreshRSS ---"
chmod_data \
    /home/containers/config/freshrss

echo ""
echo "--- Jellyfin ---"
chmod_data \
    /home/containers/config/jellyfin

echo ""
echo "--- ntfy ---"
chmod_data \
    /home/containers/config/ntfy

echo ""
echo "--- Paperless ---"
mkdir -p /home/containers/data/paper/consume
chmod_data \
    /home/containers/data/paper \
    /home/containers/config/paper

echo ""
echo "--- Glance ---"
chmod_config \
    /home/containers/config/glance

echo ""
echo "--- Traefik ---"
chmod_config \
    /home/containers/config/traefik

# acme.json must be 600 for traefik
if [ -f /home/containers/config/traefik/certs/acme.json ]; then
    echo "  Setting acme.json to 600"
    chmod 600 /home/containers/config/traefik/certs/acme.json
fi

echo ""
echo "--- Shared data directories ---"
chmod_data /home/containers/data
chmod_data /mnt/seagate

echo ""
echo "=== Permission setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Rebuild system: nh os switch"
echo "  2. Verify services start correctly"
