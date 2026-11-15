---
type: Troubleshooting
title: Troubleshooting
description: Common failure symptoms, targeted diagnostics, and small operational adjustments.
when: Read when something misbehaves and you can name the symptom; grep here first, then follow the linked page.
resource: docs/runbooks/fleet-operations.md
tags: [troubleshooting, symptoms, runbook, dns, tweaks]
---

# Troubleshooting

Use these targeted checks for known failure modes. Nix modules and scripts
remain authoritative for current settings, timers, and service ownership.

## Moonfin shows "no content found", library queries return 500

- Symptom: Moonfin or any other client shows an empty library while Jellyfin
  itself answers `/health`. The server log shows every library and `/Users`
  query failing.
- Diagnosis: the running Jellyfin binary is older than the database schema. This
  typically happens after an incidental lock change rolls nixpkgs, and with it
  Jellyfin, back behind a schema that the database already migrated to. The
  database is fine. The binary is too old.
- Fix: bump nixpkgs to a Jellyfin that matches the schema, rebuild, and
  activate. See [Update rollback](runbooks/update-rollback.md).

## Probe HTTPS edges with SNI intact

Both Traefik edges set `tls.options.default.sniStrict = true`, so probing by IP
without a hostname fails even when the backend is healthy. Pi's LAN Traefik
routes Jellyfin only. Home Assistant uses the public Cloudflare Tunnel to
Epsilon, so do not force its hostname to Pi's loopback.

Probe the public Home Assistant route using normal DNS:

```sh
curl -fsS -o /dev/null -w '%{http_code}\n' https://home.repparw.com/
```

To exercise Pi's _local_ Jellyfin edge while keeping SNI:

```sh
curl -fsS --resolve jellyfin.repparw.com:443:127.0.0.1 \
  -o /dev/null -w '%{http_code}\n' https://jellyfin.repparw.com/health
```

Only LAN-edge vhosts have static `/etc/hosts` entries on fleet hosts. Public
HTTPS names use regular DNS, and SSH still uses direct machine addresses.

Touches: `modules/aspects/services/default.nix`,
`modules/aspects/services/fleet-health.nix`, `modules/_services/proxy.nix`,
and `modules/aspects/lan-edge.nix`.

## Spin down alpha's media HDD

The WD80EAZZ ignores the ATA standby timer. `hdparm -S` and
`smartctl --set standby` are clamped to a vendor minimum, and that minimum never
engages, so scheduled standby never fires. The only way to spin the drive down
is STANDBY IMMEDIATE (`hdparm -y`), guarded by `findmnt` on the disk label.
`findmnt` reads mountinfo and does not touch the automount. A statvfs check
through `mountpoint` would reset the idle timer and defeat the sweep.

Touches: `modules/hosts/alpha.nix` (`systemd.services.hdd-spindown`,
`systemd.timers.hdd-spindown`, every 5 minutes).

## Obsidian vault sync stops

- Inspect `journalctl --user -u obsidian-bisync.service`.
  [obsidian.nix](../modules/aspects/obsidian.nix) declares the timer, paths, and
  sync flags.
- The listings under `~/.local/state/rclone/obsidian-bisync` are required state,
  not cache. Before a manual resync, pause edits and stop both the timer and the
  service. Preserve the local and remote vault copies and the listing state, and
  reconcile changes using the [bisync recovery guidance](https://rclone.org/bisync/).
  Verify a normal incremental run before you restart the timer.

## GE-Proton automatic FSR upgrade

The gaming aspect sets `PROTON_FSR4_UPGRADE=1` in the launcher environments of
Steam and Heroic, including Heroic shortcuts inside Steam. GE-Proton picks its
default DLL from the upstream upscaler manifest. The managed runner stays
`GE-Proton`.

Compatible games that use their FSR 3.1 integration can use the automatic
upgrade. The flag does not select an in-game upscaler, convert arbitrary FSR2
integrations, or guarantee that the selected model supports the GPU. FSR 4.1 on
Alpha's RX 6700 XT still needs runtime verification, tracked in
[issue #323](https://github.com/repparw/nix/issues/323).

To disable the upgrade for one Steam game, set its launch options to
`PROTON_FSR4_UPGRADE=0 %command%`. For a Heroic game, add `PROTON_FSR4_UPGRADE`
with the value `0` to that game's environment settings. To diagnose, temporarily
set `PROTON_FSR4_INDICATOR=1` for the game, and remove the setting after you
check the active upscaler. After you activate a changed launcher package,
restart the launcher.

Touches: `modules/aspects/gaming.nix` (`gamingEnvironment`, Steam's `extraEnv`,
and the Heroic package override).

## Native container DNS failures

Containers intentionally use the host's bridge resolver instead of an
independent upstream DNS configuration. This keeps name resolution and
network-policy decisions under the host's control. The service aspects and the
host's effective NixOS configuration declare the resolver listeners, gateway
addresses, and firewall permissions. Do not copy the per-host address table into
a runbook.

Check host resolution and the listener first:

```sh
resolvectl status
ss -lunpt | rg ':53'
systemctl status systemd-resolved.service
```

Then check the affected container:

```sh
container=sonarr # replace with the affected native container
sudo nixos-container run "$container" -- cat /etc/resolv.conf
sudo nixos-container run "$container" -- getent hosts cache.nixos.org
sudo nixos-container run "$container" -- resolvectl query cache.nixos.org
```

If the host resolves but the container does not, compare the container's
nameserver with its host bridge address. Then inspect the firewall rules on
`ve-*` interfaces and the active resolved listener. A failed lookup alone does
not tell you whether the problem is routing, firewall policy, the resolver, or
the upstream DNS provider.
