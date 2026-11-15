---
type: Troubleshooting
title: Troubleshooting
description: Symptom-indexed diagnosis and fix pairs for the fleet.
when: Read when something misbehaves and you can name the symptom; grep here first, then follow the linked page.
resource: docs/runbooks/fleet-operations.md
tags: [troubleshooting, symptoms, runbook]
---

# Troubleshooting

Each entry gives a symptom, a diagnosis, and a fix. The fix lives in the linked
runbook or tweak. This page only routes.

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

## HTTPS probe fails but the service is up

- Symptom: `curl` against traefik by IP, or from a client that sends no SNI,
  fails the handshake or gets no route while the backend itself is healthy.
- Diagnosis: `sniStrict` is enabled on both edges, so a request without a
  matching SNI gets no route.
- Fix: probe the FQDN with SNI intact. See
  [Probe HTTPS edges with SNI intact](tweaks.md#probe-https-edges-with-sni-intact).

## Alpha's media HDD never spins down

- Symptom: the HDD stays spun up even though the idle sweep timer fires.
- Diagnosis: either the drive ignores the ATA standby timer, as the WD80EAZZ
  does, or the idleness check itself touches the mount and resets the timer.
- Fix: run STANDBY IMMEDIATE, guarded by `findmnt`. See
  [Spin down alpha's media HDD](tweaks.md#spin-down-alphas-media-hdd).

## Obsidian vault sync stops

- Inspect `journalctl --user -u obsidian-bisync.service`.
  [obsidian.nix](../modules/aspects/obsidian.nix) declares the timer, paths, and
  sync flags.
- The listings under `~/.local/state/rclone/obsidian-bisync` are required state,
  not cache. Before a manual resync, pause edits and stop both the timer and the
  service. Preserve the local and remote vault copies and the listing state, and
  reconcile changes using the [bisync recovery guidance](https://rclone.org/bisync/).
  Verify a normal incremental run before you restart the timer.
