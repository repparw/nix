---
type: Runbook
title: Configure Grafana Cloud
description: Maintain Cloud credentials, dashboards, alert policy, and Discord delivery.
when: Configure Cloud collection, rotate credentials, or change alerts.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, alerting]
---

# Configure Grafana Cloud

Stack: `https://repparw.grafana.net`. Cloud resources are maintained manually;
Nix provisions the agents and encrypted per-host write credentials.
See [monitoring diagnostics](monitoring.md) for ingestion checks and rollback.

## Credentials and dashboard

Rotate `secrets/grafana-cloud-<host>.sops.yaml` through SOPS. Tokens require
`metrics:write` and `logs:write`; agents receive them through systemd credentials.
Endpoint settings live in [monitoring.nix](../../modules/aspects/monitoring.nix).
Never commit tokens or the Discord webhook.

Import [fleet-overview.json](../../modules/aspects/monitoring/fleet-overview.json)
with datasource UIDs `fleet-prom` → `grafanacloud-prom` and
`fleet-loki` → `grafanacloud-logs`. Preserve dashboard UID `fleet-overview`.
Cloud usage queries use `grafanacloud-usage`.

## Maintain alert policy

[health-alerts.json](../../modules/aspects/monitoring/health-alerts.json) records
the health rules. Disk thresholds belong to each host's
`modules.monitoring.health.disks`. Export preparation alone cannot establish a
successful offsite backup. Host absence applies to Pi and Epsilon; Alpha can
shut down intentionally and needs an uptime policy before enabling that alert.
For each always-on host, use
`absent_over_time(node_uname_info{host="<host>"}[10m]) or on() vector(0)`.
The zero fallback explicitly represents healthy telemetry.

Keep ordinary health rules at **Keep Last State** for evaluation errors and
No Data. The separate **Cloud metrics query availability** rule uses `vector(0)`
with **Error** and **No Data** states to report monitoring failures. Route its
`DatasourceError` and `DatasourceNoData` alerts using
`rulename="Cloud metrics query availability"`, grouped by `datasource_uid`, with
a 2m wait and 4h repeat. Query failure must not masquerade as host or disk failure.

The series budget uses `sum(grafanacloud_instance_active_series)` from the usage
datasource, warning at 9,000 against the 10,000 allowance. Verify headroom after
changing collection. The rule folder/group retain the names **Fleet Cloud Pilot**
and **fleet-cloud-pilot**.

## Maintain Discord delivery

The **Grafana Cloud Alerts** contact point uses its own webhook to
`#notifications`. Its route matches `pilot=grafana-cloud`, groups by `host`,
waits 10s, groups updates at 1m, and repeats at 4h.

Install [discord.tmpl](../../modules/aspects/monitoring/discord.tmpl) as
`fleet.discord`. Set title to `{{ template "fleet.discord.title" . }}` and message
to `{{ template "fleet.discord.message" . }}`. Enable `use_embed_description` and
keep `disableResolveMessage: false`. Grafana sends a separate recovery message;
it does not delete the firing message. Rules supply `brief` and `recovery`
annotations; disk values and thresholds use queries D and E.

Preview firing, recovery, missing-host, and datasource-error notifications before
changing delivery. Then verify an actual temporary alert fires and resolves in
Discord, and remove the fixture afterward. A successful preview alone does not
prove delivery.
