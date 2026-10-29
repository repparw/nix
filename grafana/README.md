# Grafana Cloud state

`dashboards/` contains the dashboard resources for Grafana Git Sync. Preserve
`metadata.name` to keep dashboard URLs stable. Cloud UI edits should produce
GitHub pull requests; a merge makes the revision available to sync.

Alerting and notification settings are edited in Cloud and backed up privately
through Epsilon's existing offsite backup. No webhook or export archive belongs
in this directory. See [operations and recovery](../docs/runbooks/grafana-cloud.md).

`connection.json` and `repository.json` record the Cloud Git Sync configuration.
The GitHub App key is encrypted separately with SOPS; connection creation needs
that key injected privately. These specifications are outside the synced path.
