---
type: Runbook
title: Fleet observability (Grafana, Prometheus, Loki + Alloy)
description: Metrics and centralized journal-log collection, including volatile Pi journald.
when: Read before activating observability or replacing legacy health alerts.
resource: modules/aspects/monitoring.nix
tags: [monitoring, prometheus, grafana, epsilon, metrics, loki, alloy, journald]
---

# Fleet observability

This is **phase 1** of an observability migration. Existing fleet-health,
disk-watch, reboot-watch, backup failure checks, Discord notifications, and
deploy-rs readiness gates remain active. Do not delete them merely because
Grafana dashboards load. A separate migration must establish alert parity,
independent monitoring of Epsilon, and an acceptable resolution/clear policy.

## Topology

- **Epsilon** runs Prometheus bound to `127.0.0.1:9090`, Grafana bound
  to `127.0.0.1:3001`, Loki on TCP 3100, and a local node exporter at
  `127.0.0.1:9100`.
  Grafana is registered as `metrics.repparw.com` in the service registry,
  with Traefik routing and Authelia one-factor (admins-only) policy.
- **Pi** and **Alpha** expose node exporters on `0.0.0.0:9100`, with
  nftables ingress restricted to Epsilon's private WireGuard address.
  No exporter port is opened in the NixOS exporter module.
- Epsilon scrapes the Pi and Alpha service addresses over its existing
  `wg-home` route. The actual source IP and return route must be verified
  on both targets; the firewall intentionally fails closed otherwise.
- **Alloy** on all three hosts reads each host's journald and sends entries
  to Loki on Epsilon. Pi and Alpha connect to the WireGuard Epsilon endpoint
  (its service address). Loki's unauthenticated ingestion API is accepted
  only over `wg-home` from the specified Pi/Alpha host addresses, or locally
  on Epsilon. Firewall source address must be verified with packet capture.
  Journald metadata provides `host`, `unit`, `level`, and `identifier` labels.
- One node-exporter job at 30s cadence includes the systemd collector.
  The textfile directory supports future Nix deployment, backup freshness,
  and fleet readiness metrics without a second exporter.
- Prometheus is capped at 30 days and 3 GB. Metric history is local only.
  Grafana and Prometheus live state is preserved through Epsilon's
  `/persist` binds, but isn't currently copied to the offsite restic repo.
- Loki uses 7-day retention with filesystem-backed TSDB and compactor
  cleanup. There is **no hard byte cap**: disk exhaustion must be monitored.
  The initial implementation does not automatically ship journal entries
  generated *inside* systemd-nspawn containers; those are a follow-up.

## Pi volatile journal preservation

Pi retains its existing `Storage=volatile`, 50 MB runtime journal limit,
and tmpfs root. Alloy tails this journal in near real time, sends the
entries over the private tunnel to Loki on Epsilon, and Loki persists them
on Epsilon's `/persist` volume for 7 days. This means logs *successfully
ingested* before Pi restarts remain searchable in Grafana after reboot.

This is **best effort**, not an archival or lossless journaling system:
outages of Epsilon, the tunnel, Alloy, or Pi itself can prevent shipping.
Alloy retries failed pushes, but infinite retries do not imply an unbounded
durable queue; unsent entries may be lost once journald rotates or the Pi
reboots. The Alloy service state is on Pi's tmpfs root, so it isn't a durable
backlog. For stronger guarantees, consider moving journald to the Pi's NVMe
and persisting its `/var/log/journal` separately, using storage quotas.
Do not rely on Loki as the sole copy of crucial evidence.

Alloy applies best-effort secret masking to host-journal lines before
transmission. The collector may still contain sensitive personal data and
unrecognized secrets. Keep `metrics.repparw.com` access admin-only;
do not make the Loki API public.

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
2. On Epsilon, check `systemctl status prometheus grafana loki alloy prometheus-node-exporter`.
   Check `curl -fsS http://127.0.0.1:9090/-/ready`,
   `curl -fsS http://127.0.0.1:3100/ready`, and
   `curl -fsS http://127.0.0.1:3001/api/health`.
3. Query Prometheus's targets API on Epsilon:
   `curl -fsS http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {labels,health,lastError}'`.
   Require all three node targets to be UP. Check that `host` labels
   are alpha, pi, and epsilon.
4. Verify `https://metrics.repparw.com` requires Authelia login,
   that Grafana's Prometheus **and Loki** datasources are healthy, and
   the Fleet Overview dashboard shows CPU/memory/disk/network/systemd time series.
5. On Alpha, verify the HDD remains asleep while scrapes run. Pay
   special attention to `/mnt/hdd`, `/mnt/seagate`, and their media-portal
   automounts; update node exporter's filesystem exclusion if more
   automounts are introduced.
6. On Pi, Alpha and Epsilon, run `systemctl status alloy` and check
   `journalctl -u alloy -n 50` for shipping errors. In Grafana Explore,
   select Loki and query `{source="journald", host="pi"}`; expect lines.
   Optionally create a harmless tagged test message with
   `systemd-cat -t loki-smoke echo "fleet Loki smoke test"` and search for it
   by `identifier` or line content.
7. Restart Pi after confirming entries are visible in Loki; confirm that
   pre-restart entries remain searchable (but the local volatile journal
   correctly lost them). Interrupt the tunnel and restore it to check
   Alloy retry/dropped-entry logs. Treat persistent errors as blockers.
8. Reboot Epsilon, confirm previous metrics, Loki log history, and Grafana
   login persist, and confirm all scrape targets recover. Verify the old
   Discord alerting system still works.

**Security:** no unauthenticated Prometheus, Loki or exporter endpoints should
be reachable from the public internet. The Grafana `/api/health` path
is intentionally unauthenticated for fleet-health; other Grafana routes
must enforce Authelia. Treat Grafana local admin as a second login layer.
No new automatic notifications are enabled in this phase.

## Alternatives

The Prometheus collector, Loki and Alloy are deliberately independent of Grafana.
Before migrating the legacy alerting system, evaluate Beszel for a simpler
all-in-one host/systemd monitoring experience and Perses for a GitOps-focused
Prometheus frontend. A move away from Grafana should not require replacing
the collectors or historical metrics/logging backends. Leave this PR as a draft until
metrics collection and frontend choice have both been evaluated.

## Next migration

Use the node exporter textfile collector for fleet-specific gauges
(job failures, backup freshness and completeness, current deploy revision,
and reboot-required state); add Blackbox Exporter for HTTP/endpoint
probes and Grafana-managed Discord notification routing. Validate all
failure/recovery paths, including when Prometheus or Epsilon itself dies,
before retiring old watcher scripts. Deployment health gates must remain
independent of the monitoring stack.
