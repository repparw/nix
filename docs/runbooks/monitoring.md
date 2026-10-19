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

- The **generic Alloy agent** is included through `den.default.includes`, so
  every NixOS fleet host receives the same journald and Unix exporter pipeline.
- **Alpha** declares its sleeping-HDD mount exclusions explicitly; Epsilon
  configures its Alloy to write to loopback ports 9091/3101. Alpha and Pi
  use Epsilon's private address and separate SOPS credentials, delivered
  to Alloy through systemd `LoadCredential`.
- Alloy scrapes the built-in Unix exporter every 30s (CPU, RAM, disk,
  network, systemd, textfile metrics) and **its own localhost status endpoint**
  (`127.0.0.1:12345/metrics`). Both jobs forward to the same Prometheus
  remote-write pipeline. The local Alloy status endpoint is not publicly
  exposed. Alloy also ships host journal entries to Loki on Epsilon.
- **Epsilon** runs Prometheus on loopback TCP 9091, Loki on loopback TCP
  3101 and Grafana on loopback TCP 3001. Grafana is registered as
  `metrics.repparw.com` through existing Traefik/Authelia auth.
- Traefik exposes only authenticated POST ingestion routes on TCP 9090
  (`/api/v1/write`) and 3100 (`/loki/api/v1/push`). Query and admin routes
  stay local. The firewall permits those ports only through `wg-home`
  from `10.5.5.1`: packet inspection verified that the home router SNATs
  both Alpha and Pi to that address. Per-host credentials distinguish
  authorized agents from other traffic behind the same gateway.
- Credentials are encrypted in `monitoring-alpha.sops.yaml`,
  `monitoring-pi.sops.yaml`, and `monitoring-server.sops.yaml`. Each agent
  file is decryptable only by its host and the recovery key; only Epsilon
  and the recovery key can decrypt the receiver's bcrypt password file.
  To rotate one agent, update its password and the matching receiver hash,
  deploy the receiver, then that agent. Never put passwords in Alloy's
  generated configuration or command-line arguments.
- The dashboard tracks **three expected hosts** (Alpha, Pi, Epsilon).
  Separate `absent_over_time(node_uname_info{host="..."}[5m])` checks
  report 1 when a host stops sending Unix exporter samples rather than
  relying on disappearing `up` series. These are **display indicators**,
  not yet Discord alert rules; the existing fleet-health alerts remain.
- Textfile metrics can be published to `/var/lib/fleet-metrics/textfile`.
- Prometheus keeps 30 days of metrics with a 3 GB storage retention limit.
  Loki keeps 7 days of filesystem-backed TSDB log chunks. Neither Loki
  retention nor its default ingestion limits enforce a disk-space quota.
- Epsilon runs the existing **disk-watch** script every 15 minutes for
  `/persist` (warning at 70%, critical at 85%) and sends Discord alerts
  without depending on Loki/Prometheus/Grafana. Consider filesystem quotas
  or a dedicated volume if monitoring data ever warrants hard isolation.
- Epsilon uses explicit `/persist` binds for Loki, Prometheus and Grafana,
  including Grafana encryption credentials. The monitoring data is not yet
  copied to the offsite restic repository.
- Only _host_ journald entries are collected by this initial pipeline.
  Individual systemd-nspawn container journals require separate collection.

## Pi volatile journal preservation

Pi retains its existing `Storage=volatile`, 50 MB runtime journal limit,
and tmpfs root. Alloy tails this journal in near real time, sends the
entries over the private tunnel to Loki on Epsilon, and Loki persists them
on Epsilon's `/persist` volume for 7 days. This means logs _successfully
ingested_ before Pi restarts remain searchable in Grafana after reboot.

This is **best effort**, not an archival or lossless journaling system:
outages of Epsilon, the tunnel, Alloy, or Pi itself can prevent shipping.
Alloy retries failed pushes, but infinite retries do not imply an unbounded
durable queue; unsent entries may be lost once journald rotates or the Pi
reboots. The Alloy service state is on Pi's tmpfs root, so it isn't a durable
backlog. For stronger guarantees, consider moving journald to the Pi's NVMe
and persisting its `/var/log/journal` separately, using storage quotas.
Do not rely on Loki as the sole copy of crucial evidence.

Alloy applies best-effort secret masking to host-journal lines before
transmission. The pinned Alloy version classifies `loki.secretfilter` as
experimental, so its service explicitly enables that stability level. The Loki backend may still contain sensitive personal data and
unrecognized secrets. Keep `metrics.repparw.com` access admin-only;
do not make the Loki API public.

## Login

Sign in through Authelia. Traefik forwards the authenticated username, name and
email to Grafana, which accepts these identity headers only from loopback.
The existing ingress policy permits only Authelia members of `admins`; their
Grafana accounts receive the organization Admin role. Grafana hides its own
login form and requires proxy authentication on each request.

For local recovery, Grafana generates a random admin password in
`/var/lib/grafana/admin-password` and a separate encryption secret in
`/var/lib/grafana/secret-key` on first start. Neither value is placed
in Git or the Nix store. Both files persist across Epsilon reboots.
Never regenerate or rotate the secret key casually: existing encrypted
Grafana data depends on it. After activating Epsilon:

```sh
ssh root@epsilon 'cat /var/lib/grafana/admin-password'
```

The local `admin` account remains available through the loopback API for
recovery. Rotate it in Grafana if desired; the first-start file
is **not** a declarative password reset for an existing Grafana database.
Do not post either password in an issue or CI log. Verify the
`metrics.repparw.com` DNS record / wildcard points to the public edge
before expecting browser access.

## Rollout and checks

1. Deploy Epsilon's receivers first, then Alpha/Pi's Alloy agents.
   Cross-host uploads will fail until the Epsilon WireGuard route,
   source-address filtering, credentials, and endpoint services are working.
2. On Epsilon, check `systemctl status prometheus grafana loki alloy`.
   Check `curl -fsS http://127.0.0.1:9091/-/ready`,
   `curl -fsS http://127.0.0.1:3101/ready`, and
   `curl -fsS http://127.0.0.1:3001/api/health -H 'Host: metrics.repparw.com'`.
   Check `traefik.service`; an unauthenticated POST to either private
   ingestion route must return 401. Authenticated agents must upload
   successfully, while query routes on those ports return 404.
3. Query Prometheus's **metrics API**, not its targets API (the server
   does not scrape remote hosts):
   `curl -fsSG http://127.0.0.1:9091/api/v1/query --data-urlencode 'query=node_uname_info' | jq '.data.result[].metric | {host,job,instance}'`.
   Expect one result from each host with `job="node"`. Check that
   `timestamp(node_uname_info{host="pi"})` remains recent. The absence
   of incoming samples indicates shipping or networking failure. Repeat for
   `up{job="alloy"}` and inspect Loki/remote-write drop/failure metrics.
4. Verify `https://metrics.repparw.com` requires Authelia login,
   that Grafana's Prometheus **and Loki** datasources are healthy, and
   the Fleet Overview dashboard shows CPU/memory/disk/network/systemd time series.
5. On Alpha, verify the HDD remains asleep while scrapes run. Pay
   special attention to `/mnt/hdd`, `/mnt/seagate`, and their media-portal
   automounts; update Alloy's Unix exporter filesystem exclusion if more
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
8. Check `systemctl status disk-watch.timer` on Epsilon and evaluate its
   fifteen-minute run independently of the monitoring stack. Verify the
   configured thresholds for `/persist`, and that alerts can reach Discord.
9. Measure Alloy's CPU use with `loki.secretfilter` enabled on Pi under
   typical and high journal load before deploying broadly. Reduce/filter
   inputs if needed.
10. Reboot Epsilon, confirm previous metrics, Loki log history, and Grafana
    login persist, and confirm incoming remote-write samples resume from all
    three Alloy agents. Verify the old Discord alerts still work.

**Security:** Loki and Prometheus listen on loopback. Their ingestion proxy
requires per-host credentials and WireGuard source filtering. Verify both
public-interface rejection and private authentication before activation;
**do not** set `services.prometheus.openFirewall`. The HTTP ingestion routes
rely on WireGuard for encryption between the home router and Epsilon.
Loki has no hard size quota. Monitor actual persistent volume usage and
Alloy ingestion errors before deciding whether a dedicated filesystem
budget is necessary. The Grafana `/api/health` path is intentionally
unauthenticated for fleet-health; other Grafana routes
must enforce Authelia. Treat Grafana local admin as a loopback-only recovery account.
No new automatic notifications are enabled in this phase.

## Automated verification

`nix build .#checks.x86_64-linux.monitoring-fleet --no-link` evaluates all
three host configurations, validates their actual Alloy and Loki files
with the pinned binaries, and exercises dashboard queries with Promtool.
This check runs in the required configuration CI group.

`nix build .#checks.x86_64-linux.monitoring-vm --no-link` runs an isolated
two-machine integration test. It checks authenticated ingestion, wrong and
missing credentials, private/public firewall boundaries, blocked query
routes, log redaction, metrics, excluded automounts, outage retries, and
history/credential preservation across client and server reboots. It uses
test credentials and does not connect to or activate production hosts.
Run this explicitly when changing the telemetry pipeline; it is not part
of the default CI group.

## Alternatives

Prometheus, Loki and Alloy are deliberately independent of Grafana.
Before migrating the legacy alerting system, evaluate Beszel for a simpler
all-in-one host/systemd monitoring experience and Perses for a GitOps-focused
Prometheus frontend. A move away from Grafana should not require replacing
the collectors or historical metrics/logging backends. Leave this PR as a draft until
metrics collection and frontend choice have both been evaluated.

## Parallel Grafana Cloud pilot

A Cloud pilot can run alongside Epsilon without changing its receiving services. See [Grafana Cloud parallel pilot](grafana-cloud-pilot.md) for optional Alloy routing, SOPS token setup, privacy safeguards, and Cloud-side alerts. Existing fleet and deployment alerts remain active.

## Next migration

Use Alloy's Unix exporter textfile collector for fleet-specific gauges
(job failures, backup freshness and completeness, current deploy revision,
and reboot-required state); add Blackbox Exporter for HTTP/endpoint
probes and Grafana-managed Discord notification routing. Validate all
failure/recovery paths, including when Prometheus or Epsilon itself dies,
before retiring old watcher scripts. Deployment health gates must remain
independent of the monitoring stack.
