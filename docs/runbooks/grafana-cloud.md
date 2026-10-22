---
type: Runbook
title: Grafana Cloud setup and alerting
description: Configure Cloud credentials, dashboards, and independent alerts.
when: Configure Cloud collection, rotate credentials, or change alerts.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, alerting]
---

# Grafana Cloud setup and alerting

Grafana Cloud is the fleet's metrics and log backend. See [Fleet observability](monitoring.md) for collection, diagnostics and rollback.

## Stack and credentials

- Stack: `https://repparw.grafana.net`, with Cloud Portal sign-in and restricted membership.
- Metrics: `https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push`, instance ID `3689389`.
- Logs: `https://logs-prod-024.grafana.net/loki/api/v1/push`, instance ID `1840359`.
- Tokens: one per host, scoped to `metrics:write` and `logs:write`, encrypted in `secrets/grafana-cloud-<host>.sops.yaml`. The `.sops.yaml` rules select the consuming host and recovery recipients. Rotate through SOPS; never place tokens in Nix expressions or generated files.

`den.aspects.monitoring._.cloud` configures both destinations and the SOPS credential. The agent supports enabling either signal independently; at least one destination is required. Runtime credentials are delivered through systemd `LoadCredential`. Cloud HTTPS and private credential paths are checked before activation.

The dashboard source is `modules/aspects/monitoring/fleet-overview.json`. When importing into Cloud, replace datasource UIDs `fleet-prom` and `fleet-loki` with the stack's actual UIDs (`grafanacloud-prom` and `grafanacloud-logs`). Dashboard UID `fleet-overview` preserves existing bookmarks. Keep the exported JSON free of tokens.

## Independent Cloud alerts

The Cloud stack has one independent Discord contact point, **Grafana Cloud Alerts**, posting to `#notifications` through its own webhook. The webhook URL is a runtime secret: do not commit it, and rotate it if it is exposed. Keep `disableResolveMessage: false` so recovery notifications are sent. The contact point shares the channel with workflow notifications, including deployment reports.

Grafana's Discord notifier sends a new message on resolution; it cannot delete the original firing message. The contact point keeps that built-in behavior. A self-cleaning relay that stores the Discord message ID per alert fingerprint would be required if firing messages must disappear on resolution.

A notification policy route sends alerts labeled `pilot=grafana-cloud` to that contact point. The route uses `group_by: ["host"]`, a 10s group wait, a 1m group interval, and a 4h repeat interval.

Use [the native Discord template](../../modules/aspects/monitoring/discord.tmpl) as the Grafana notification template `fleet.discord`. Set the contact point title to `{{ template "fleet.discord.title" . }}`, its message to `{{ template "fleet.discord.message" . }}`, and enable embed description (`use_embed_description`).

The message contains the host, condition, useful value and one dashboard link. It omits raw labels, expression references and silence URLs. Each rule supplies a `brief` firing annotation and a `recovery` annotation, with `summary` as a fallback. Disk rules retain the numeric percentage in query D and the configured limit in E; their brief/recovery annotations use those values. Query A evaluates the policy, B reduces it, and C checks `$B > 0`. Preview firing, resolved, missing-host and datasource-error cases using Grafana's native template preview before changing the contact point.

Two Grafana-managed host-absence rules exist in folder **Fleet Cloud Pilot**, group **fleet-cloud-pilot**:

- **Epsilon:** `absent_over_time(node_uname_info{host="epsilon"}[10m]) or on() vector(0)`
- **Pi:** `absent_over_time(node_uname_info{host="pi"}[10m]) or on() vector(0)`

Both absence rules are enabled after verifying fresh samples. The zero fallback represents healthy telemetry explicitly, so an empty healthy result cannot trigger the rule's No Data policy. Alpha deliberately shuts down; add an Alpha rule only after defining its expected uptime schedule or explicit maintenance suppression.

The firing/resolved path was validated with a temporary synthetic rule (`fleet_cloud_probe{test="delivery"}`), which was deleted after a Firing and a Resolved notification were observed. Re-run that check after changing the contact point or notification policy.

Disk, host-absence and series-budget rules use **Keep Last State** for both evaluation errors and No Data. A Cloud query timeout cannot establish a disk threshold violation or host outage. Using Alerting for these errors previously caused false firing/resolved messages across filesystem instances.

A separate **Cloud metrics query availability** rule queries `vector(0)` and uses Grafana's **Error** and **No Data** states. Route its `DatasourceError` and `DatasourceNoData` alerts to Discord using `rulename="Cloud metrics query availability"`, grouped by `datasource_uid`, with a 2m group wait and 4h repeat interval. These notifications report that monitoring is unavailable. Use `fleet health probe` and local journals to inspect the fleet while Cloud cannot evaluate queries. Periodic health notifications depend on Cloud availability.

The health policy manifest is
[`health-alerts.json`](../../modules/aspects/monitoring/health-alerts.json).
It covers failed jobs/services, stopped required units, HTTP probe failure or
absence, per-host disk thresholds, missing required filesystems, Btrfs allocation
pressure, overdue offsite backups, incomplete native exports, Alpha's reboot
requirement, Pi's deployment PAUSE and stale collectors. Disk thresholds come
from each host's `modules.monitoring.health.disks`; Epsilon monitors its shared
physical filesystem once at `/persist` with 70/85 percent thresholds. Sleeping
Alpha disks retain their last mounted observation without being accessed.

Backup freshness requires a successful whole offsite job within 30 hours.
Initial installation allows 30 hours for the first recorded success; failed-job
and incomplete-export rules remain independent during that interval. Export
preparation alone never advances the success timestamp.

The series-budget rule uses `sum(grafanacloud_instance_active_series)` from
`grafanacloud-usage`, warning at 9,000 against the 10,000 series allowance.
Instantaneous counts from the application metrics datasource do not represent
the Cloud activity window. Probe metrics and systemd states are filtered before
upload; keep the scrape interval at 60 seconds and verify actual usage after
adding targets or labels.

Cloud Synthetic Monitoring can probe a public HTTPS service independently of Epsilon. Cloud's unauthenticated `/api/health` checks frontend reachability, **not end-to-end ingestion**.

The repository provisions encrypted per-host write tokens in `secrets/grafana-cloud-*.sops.yaml`. The Cloud account, access policies, Discord webhook/contact point, notification policy, dashboards, and alert rules are created manually in the Cloud Portal/UI and are not managed by this Nix module. Deployment readiness checks remain local and independent of Cloud.

References: [Alloy remote write](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.remote_write/), [Alloy Loki write](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/), [Cloud Access Policies](https://grafana.com/docs/grafana-cloud/platform/security-and-account-management/security-and-access/authentication-and-permissions/access-policies/), [Cloud alert notifications](https://grafana.com/docs/grafana-cloud/observe-and-act/alert-and-measure-reliability/alerting/configure-notifications/manage-contact-points/).
