---
type: Runbook
title: Diagnose fleet observability
description: Check Cloud ingestion, collection limits, and receiver rollback.
when: Diagnose missing telemetry, operate dashboards, or roll back the Cloud cutover.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, journald]
---

# Diagnose fleet observability

Alpha, Pi, and Epsilon send metrics and filtered host journals directly to
Grafana Cloud through Alloy. Pi runs the service probes. Epsilon redirects
[the dashboard hostname](https://metrics.repparw.com/d/fleet-overview/fleet-overview)
to Cloud, which controls sign-in. See [Cloud setup](grafana-cloud.md) for
credentials, dashboards, and notification policy.

## Check delivery

```sh
fleet debug epsilon
ssh root@epsilon 'systemctl status alloy; journalctl -u alloy --since "30 minutes ago" --no-pager'
ssh root@epsilon 'curl -fsS http://127.0.0.1:12345/metrics'
```

In Cloud, inspect fresh timestamps and writer queue/retry/drop counters:

```promql
count by (host) (node_uname_info)
up{host=~"alpha|pi|epsilon"}
prometheus_remote_storage_samples_pending{host=~"alpha|pi|epsilon"}
```

A successful write or unauthenticated Cloud `/api/health` response does not prove
end-to-end query availability. Strict deployment probes exclude Cloud reachability
so a Cloud outage cannot prevent fleet recovery. Never print credential files.

## Interpret collection limits

[Agent configuration](../../modules/aspects/monitoring.nix) defines scrape
cadence and metric/log filters. [Host collection](../../modules/aspects/monitoring-health.nix)
adds retained failures, completed backup timestamps, export status, and disk facts.

- Sleeping media retain their last mounted observation and timestamp; monitoring
  does not wake them. Btrfs unallocated chunks are distinct from total free space.
- Journal redaction recognizes credential patterns, not arbitrary private text.
  Container journals need separate collection.
- Persisted Alloy state does not guarantee replay: unsent logs can be lost when
  Alloy restarts during an outage ([Alloy #7112](https://github.com/grafana/alloy/issues/7112)).
- Verify actual active-series usage in `grafanacloud-usage` after changing labels
  or targets; the application datasource's instantaneous series count differs.

## Restore local receivers if required

Epsilon retains `/var/lib/grafana`, `/var/lib/loki`, and `/var/lib/prometheus2`
under `/persist` as inactive rollback data. Do not delete them during activation.
To restore the former topology, recover the receiver configuration and encrypted
credentials from Git, build and deploy it, then verify receivers before switching
agents. Keep Cloud writes until local ingestion works; use the normal
[rollback procedure](update-rollback.md).

## Verify configuration changes

```sh
nix build .#checks.x86_64-linux.monitoring-fleet --no-link
```

Use the [monitoring VM](../../modules/_tests/monitoring-vm.nix) for delivery,
outage, and reboot behavior against test-only receivers. Production ingestion
and notification delivery still require live verification.
