---
type: Runbook
title: Fleet metrics (Grafana + Prometheus)
description: Provisioning, network access, validation and rollback for the fleet metrics stack.
when: Read before activating observability or replacing legacy health alerts.
resource: modules/aspects/monitoring.nix
tags: [monitoring, prometheus, grafana, epsilon, metrics]
---

# Fleet metrics

This is **phase 1** of an observability migration. Existing fleet-health,
disk-watch, reboot-watch, backup failure checks, Discord notifications, and
deploy-rs readiness gates remain active. Do not delete them merely because
Grafana dashboards load. A separate migration must establish alert parity,
independent monitoring of Epsilon, and an acceptable resolution/clear policy.

## Topology

- **Epsilon** runs Prometheus bound to `127.0.0.1:9090`, Grafana bound
  to `127.0.0.1:3001`, and a local node exporter at `127.0.0.1:9100`.
  Grafana is registered as `metrics.repparw.com` in the service registry,
  with Traefik routing and Authelia one-factor (admins-only) policy.
- **Pi** and **Alpha** expose node exporters on `0.0.0.0:9100`, with
  nftables ingress restricted to Epsilon's private WireGuard address.
  No exporter port is opened in the NixOS exporter module.
- Epsilon scrapes the Pi and Alpha service addresses over its existing
  `wg-home` route. The actual source IP and return route must be verified
  on both targets; the firewall intentionally fails closed otherwise.
- One node-exporter job at 30s cadence includes the systemd collector.
  The textfile directory supports future Nix deployment, backup freshness,
  and fleet readiness metrics without a second exporter.
- Prometheus is capped at 30 days and 3 GB. Metric history is local only.
  Grafana and Prometheus live state is preserved through Epsilon's
  `/persist` binds, but isn't currently copied to the offsite restic repo.

## First-time login

Grafana generates its own 32-byte random admin password in
`/var/lib/grafana/admin-password` on the first service start. It is not
placed in Git or the Nix store. After activating Epsilon:

```sh
ssh root@epsilon 'cat /var/lib/grafana/admin-password'
```

Authenticate through Authelia first, then sign in to Grafana as `admin`
with this password. Rotate it in Grafana if desired; the first-start file
is **not** a declarative password reset for an existing Grafana database.
Do not post either password in an issue or CI log. Verify the
`metrics.repparw.com` DNS record / wildcard points to the public edge
before expecting browser access.

## Rollout and checks

1. The staged deployment pipeline activates Epsilon before Alpha and Pi;
   its collector can temporarily report the other two scrape targets DOWN.
   That is expected during initial rollout and must not gate deployment.
2. On Epsilon, check `systemctl status prometheus grafana prometheus-node-exporter`.
   Check `curl -fsS http://127.0.0.1:9090/-/ready` and
   `curl -fsS http://127.0.0.1:3001/api/health`.
3. Query Prometheus's targets API on Epsilon:
   `curl -fsS http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {labels,health,lastError}'`.
   Require all three node targets to be UP. Check that `host` labels
   are alpha, pi, and epsilon.
4. Verify `https://metrics.repparw.com` requires Authelia login,
   that Grafana's Prometheus datasource is healthy, and the Fleet Overview
   dashboard shows CPU/memory/disk/network/systemd time series.
5. On Alpha, verify the HDD remains asleep while scrapes run. Pay
   special attention to `/mnt/hdd`, `/mnt/seagate`, and their media-portal
   automounts; update node exporter's filesystem exclusion if more
   automounts are introduced.
6. Reboot Epsilon, confirm previous metrics and login persist, and
   confirm all three scrape targets recover. Verify the old Discord
   alerting system still works.

**Security:** no unauthenticated Prometheus or exporter endpoints should
be reachable from the public internet. The Grafana `/api/health` path
is intentionally unauthenticated for fleet-health; other Grafana routes
must enforce Authelia. Treat Grafana local admin as a second login layer.
No new automatic notifications are enabled in this phase.

## Alternatives

The collector and node exporters are deliberately independent of Grafana.
Before migrating the legacy alerting system, evaluate Beszel for a simpler
all-in-one host/systemd monitoring experience and Perses for a GitOps-focused
Prometheus frontend. A move away from Grafana should not require replacing
the collectors or historical metrics backend. Leave this PR as a draft until
metrics collection and frontend choice have both been evaluated.

## Next migration

Use the node exporter textfile collector for fleet-specific gauges
(job failures, backup freshness and completeness, current deploy revision,
and reboot-required state); add Blackbox Exporter for HTTP/endpoint
probes and Grafana-managed Discord notification routing. Validate all
failure/recovery paths, including when Prometheus or Epsilon itself dies,
before retiring old watcher scripts. Deployment health gates must remain
independent of the monitoring stack.
