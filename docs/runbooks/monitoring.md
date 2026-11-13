---
type: Runbook
title: Diagnose fleet observability
description: Check Cloud ingestion and collection limits.
when: Diagnose missing telemetry or operate dashboards.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, journald]
---

# Diagnose fleet observability

Alpha, Pi, and Epsilon send metrics and filtered host journals directly to
Grafana Cloud through Alloy. Pi runs the service probes. Epsilon redirects
[the dashboard hostname](https://metrics.repparw.com/d/fleet-overview/fleet-overview)
to Cloud, which controls sign-in. See [Grafana Cloud operations](https://github.com/repparw/grafana#readme)
for dashboards, alerts, credentials and recovery.

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

### Cloud log allowance

The free log tier allows a fixed amount per calendar month, not a rolling
window: the meter resets at the start of each month, and bytes sent in one
month do not offset the next.

The bill counts the bytes the distributor received, which is much more than
what is stored. A repeated batch is billed on every copy even when the stored
volume barely grows, so a stored-volume query cannot show how much of the
allowance was consumed.

An exhausted allowance is not an overage charge. The distributor answers with
`ingestion rate limit exceeded for user <id> (limit: 0 bytes/sec)` and
discards the batch without billing it, and ingestion stays blocked until the
next month. Read the received rate and the billable total in Cloud before
treating missing logs as a configuration problem.

### Recover a stuck write-ahead log

A full filesystem truncates Alloy's write-ahead log mid-record. On the next
start the reader can re-read the same segment over and over, and every retry
is billed again. The symptom is `loki_write_sent_bytes_total` climbing far
above the journal volume while `loki_write_batch_retries_total` grows, plus a
reader error in the Alloy journal:

```sh
journalctl -u alloy --since "1 hour ago" --no-pager | grep -i "error tailing WAL"
```

Stop the amplification before touching the log, because every retry costs
allowance:

```sh
systemctl stop alloy
df -h /persist          # Pi's card; free the space that truncated the log
ls -l /var/lib/private/alloy/data-path/loki.write.cloud/wal/
rm -rf /var/lib/private/alloy/data-path/loki.write.cloud/wal
systemctl start alloy
```

Removing the WAL discards the logs it held. That is the cheaper trade than
re-sending them, and the freed disk space is the reason to do it.

## Verify configuration changes

```sh
nix build .#checks.x86_64-linux.monitoring-fleet --no-link
```

Use the [monitoring VM](../../modules/_tests/monitoring-vm.nix) for delivery,
outage, and reboot behavior against test-only receivers. Production ingestion
and notification delivery still require live verification.
