---
type: Runbook
title: Configure Grafana Cloud
description: Maintain Cloud-owned dashboards and alerts, Git Sync, and private recovery exports.
when: Change dashboards or alerts, rotate Cloud credentials, or restore Cloud configuration.
resource: modules/aspects/monitoring-cloud-state.nix
tags: [monitoring, grafana, cloud, alloy, alerting, backup]
---

# Configure Grafana Cloud

Stack: `https://repparw.grafana.net`. Edit dashboards and alerting in Cloud.
Nix owns Alloy, collection filters, native health facts, private service probes,
and encrypted credentials. See [monitoring diagnostics](monitoring.md) for
collection checks.

## Dashboards in Git

[Dashboard resources](https://github.com/repparw/grafana/tree/main/dashboards)
are maintained in the standalone public `repparw/grafana` repository.
The dashboard UID is `fleet-overview`; datasource UIDs are the live Cloud
UIDs, including `grafanacloud-prom`, `grafanacloud-logs` and
`grafanacloud-usage`. Do not maintain a second dashboard in this NixOS repo.

The existing Grafana Cloud Git Sync repository `fleet-dashboards` uses
`repparw/grafana`, branch `main`, path `dashboards/`, through the
repository-scoped `fleet-github` GitHub App connection. Keep PR workflows
and five-minute polling with webhooks disabled. Public integration metadata
lives in [connection.json](https://github.com/repparw/grafana/blob/main/connection.json)
and [repository.json](https://github.com/repparw/grafana/blob/main/repository.json).
The App key and backup credentials remain SOPS-encrypted in this repo.

Cloud UI dashboard changes should produce GitHub PRs; dashboard query tests
run in the Grafana repository's own CI. Verify live sync status, UID and
queries following changes. Never enable a second Git Sync owner for the same
dashboard UID.

Git Sync covers dashboards and folders, not alerts or notification settings.
The latter remain Cloud-managed and privately backed up as described below.

## Alerts and notifications

Cloud is authoritative for rules, contact points, notification policies and
notification templates. Their old source copies under
`modules/_tests/fixtures/monitoring/` are historical test fixtures, not files to
apply to production. Editing alerting does not require a fleet deployment.

Keep ordinary health rules at **Keep Last State** for evaluation errors and
No Data. **Cloud metrics query availability** separately reports datasource
errors; query failure must not masquerade as host or disk failure. Alpha can
shut down intentionally, so its absence needs a separate uptime policy.

The **Grafana Cloud Alerts** contact point delivers to Discord. Preview firing,
recovery and mixed-severity cases before changing templates. Grafana sends a
separate recovery message; it does not delete the firing message.

The failed-unit rule fires on `fleet_failed_unit`, one series per failed loaded
unit or retained job, so a grouped message names each unit. Its query also
returns a zero-valued host baseline from `fleet_health_collection_timestamp_seconds`
when no units fail. This avoids a No Data result after the last failed unit
recovers: Grafana can then resolve the disappeared alert instance through its
MissingSeries handling (normally after two evaluations). The separate collector
staleness alert covers missing host facts.

The dashboard derives failed counts via `count by (host) (fleet_failed_unit)`,
zero-filled for healthy reporting hosts. Historical `fleet_failed_units` and
node-exporter samples remain fallbacks. The collector temporarily continues to
emit the legacy `fleet_failed_units` gauge so the existing live Cloud alert
stays functional until its query is migrated. Remove that gauge afterward.

Keep collection's series budget separate from alert policy. Check actual usage
in `grafanacloud-usage` after adding metrics or labels. Disk facts and their
host-specific thresholds remain in `modules.monitoring.health.disks`.

## Private configuration backups

Epsilon's `grafana-cloud-backup.service` exports configuration immediately before
its ordinary offsite Restic run. There is no second backup schedule. Manual
`systemctl start restic-backups-offsite.service` runs the same export/upload path.
For an export without uploading, start `grafana-cloud-backup.service` alone.

The verified archive is `/var/lib/grafana-cloud-backup/grafana-cloud-state.tar.gz`.
It includes dashboards, folders and their permissions, datasource metadata,
alert rules, contact points with decrypted secrets, policies, templates and mute
timings. Restic retains previous versions. Failed exports preserve the previous
archive and mark the overall backup incomplete while available data uploads.

Treat the archive as secret: its directory is mode 0700, files are 0600, and
Restic encrypts the offsite copy. Never commit exports or webhook URLs to Git.
API reads are sequential, not an atomic snapshot; avoid editing configuration
during a recovery export. This backs up configuration, not metrics or logs.
Datasource secrets, organization users/RBAC and GitHub App private credentials
are not recoverable from these APIs. The GitHub App recovery key and IDs are
SOPS-encrypted as `grafana-git-sync-app` in the Epsilon credential file. When
recreating the connection, pass the base64-encoded private key as
`secure.privateKey.create`; do not put it in the public connection specification.

The service account `fleet-state-backup` has no basic organization role and
read-only resource roles, including permission to export contact-point secrets.
Its token is SOPS-encrypted in `secrets/grafana-cloud-epsilon.sops.yaml` as
`grafana-cloud-backup-token`; rotate it before expiry on 2027-10-26. Agent
metrics/log write credentials remain separate and unchanged.

## Restore configuration

1. Restore the archive from Epsilon's Restic repository to a private directory.
2. Verify the SHA-256 file hashes in `manifest.json` before using the JSON files.
3. Restore folders and permissions, then dashboards using native Grafana APIs
   or Git Sync. Keep existing UIDs. Cloud-managed datasource credentials must
   be recovered separately; `datasources.json` contains metadata only.
4. Restore alert rules from `alert-rules-api.json` using the provisioning API;
   use `X-Disable-Provenance: true` to retain UI editing. Native export-format
   copies are also included, but are not interchangeable with API payloads.
5. Restore contact points from their decrypted export, templates, mute timings,
   and finally the policy tree. Keep alert evaluation paused until destinations
   and queries have been checked; resume only the intended rules.
6. Check dashboard queries, rule count, datasource availability and actual
   notification delivery. Restore tokens from SOPS rather than terminal history.

Use a disposable dashboard for recovery validation; do not overwrite live rules
merely to test a backup.
