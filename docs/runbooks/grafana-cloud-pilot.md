---
type: Runbook
title: Grafana Cloud parallel monitoring pilot
description: Mirror Alloy metrics/logs to Grafana Cloud while retaining Epsilon.
when: Start a cloud pilot or configure independent Cloud alerts.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, alerting]
---

# Parallel Grafana Cloud pilot

Grafana Cloud Free is the intended permanent backend after the pilot passes. Keep Epsilon's stack in place throughout validation; retire it only in a separate, evidence-backed cleanup PR.

**Opt-in per host and signal.** Without `modules.monitoring.agent.cloud.metrics` or `logs`, Epsilon's existing Prometheus, Loki, Grafana, ingestion proxy, SOPS credentials, and alerting are unchanged. Cloud targets use separate Alloy writers. The `den.aspects.monitoring._.cloud` aspect enables Cloud **metrics** for Alpha, Pi and Epsilon; Cloud **logs** remain disabled until the journald sensitivity review is complete.

## Prerequisites

1. The Grafana Cloud Free stack is `repparw` with these ingestion endpoints:
   - Metrics: `https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push`, instance ID `3689389`.
   - Logs: `https://logs-prod-024.grafana.net/loki/api/v1/push`, instance ID `1840359`.
2. Each host has its own Cloud Access Policy token carrying `metrics:write` and `logs:write`. Host-scoped policies allow isolated revocation.
3. Encrypt each host's token with the existing SOPS workflow in `secrets/grafana-cloud-<host>.sops.yaml` under the `token` key. The matching `.sops.yaml` rules select that host and recovery recipients only. **Never embed actual tokens in Nix expressions, the generated Alloy config or CI.**
4. `den.aspects.monitoring._.cloud` defines the runtime credential and enables the metrics mirror on hosts that include it:

```nix
den.aspects.monitoring.provides.cloud.nixos = { config, lib, ... }: {
  sops.secrets.grafana-cloud-write-token = {
    sopsFile = ../../secrets + "/grafana-cloud-${config.networking.hostName}.sops.yaml";
    key = "token";
    restartUnits = [ "alloy.service" ];
  };
  modules.monitoring.agent.cloud.metrics = lib.mkDefault {
    url = "https://prometheus-prod-40-prod-sa-east-1.grafana.net/api/prom/push";
    username = "3689389";
    tokenFile = config.sops.secrets.grafana-cloud-write-token.path;
  };
};
```

The module requires HTTPS and delivers the token to Alloy through systemd `LoadCredential`; the generated Alloy file references the credential file path, not its contents. The aspect is included by Alpha, Pi and Epsilon, but activation remains staged: Epsilon first.

Optional logs (keep disabled until the journald sensitivity review is complete):

```nix
modules.monitoring.agent.cloud.logs = {
  url = "https://logs-prod-024.grafana.net/loki/api/v1/push";
  username = "1840359";
  tokenFile = config.sops.secrets.grafana-cloud-write-token.path;
};
```

Cloud logs use the existing native `loki.secretfilter` pipeline before either destination receives entries. Redaction covers known credential patterns; it does not remove arbitrary private message content.

## Safe deployment and verification

1. Keep Epsilon's receivers and all current fleet-health, disk-watch, backup, deploy readiness and Discord alerts. The module configures Cloud **metrics** on all three hosts, but activate Epsilon first and confirm Cloud Explore has recent `node_uname_info{host="epsilon"}` samples. Confirm local Epsilon Prometheus still ingests normally.
2. Add Pi, then Alpha. Verify three host labels in Cloud, compare dashboards, watch Cloud active-series/DPM usage, and ensure no authentication/429 errors in `journalctl -u alloy`. Cloud scrapes run every 60s while local scrapes remain at 30s. The separate scrape jobs preserve the same `node` and `alloy` job labels in both backends.
3. Run an intentional Cloud write failure or credential rejection test; the Epsilon writer must remain healthy. Separately test missing host telemetry without disabling existing fleet checks.
4. Add logs host by host using native secret redaction. Compare log usage/retention and ensure failures at the Cloud writer do not prevent local Loki ingestion.
5. Revert by setting `modules.monitoring.agent.cloud.metrics` and/or `logs` to `null`. Do not remove Epsilon backend until independent alert parity has been demonstrated.

The repository checks exercise metrics-only, logs-only, and combined Cloud configuration with the pinned Alloy validator. The monitoring VM uses unreachable HTTPS fixtures to check separate buffers and continued Epsilon ingestion, plus HTTPS redirect/bookmark behavior and the local health exception. The encrypted per-host tokens are validated separately with a live write probe; the checks do not establish delivery, quotas, dashboard access, or alert notifications.

Import `modules/aspects/monitoring/fleet-overview.json` into the Cloud stack after ingestion works. Before import, replace every Prometheus datasource UID `fleet-prom` with the actual Cloud Prometheus datasource UID from the stack's Connections page. If Cloud logs are enabled, replace `fleet-loki` with the actual Cloud Loki datasource UID. Keep the local dashboard file unchanged. Confirm each host and panel in Cloud, and record the dashboard URL in the rollout evidence.

Record the observed active series and samples per minute in Cloud's usage view against the account's actual Free limits. Compare those with local `prometheus_remote_storage_*` counters and Cloud HTTP 401/429 responses before expanding to another host. Keep the independent Cloud scrape jobs at 60s and the local jobs at 30s during this comparison.

## Independent Cloud alerts

The Cloud stack has one independent Discord contact point, **Grafana Cloud Alerts**, posting to `#notifications` through its own webhook. The webhook URL is a runtime secret: do not commit it, and rotate it if it is exposed. Keep `disableResolveMessage: false` so recovery notifications are sent. The contact point shares the channel with fleet-health messages but not the delivery path.

Grafana's Discord notifier sends a new message on resolution; it cannot delete the original firing message. The pilot intentionally keeps that built-in behavior. A self-cleaning relay that stores the Discord message ID per alert fingerprint would be required if firing messages must disappear on resolution.

A notification policy route sends alerts labeled `pilot=grafana-cloud` to that contact point. The route uses `group_by: ["host"]`, a 10s group wait, a 1m group interval, and a 4h repeat interval.

Two Grafana-managed host-absence rules exist in folder **Fleet Cloud Pilot**, group **fleet-cloud-pilot**:

- **Epsilon:** `absent_over_time(node_uname_info{host="epsilon"}[10m])`
- **Pi:** `absent_over_time(node_uname_info{host="pi"}[10m])`

Both rules are **paused** until the corresponding host is activated, because absence is expected before the first Cloud sample arrives. Do not unpause a rule before its host is live. Alpha deliberately shuts down; add an Alpha rule only after defining its expected uptime schedule or explicit maintenance suppression.

The firing/resolved path was validated with a temporary synthetic rule (`fleet_cloud_probe{test="delivery"}`), which was deleted after a Firing and a Resolved notification were observed. Re-run that check after changing the contact point or notification policy.

Configure explicit No Data and Error behavior and test both firing and resolution. For disk alerts, evaluate `100 * (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes)` after excluding pseudo and ephemeral mounts; start with 70% warning and 85% critical sustained for several minutes. Consider systemd failed-unit and backup freshness alerts after the corresponding metrics are verified.

Cloud Synthetic Monitoring can probe a public HTTPS service independently of Epsilon. Note that `metrics.repparw.com/api/health` is intentionally unauthenticated and checks frontend reachability, **not end-to-end ingestion**.

The repository provisions encrypted per-host write tokens in `secrets/grafana-cloud-*.sops.yaml`. The Cloud account, access policies, Discord webhook/contact point, notification policy, dashboards, and alert rules are created manually in the Cloud Portal/UI and are not managed by this Nix module. Existing monitoring remains the source of truth until the pilot is validated.

References: [Alloy remote write](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.remote_write/), [Alloy Loki write](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/), [Cloud Access Policies](https://grafana.com/docs/grafana-cloud/platform/security-and-account-management/security-and-access/authentication-and-permissions/access-policies/), [Cloud alert notifications](https://grafana.com/docs/grafana-cloud/observe-and-act/alert-and-measure-reliability/alerting/configure-notifications/manage-contact-points/).

## metrics.repparw.com redirect after validation

A redirect is _not_ a custom Grafana Cloud domain: users opening `https://metrics.repparw.com` receive a 302 to the real Cloud stack URL, and the browser then uses that `*.grafana.net` hostname. Use the **default Grafana Cloud Portal login** at the Cloud stack: it already supports GitHub/Google social sign-in for Cloud Portal members, without separate stack-level OAuth client configuration. Do not add Authelia at the redirect layer; it does not protect users arriving at the Cloud URL directly. Keep Cloud stack membership and permissions restricted. A publicly reachable redirect does **not** enable anonymous Grafana access.

**Default:** `modules.monitoring.server.cloudRedirectUrl = null;` — the existing local Grafana remains reachable through Authelia. Once access, metrics, dashboards, cloud-side alerts, firing/resolution, and external outage detection are verified, opt into the redirect on Epsilon. Logs can be enabled independently with their own token:

```nix
modules.monitoring.server.cloudRedirectUrl = "https://<stack>.grafana.net";
```

Replace the placeholder with the actual Cloud stack HTTPS origin, not an ingestion endpoint. This is a reversible **302**, not a permanent 301. Traefik preserves the request path and query. The unauthenticated Epsilon-local `/api/health` route stays in place for existing fleet-health checks; it is **not** evidence Cloud is healthy. Test root and bookmarked URLs as well as `/api/health` before considering cutover complete.

The Epsilon backend is intended to be **retired** if Cloud meets requirements. In a separate cleanup PR, remove Prometheus, Loki, Grafana, their private ingestion proxy, obsolete secrets and persistence binds. Retain fleet Alloy collection; migrate any local health checks before dropping local Grafana; simplify the URL redirect once it no longer belongs to the Epsilon monitoring server aspect. Deployment readiness checks should remain independent of Cloud.
