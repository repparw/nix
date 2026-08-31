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
# boot; safe to re-run manually. Installs the deployed fragment over
# /etc/hosts, replacing a previous copy of itself if present.
#
# webOS normally keeps /etc/hosts as a writable tmpfs bind (LG jail setup /
# webosbrew update-blocker), so editing in place is enough and avoids this
# kernel refusing to stack a file bind over an existing file bind. Fall back
# to creating that bind ourselves when facing the pristine read-only file.
FRAG=/var/lib/webosbrew/lan-hosts

filter() {
  sed '/^# BEGIN nix lan-hosts/,/^# END nix lan-hosts/d'
}

rm -f /tmp/hosts.lan* /tmp/hosts.new

# Try direct write (tmpfs case), fallback to bind-mount on ro root (pristine webOS)
if [ -w /etc/hosts ]; then
  filter </etc/hosts >/tmp/hosts.new && cat "$FRAG" >>/tmp/hosts.new
  if cat /tmp/hosts.new >/etc/hosts 2>/dev/null; then
    rm -f /tmp/hosts.new
  else
    # ro root: use bind-mount path
    filter </etc/hosts >/tmp/hosts.lan && cat "$FRAG" >>/tmp/hosts.lan
    mount --bind /tmp/hosts.lan /etc/hosts
    rm -f /tmp/hosts.new
  fi
else
  filter </etc/hosts >/tmp/hosts.lan && cat "$FRAG" >>/tmp/hosts.lan
  mount --bind /tmp/hosts.lan /etc/hosts
fi
EOF

scp -q "$hook" "$tv:/var/lib/webosbrew/init.d/40-lan-hosts"
ssh "$tv" 'chmod +x /var/lib/webosbrew/init.d/40-lan-hosts && /var/lib/webosbrew/init.d/40-lan-hosts'

echo "deployed to $tv, /etc/hosts now contains:"
ssh "$tv" 'grep -A3 "BEGIN nix lan-hosts" /etc/hosts'
