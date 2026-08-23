#!/usr/bin/env bash
set -euo pipefail

# Deploy the canonical LAN hosts fragment (modules/aspects/lan-hosts.nix) onto
# the rooted webOS TV. The TV bind-mounts it over /etc/hosts via a webosbrew
# boot hook, so it resolves *.repparw.com locally without pi-as-DNS.
#
# Idempotent: re-run any time the mapping changes. Requires `ssh tv` (see
# modules/aspects/cli/ssh.nix) and root on the TV.

tv="${1:-tv}"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# Rendered fragment from alpha's evaluated config.
nix build ".#nixosConfigurations.alpha.config.modules.lan-hosts.file" --out-link "$out/lan-hosts"

scp -q "$out/lan-hosts" "$tv:/var/lib/webosbrew/lan-hosts"

hook="$out/40-lan-hosts"
cat >"$hook" <<'EOF'
#!/bin/sh
# Managed by nix repo scripts/deploy-tv-hosts.sh. webosbrew runs this on every
# boot; safe to re-run manually. Bind-mounts the deployed fragment over
# /etc/hosts, replacing a previous copy of itself if present.
cp /etc/hosts /tmp/hosts.lan
sed -i '/^# BEGIN nix lan-hosts/,/^# END nix lan-hosts/d' /tmp/hosts.lan
cat /var/lib/webosbrew/lan-hosts >> /tmp/hosts.lan
mount --bind /tmp/hosts.lan /etc/hosts
EOF

scp -q "$hook" "$tv:/var/lib/webosbrew/init.d/40-lan-hosts"
ssh "$tv" 'chmod +x /var/lib/webosbrew/init.d/40-lan-hosts && /var/lib/webosbrew/init.d/40-lan-hosts'

echo "deployed to $tv, /etc/hosts now contains:"
ssh "$tv" 'grep -A3 "BEGIN nix lan-hosts" /etc/hosts'
