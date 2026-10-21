---
type: Runbook
title: Grafana Cloud setup
description: Retained link to the current Grafana Cloud deployment procedure.
when: Follow an older link to the Grafana Cloud trial.
resource: modules/aspects/monitoring.nix
tags: [monitoring, grafana-cloud, alloy]
---

# Grafana Cloud setup

Use [Grafana Cloud parallel pilot](grafana-cloud-pilot.md) for the current
configuration, credentials, deployment checks, and Cloud alerts.

The pilot replaces the original combined Cloud switch with independent
`modules.monitoring.agent.cloud.metrics` and `logs` destinations.
