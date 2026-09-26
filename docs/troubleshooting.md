---
type: Troubleshooting
title: Troubleshooting
description: Symptom-indexed diagnosis and fix pairs for the fleet.
when: Read when something misbehaves and you can name the symptom; grep here first, then follow the linked page.
resource: docs/runbooks/fleet-operations.md
tags: [troubleshooting, symptoms, runbook]
---

# Troubleshooting

Symptom → diagnosis → fix. The fix lives in the linked runbook or tweak;
this page only routes.

## Moonfin shows "no content found", library queries return 500

- Symptom: Moonfin (or any client) shows an empty library while Jellyfin
  itself answers `/health`; the server log shows every library and `/Users`
  query failing.
- Diagnosis: the running Jellyfin binary predates the database schema —
  typically after an incidental lock change rolled nixpkgs (and Jellyfin)
  back behind a schema the DB had already migrated to. The DB is fine; the
  binary is too old.
- Fix: bump nixpkgs to a Jellyfin that matches the schema, rebuild, and
  activate; see [Update rollback](runbooks/update-rollback.md).

## HTTPS probe fails but the service is up

- Symptom: `curl` against traefik by IP, or from a client that sends no SNI,
  fails the handshake or gets no route while the backend itself is healthy.
- Diagnosis: `sniStrict` is enabled on both edges — no SNI match, no route.
- Fix: probe the FQDN with SNI intact; see
  [Probe traefik with SNI intact](tweaks.md#probe-traefik-with-sni-intact).

## Alpha's media HDD never spins down

- Symptom: the HDD stays spun up despite the idle sweep timer firing.
- Diagnosis: either the drive ignores the ATA standby timer (true of the
  WD80EAZZ), or the idleness check itself touches the mount and resets the
  timer.
- Fix: STANDBY IMMEDIATE guarded by `findmnt`; see
  [Spin down alpha's media HDD](tweaks.md#spin-down-alphas-media-hdd).
