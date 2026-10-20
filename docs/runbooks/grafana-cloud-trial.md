---
type: Runbook
title: Grafana Cloud parallel ingestion trial
description: Opt in Alloy hosts to Grafana Cloud while retaining Epsilon as the original receiver and Grafana instance.
when: After creating a Grafana Cloud Free stack, before enabling Cloud for any NixOS host.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana-cloud, alloy, sops, alerts]
---

# Grafana Cloud parallel trial

## Goal and exit condition

During evaluation, **both** Grafana Cloud and Epsilon ingest metrics and host
journald logs directly from each host's single Alloy process. The existing
Epsilon services, dashboard, alerts, and deployment gates remain unchanged.
**Epsilon's Grafana/Prometheus/Loki stack is temporary**: remove it after Cloud
demonstrates data completeness, acceptable usage, useful dashboards, reliable
off-site alerting (including Epsilon down), recovery, and tolerable retention.
Keep Epsilon itself, its Alloy agent, and independent deployment/health gates.

This PR **does not** activate Cloud, contact external services, or require
secret material to build Nix configurations. It introduces opt-in destinations,
a per-host credentials aspect, and SOPS creation rules.

## Prerequisites (local setup agent)

1. Create a Grafana Cloud Free stack. Copy, without guessing, its **Prometheus
   remote-write URL and username/instance ID** and its **Loki push URL and
   username/instance ID**. Cloud endpoints may use different usernames.
2. Create Cloud Access Policy token(s), ideally one per host, with **only**
   `metrics:write` and `logs:write`, scoped to the intended stack. Do not
   grant admin/query permissions or put tokens in the repo, a URL, Nix option,
   GitHub issue, chat, shell history, or CLI arguments.
3. For each of `alpha`, `pi`, and `epsilon`, create
   `secrets/grafana-cloud-<host>.sops.yaml` containing the encrypted YAML
   key `token`. SOPS recipients are defined in `.sops.yaml` for each host
   and the existing recovery identity. Verify decryption only on the intended
   host. Prefer an editor-based SOPS flow that avoids writing a plaintext
   token to disk. A single token can be shared if the plan restricts tokens,
   but separate per-host tokens simplify incident response.

## Activate host by host

After the **target host's encrypted file** is present, opt that host into the
`monitoring._.cloud-credentials` aspect. This aspect is deliberately not in
fleet defaults yet; doing so before the secret files exist would break eval.

If Cloud URLs and usernames are shared across the fleet, keep these _public_
configuration values in a common NixOS declaration (for example, alongside
other `den.default.nixos` settings), not in SOPS:

```nix
modules.monitoring.agent.cloud = {
  metricsUrl = "https://<actual-prometheus-remote-write-endpoint>";
  metricsUsername = "<actual-prometheus-instance-id>";
  logsUrl = "https://<actual-loki-push-endpoint>";
  logsUsername = "<actual-loki-instance-id>";
};
```

The host-specific aspect sets `cloud.enable = true` and `cloud.tokenFile`
from `sops.secrets.grafana-cloud-token.path`. Include the aspect on one host
first to prove ingestion, then roll it out to the other two. If you prefer a
single fleet-wide include, do it only **after** all secrets and values have
been installed and validated. Epsilon's own Cloud telemetry is sent via
HTTPS independently of its local Prometheus/Loki servers.

The local `node` and `alloy` scrapes remain at **30s**. Separate Cloud
scrapes use **60s** to reduce billed data-points-per-minute. The same
`loki.secretfilter` output fans out to both Loki receivers; secret masking
is best-effort and not sufficient for arbitrary sensitive journal data.

### Validate

Before deploying, evaluate and validate Alloy using:

```sh
nix build .#checks.x86_64-linux.monitoring-fleet --no-link
nix build .#checks.x86_64-linux.monitoring-vm --no-link
```

The first check covers the Cloud opt-in configuration with dummy URLs/token
paths. The VM check protects the original Epsilon ingestion path. Neither
contacts Grafana Cloud. Follow existing deploy procedures, starting with one
host. On that host, confirm `alloy.service` is active and its generated
config contains both `remote_write` and both Loki write blocks.

On Cloud, check the newest `node_uname_info{host="<host>"}` and
`up{job="alloy",host="<host>"}` samples, the textfile gauges, and
`{source="journald",host="<host>"}` logs. Confirm they match local Grafana
and persist after Pi reboot. Measure Cloud active-series usage and log bytes
over several days, including noisy periods and outages. Check cloud write
errors, dropped data and rate-limit responses on Alloy.

**Rollback:** remove the host's `monitoring._.cloud-credentials` include
and redeploy. Epsilon's ingestion is not dependent on Cloud.

## Alerts during the trial

Grafana Git Sync manages dashboards and folders only. It does not manage
alert rules, data sources, or contact points. Do not couple alert management
to dashboard Git Sync. Same Grafana-managed alert rules can be configured on both instances:
evaluate against the local Prometheus/Loki datasource on Epsilon and the Cloud
datasource on Cloud. Configure separate Discord contact points; duplicate
notifications are acceptable during the evaluation. Test explicit FIRING and
RESOLVED notifications from both.

Initially trial a per-host no-telemetry rule and a high-disk-usage rule on
both. Include Epsilon's no-telemetry alert on Cloud: if Epsilon dies, its
local Grafana alert evaluator also dies. Keep existing disk-watch,
fleet-health, backup/reboot-watch, Discord and deploy-rs safety checks
until alert parity and recovery paths are proven.

For reproducible alerts later, use Grafana alert provisioning APIs or the
Grafana Terraform provider. Use shared rule definitions parameterized by
instance-specific datasource UIDs and credentials. Manage API
tokens through a secret mechanism; alerting Terraform state must be kept
private. If Cloud becomes the sole backend, discontinue local alert
provisioning instead of maintaining permanent duplication.

## Dashboards and cleanup

Keep the existing file-provisioned Fleet Overview dashboard on Epsilon during
the trial; deleting it now would break the comparison. Create or edit a Cloud
dashboard directly in its UI and set up Grafana's native Git Sync separately.
Git Sync requires user-level Git access and manages dashboards/folders only.
Avoid Git Sync from both Grafana instances writing to the same resources
without a defined ownership strategy.

If Cloud satisfies the exit conditions, follow with a separate cleanup PR:

- Remove Epsilon's Grafana, Loki, Prometheus, ingestion proxy/firewall rules,
  receiver password files, extra persistence mounts and provisioning.
- Remove `modules/aspects/monitoring/fleet-overview.json` and its dashboard
  derivation from `repparw/nix`; keep any desired dashboard source in a
  Grafana Git Sync repository or independent backup.
- Simplify Alloy to ship only to Cloud at a single intentional scrape cadence
  instead of keeping duplicate scraping, but retain fleet-wide Alloy.
- Keep truly independent Epsilon reachability monitoring and deployment
  readiness safety gates.
