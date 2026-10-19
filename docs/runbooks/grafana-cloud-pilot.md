---
type: Runbook
title: Grafana Cloud parallel monitoring pilot
description: Mirror Alloy metrics/logs to Grafana Cloud while retaining Epsilon.
when: Start a cloud pilot or configure independent Cloud alerts.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana, cloud, alloy, alerting]
---

# Parallel Grafana Cloud pilot

**Opt-in per host and signal.** Without `modules.monitoring.agent.cloud.metrics` or `logs`, Epsilon's existing Prometheus, Loki, Grafana, ingestion proxy, SOPS credentials, and alerting are unchanged. Cloud targets use separate Alloy writers. **Neither Cloud target is enabled by merging the PR.**

## Prerequisites

1. Create a Grafana Cloud Free stack. Obtain the **exact metrics remote-write URL / instance ID**, and optionally the **Loki push URL / instance ID**, from the Cloud Portal. No endpoints/IDs are guessed.
2. Generate narrowly scoped Cloud Access Policy tokens (`metrics:write` for metrics, `logs:write` for logs); use separate or host-scoped tokens where practical.
3. Encrypt each host's token with the existing SOPS workflow and reference its runtime path using `config.sops.secrets.<name>.path`. Use the correct host's `.sops.yaml` recipients. **Never embed actual tokens in Nix expressions, the generated Alloy config or CI.**
4. Enable the metrics mirror first, on Epsilon only. Example of a host NixOS module *after* provisioning its encrypted SOPS file:

```nix
sops.secrets.grafana-cloud-metrics-token = {
  sopsFile = ../../secrets/grafana-cloud-epsilon.sops.yaml;
  key = "metricsToken";
  restartUnits = [ "alloy.service" ];
};
modules.monitoring.agent.cloud.metrics = {
  url = "https://prometheus-<stack>.grafana.net/api/prom/push";
  username = "<metrics-instance-id>";
  tokenFile = config.sops.secrets.grafana-cloud-metrics-token.path;
};
```

The URLs and instance IDs above are **placeholders**. The module requires HTTPS and delivers the token to Alloy through systemd `LoadCredential`; the generated Alloy file references the credential file path, not its contents.

Optional logs (provision a separate SOPS token first):

```nix
modules.monitoring.agent.cloud.logs = {
  url = "https://logs-<region>.grafana.net/loki/api/v1/push";
  username = "<logs-instance-id>";
  tokenFile = config.sops.secrets.grafana-cloud-logs-token.path;
};
```

**Logs remain disabled until reviewed.** Our `loki.secretfilter` is best-effort and host journald can include private data. If desired, introduce Cloud-specific filtering before enabling this writer.

## Safe deployment and verification

1. Keep Epsilon's receivers and all current fleet-health, disk-watch, backup, deploy readiness and Discord alerts. Deploy Cloud **metrics** to Epsilon alone, and confirm Cloud Explore has recent `node_uname_info{host="epsilon"}` samples. Confirm local Epsilon Prometheus still ingests normally.
2. Add Pi, then Alpha. Verify three host labels in Cloud, compare dashboards, watch Cloud active-series/DPM usage, and ensure no authentication/429 errors in `journalctl -u alloy`. Initial scrapes remain 30s so measurements are comparable; later adjust the Cloud path without silently changing local sampling.
3. Run an intentional Cloud write failure or credential rejection test; the Epsilon writer must remain healthy. Separately test missing host telemetry without disabling existing fleet checks.
4. Only after a privacy review, optionally add logs host by host. Compare log usage/retention and ensure failures at the Cloud writer do not prevent local Loki ingestion.
5. Revert by setting `modules.monitoring.agent.cloud.metrics` and/or `logs` to `null`. Do not remove Epsilon backend until independent alert parity has been demonstrated.

## Independent Cloud alerts

Configure these **in the Cloud Grafana UI** (not created by this Nix module). In Alerting → Notification configuration, add a *Discord* contact point using a Discord channel webhook. Send a test, retain recovery/resolved notifications, and route the pilot to a dedicated channel to avoid duplicate production alerts.

Start with three independent Grafana-managed host-absence rules, evaluated every minute:

- **Epsilon:** `absent_over_time(node_uname_info{host="epsilon"}[10m])`
- **Pi:** `absent_over_time(node_uname_info{host="pi"}[10m])`
- **Alpha:** `absent_over_time(node_uname_info{host="alpha"}[10m])` (account for intentionally sleeping desktop)

Configure explicit No Data and Error behavior and test both firing and resolution. For disk alerts, evaluate `100 * (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes)` after excluding pseudo and ephemeral mounts; start with 70% warning and 85% critical sustained for several minutes. Consider systemd failed-unit and backup freshness alerts after the corresponding metrics are verified.

Cloud Synthetic Monitoring can probe a public HTTPS service independently of Epsilon. Note that `metrics.repparw.com/api/health` is intentionally unauthenticated and checks frontend reachability, **not end-to-end ingestion**.

This PR does **not** provision a Cloud account, tokens, Grafana service-account alert-management credentials, Discord webhook, or remote alert objects. Those require Cloud onboarding. Existing monitoring remains the source of truth until the pilot is validated.

References: [Alloy remote write](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.remote_write/), [Alloy Loki write](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.write/), [Cloud Access Policies](https://grafana.com/docs/grafana-cloud/platform/security-and-account-management/security-and-access/authentication-and-permissions/access-policies/), [Cloud alert notifications](https://grafana.com/docs/grafana-cloud/observe-and-act/alert-and-measure-reliability/alerting/configure-notifications/manage-contact-points/).
