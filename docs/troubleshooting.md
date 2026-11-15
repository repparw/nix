---
type: Troubleshooting
title: Troubleshooting
description: Symptom-indexed diagnosis and fix pairs for the fleet.
when: Read when something misbehaves and you can name the symptom; grep here first, then follow the linked page.
resource: docs/runbooks/fleet-operations.md
tags: [troubleshooting, symptoms, runbook]
---

# Troubleshooting

Use the symptom to find a focused diagnosis or procedure. Read that page
only when the problem matches.

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

A probe by IP may fail TLS even while the backend works. See
[Probe HTTPS edges with SNI intact](tweaks.md#probe-https-edges-with-sni-intact).

## Alpha's media HDD never spins down

If the idle timer runs but the drive stays active, see
[Spin down Alpha's media HDD](tweaks.md#spin-down-alphas-media-hdd).

## Obsidian vault sync stops

- Inspect `journalctl --user -u obsidian-bisync.service`.
  [obsidian.nix](../modules/aspects/obsidian.nix) declares the timer, paths, and
  sync flags.
- The listings under `~/.local/state/rclone/obsidian-bisync` are required state,
  not cache. Before a manual resync, pause edits and stop both the timer and the
  service. Preserve the local and remote vault copies and the listing state, and
  reconcile changes using the [bisync recovery guidance](https://rclone.org/bisync/).
  Verify a normal incremental run before you restart the timer.
