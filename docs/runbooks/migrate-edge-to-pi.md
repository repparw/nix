---
type: Runbook
when: Run when moving the public edge (traefik/authelia/ddclient) from alpha to pi.
title: Migrate the edge to pi
description: Cutover and rollback steps for the two-commit edge migration on branch migrate/pi-edge.
tags: [pi, alpha, traefik, authelia, ingress, migration]
---

# Migrate the edge to pi

The migration ships as two commits so production can cut over between
deployments. Commit 1 brings a standby edge up on pi; commit 2 retires
alpha's edge. Verify each phase before advancing.

## Phase 1 — deploy commit 1 (standby edge)

After deploying the first commit of `migrate/pi-edge` to both hosts:

1. pi gains Traefik (:80/:443), an Authelia nspawn container
   (`10.231.136.7`), and ddclient. Its Authelia database is **empty** — that
   is expected; nothing routes through it yet because LAN DNS still points at
   alpha.
2. Confirm on pi:
   - `curl -k https://localhost` serves the glance dashboard router (cert
     warnings fine; ACME DNS-01 should already have issued).
   - `systemctl status container@authelia ddclient traefik`.
   - Authelia answers: `curl http://10.231.136.7:9091/api/health`.
3. Confirm alpha unchanged: all vhosts still work exactly as before.

## Phase 2 — seed Authelia state, then cut over

1. Copy Authelia's data from alpha (users, TOTP seeds, OIDC client state):
   ```console
   rsync -a root@alpha:/home/containers/config/authelia/config/ \
     root@pi:/home/containers/config/authelia/config/
   ```
2. Deploy commit 2 to **both** hosts. Alpha drops its edge units and closes
   :80/:443; pi becomes the sole ingress for every `*.repparw.com` vhost.
3. Flip the router port-forwards: TCP 80 and 443 now target `192.168.0.4`
   (was `.18`). Keep the qBittorrent forward (TCP+UDP 54535 → alpha).
4. Update Cloudflare DNS if the A record is host-specific (ddclient on pi now
   owns updates; dual-run during transition was safe because updates are
   idempotent).

## Verification (alpha powered OFF)

- `home.repparw.com`, `rss.repparw.com`, `paper.repparw.com`,
  `jellyfin.repparw.com`, `qbit.repparw.com`, `code.repparw.com`,
  `finance.repparw.com`, apex `repparw.com` — all resolve and respond.
- Authelia login works with your existing TOTP/passkey (proves the seeded
  storage carried over).
- Home Assistant remote control still functions (its OIDC issuer is
  `auth.repparw.com`; session cookies may need one re-login).

## Known caveats

- **opencode (`code.repparw.com`, port 4096) and finance (port 3000)** are
  alpha-native listeners whose bind address this repo does not control. If pi
  cannot reach them post-cutover (`curl 192.168.0.18:4096` from pi), they bind
  loopback-only: add `--hostname 0.0.0.0`-style args or a small
  `socat TCP-LISTEN` publish unit on alpha.
- Container backends reach pi via nspawn `forwardPorts` publishes on alpha
  (qbittorrent remapped to LAN port 18080, glance to 18085). The mapping
  lives in `_services/inventory.nix` next to each service's routing facts.

## Rollback

Redeploy the previous generation on both hosts (commit 1 state), restore the
router forwards to `.18`. No data migration needs reversing; the Authelia
copy on pi can be deleted.

## Related

- [Host profiles](../hosts.md)
- [Deploy NixOS to the Raspberry Pi](deploy-pi-nixos.md)
