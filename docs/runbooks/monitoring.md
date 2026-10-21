---
type: Runbook
title: Fleet observability with Grafana Cloud
description: Operate Cloud metrics, filtered host journals, and independent fleet checks.
when: Diagnose missing telemetry, operate dashboards, or roll back the Cloud cutover.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, journald]
---

# Fleet observability

Alpha, Pi and Epsilon run Alloy and send directly to Grafana Cloud. Epsilon no longer runs Prometheus, Loki or Grafana, and no host sends telemetry to Epsilon. Cloud owns periodic health alerts. Read-only deployment readiness checks and workflow-specific notifications remain independent.

## Collection

The default agent aspect collects Unix exporter metrics and host journald. Each host includes the Cloud credential aspect; Pi and Epsilon also include the persistence aspect so Alloy's state files survive their tmpfs-root reboots. File persistence alone does not establish that every unsent sample or log entry will replay after restart.

- Node and Alloy self-metrics are scraped every 60 seconds. Node exporter supplies the job label `integrations/unix`; Alloy self-metrics use `alloy`.
- Systemd state metrics retain active and failed states. Inactive and transitional variants are dropped before upload to reserve the Free series allowance for health checks.
- Alloy self-metrics omit histogram buckets to reduce cardinality. Queue, failure, retry, count and sum metrics remain available. Host metrics are unaffected.
- Alpha excludes sleeping media mountpoints from filesystem collection so monitoring does not wake disks.
- Host journals pass through native `loki.secretfilter` before upload. Recognized credentials are redacted; arbitrary private content is not. Container journals require separate collection.
- Metrics and logs have their own write-ahead logs. Logs retry indefinitely through transient failures. Buffering is finite and cannot guarantee delivery through an unlimited outage. Alloy also has a [known log WAL replay gap](https://github.com/grafana/alloy/issues/7112): unsent entries in an already-marked open segment can be skipped after a restart during an outage. Persisting the directory does not fix this. Do not claim lossless log delivery across that combination of failures.
- Host-scoped write-only tokens come from `secrets/grafana-cloud-<host>.sops.yaml` through systemd credentials. Neither tokens nor ingestion passwords appear in generated configuration.

## Dashboard and health checks

The health migration uses Alloy's native blackbox exporter on Pi, generated
from the service registry. Probes do not follow login redirects. Only success,
duration, HTTP status, certificate expiry and scrape availability are uploaded.
Host facts are published atomically through the existing Unix textfile collector:
required units, retained job failures, completed backup timestamps, export status,
deployment pause and booted versus staged kernel state. Disk facts update every
15 minutes and preserve each host's configured warning and critical thresholds.
Unmounted media are never accessed; their last observation is retained with its
timestamp. Btrfs pressure uses filesystem allocation statistics, not device slack.

`modules/aspects/monitoring/health-alerts.json` records the Cloud health rules.
Each host owns its disk thresholds through `modules.monitoring.health.disks`.
The former periodic Discord health, disk and reboot senders have been removed.
Deployment readiness, rollback, Hermes crash analysis and catalog/release notices
remain separate operational workflows. A backup timestamp is written only after
the entire job succeeds; export preparation alone is insufficient. Initial backup
freshness monitoring allows 30 hours for the first confirmed scheduled success.
Failed jobs and incomplete exports remain independently detectable during that
initial interval.

CPU used is the non-idle share of total accounted CPU time over five minutes.
Pi has reported more idle seconds than elapsed time directly in `/proc/stat`,
which made the previous `100 * (1 - idle rate)` query negative. Normalizing by
the total counter rate avoids that wall-clock assumption; it does not repair
the kernel's accounting. The query selects the Unix collector job so unrelated
CPU series cannot distort the result.

Open [Fleet overview](https://metrics.repparw.com/d/fleet-overview/fleet-overview). Epsilon's Traefik preserves the hostname as a reversible 302 to `https://repparw.grafana.net`, including bookmark paths and queries. Grafana Cloud controls sign-in and membership. There is no local Grafana health exception; `/api/health` redirects to Cloud too.

Glance probes Cloud's unauthenticated `/api/health` directly. The read-only fleet health probe also checks that endpoint, but strict deployment readiness and local-only probes exclude it. A Cloud outage must not prevent fleet recovery. This endpoint proves frontend health, not telemetry ingestion.

Use these Cloud Prometheus queries to check ingestion:

```promql
count by (host) (node_uname_info)
up{host=~"alpha|pi|epsilon"}
count({host=~"alpha|pi|epsilon"})
prometheus_remote_storage_samples_pending{host=~"alpha|pi|epsilon"}
```

Expected hosts are Alpha, Pi and Epsilon. Inspect the timestamp of the most recent sample, not just an old chart. The Free series allowance has limited headroom; the Cloud budget alert fires at 9,000 active series, using the Cloud usage datasource. See [Cloud setup and alerting](grafana-cloud-pilot.md).

For local delivery diagnostics:

```bash
fleet commands --json
fleet debug epsilon
ssh root@epsilon 'systemctl status alloy; journalctl -u alloy --since "30 minutes ago" --no-pager'
ssh root@epsilon 'curl -fsS http://127.0.0.1:12345/metrics'
```

Inspect Cloud writer queue depth, highest sent timestamp, retry/failure counters and dropped log entries. A successful HTTP write does not prove queries or dashboards are available. Never print runtime credential files.

## Retained Epsilon history and rollback

The old `/var/lib/grafana`, `/var/lib/loki` and `/var/lib/prometheus2` bind mounts remain backed by `/persist`. Their existing contents and ownership are retained; no service writes to them. Do not delete them as part of activation. This is a temporary rollback reserve, not a second monitoring backend or a new offsite backup.

To restore the previous topology, revert the Cloud-only cleanup and build/deploy the previous configuration to Epsilon and the agents. The Git history retains the encrypted ingestion credentials and receiver definitions. Restore the receivers before switching agents back; keep Cloud writes active until local ingestion is verified. The existing deployment rollback procedure remains available.

## Verification

`nix build .#checks.x86_64-linux.monitoring-fleet --no-link` validates generated Alloy configuration, Cloud-only host topology, credentials, redirect and retained data mounts. The monitoring VM exercises an isolated HTTPS Cloud fixture: authenticated ingestion, redaction, excluded automounts, histogram filtering, normal outage recovery, and agent-state plus uploaded-telemetry availability after a reboot. The fixture's Prometheus/Loki receivers are test-only.
