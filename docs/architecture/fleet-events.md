---
type: Architecture Concept
title: Fleet Event Transport Migration
description: Consolidate durable notification and agent-event delivery without weakening existing safety guarantees.
when: Work on fleet notifications, Discord, event queues, NATS JetStream, Grafana alert routing, or Hermes triage.
resource: modules/aspects/services/nats-event-bus.nix
tags: [events, notifications, nats, jetstream, hermes, grafana, discord, migration]
---

# Fleet event transport migration

Status: **stage 1, opt-in transport + isolated VM check only**. The live
notification, triage, and deployment paths remain unchanged. Do not enable the
broker, create public ingress, merge, deploy, change credentials, or clear the
controller's PAUSE as part of an exploratory test.

## Objective

Replace repeated **transport** implementations with maintained software while
retaining each source's proven application semantics. An event bus does not
replace incident state, authorization, reconciliation, or a source's ability to
buffer events while the broker is unreachable.

| Source and current implementation | Existing contract | Candidate after migration |
| --- | --- | --- |
| Alpha coredumps: `coredump-watch/collector.py` plus Epsilon `hermes-crash/triage.py` | Durable local outbox, SSH exact-ID ACK, crash signature coalescing, Hermes delivery gate | Keep local journal cursor and minimal pre-publish spool; JetStream consumer replaces transport inbox/receipt/retry; retain triage grouping and authorization |
| Pi package changes: `package-update-event.py`, `package-update-deliver.sh`, `hermes-package/triage.py` | Durable package event before rollback-root cleanup, independent delivery timer, exact-ID receipt, weekly grouping | Keep bounded local spool until confirmed JetStream publish; replace cross-host delivery timer/inbox; keep weekly research and deduplication |
| Pi readiness: `fleet-readiness-probe.sh` and `fleet-readiness-deliver.sh` | Transition observation, chronological queue, Discord `.posted` marker, *separate verified Alpha completion action* | Preserve state machine and separate completion permission; migrate Discord delivery and completion to independent durable subscribers; never conflate an alert ACK with completion |
| Direct bot notifications: `modules/_services/lib.nix` `mkDiscordNotify`, free-model watch, backup and deployment scripts | Discord post/delete, message-ID tracking, some best-effort messages | Shared Discord consumer/adapter; explicit edit/update/resolved behavior and idempotency keys; do not break mandatory emergency path |
| Page watchers: `modules/aspects/services/automations.nix` | Page change detection and direct message delivery | Publish relevant domain events; retain the detection logic |
| GitHub upstream watcher: `.github/upstream/` | PR state, once-only status messages, guarded cleanup actions | Only move reporting when it has a suitable authenticated ingress; retain state and protected automation constraints |
| Grafana Cloud alerting: `docs/runbooks/grafana-cloud.md` | Cloud owns rules/routes and independent direct Discord critical alerts | Add *parallel* signed webhook intake when authentication is ready; keep the direct Cloud-to-Discord escape path independent |
| Hermes Chief of Staff: `modules/aspects/services/hermes.nix` | Durable memory, native cron, manual approvals and unattended denial | Selective durable subscriber, trigger only when the consumer has accepted work; no routine LLM forwarding, no inferred repair permission |

The migration is **not** a blanket removal of all custom state. In particular:
source-local outage buffering, actual deployment completion, crash fingerprint
suppression, incident-episode state, Discord-message reconciliation, and
approval checks cannot be delegated to NATS.

## Stage 1: transport proof (this branch)

- Reuse pinned Nixpkgs `services.nats` and `pkgs.natscli`; don't vendor a
  broker or build a new SQLite event service.
- Import the `event-bus` aspect on Epsilon with
  `modules.fleet-event-bus.enable = false` by default.
- When **explicitly** enabled, NATS binds `127.0.0.1:4222`, with
  JetStream file storage and bounded memory/disk budgets. No public route or
  firewall opening is provided. This is an *unauthenticated localhost fixture*
  and is **not approved for production producer traffic** until SOPS-managed
  identity, per-publisher subject permissions, and cross-host transport exist.
- Persist `/var/lib/nats` in Epsilon's `/persist` through the existing
  impermanence module. Epsilon's `/` is tmpfs; an unpersisted stream would
  silently lose events across reboot.
- Test synthetic publishing to `fleet.>` with two independent durable
  consumers (Discord- and Hermes-shaped) and server restart using an isolated
  NixOS VM. This test uses no production secrets or outside networking.
- Stream setup is test-only; no production stream is created in this stage.

### Verify without local fleet access

Once CI builds the revision, review:

```sh
nix build .#checks.x86_64-linux.nats-event-bus-vm --no-link
nix eval .#nixosConfigurations.epsilon.config.modules.fleet-event-bus.enable --json
nix eval .#nixosConfigurations.epsilon.config.services.nats.enable --json
```

Expected host values before an explicitly authorized opt-in: `false` and
`false`. Check `nats.service` is **not** introduced by this change.
The VM check validates two-consumer replay, not a live cross-host rollout.

## Event contract for later stages

Use one **Limits**-retention file-backed JetStream stream, initially
`FLEET_EVENTS` subscribed to `fleet.>`, with a separate durable pull consumer
per independent destination. Avoid **WorkQueue** retention for broadcast events:
overlapping consumers do not work as intended there.

Proposed subjects: `fleet.crash.alpha`, `fleet.package.pi`,
`fleet.readiness.pi`, `fleet.backup.epsilon`. Rules should route by
`subject`, `severity`, `host`, and source type. A versioned, small JSON
envelope should carry at least a stable `event_id`, `schema_version`,
`source`, `host`, `occurred_at`, `kind`, and a source-specific payload.
Never include secrets, raw private journal material, or untrusted instructions
to agents. Do not use message text as an instruction channel.

Publish with a *JetStream publish acknowledgement*, not a fire-and-forget Core
NATS publish. Use `Nats-Msg-Id` for bounded retry deduplication, but also
persist source event IDs and consumer side-effect receipts for long windows.
JetStream is at-least-once: a consumer ACK after a Discord API call may be lost,
so retries still require idempotent handling. Missing ACK must not authorize a
duplicate privileged action.

Retain a source-local outbox until the broker acknowledges storage. A broker
outage must never cause a coredump cursor to advance past an unrecorded event.
Set finite age/byte/count limits and `discard=new` so a full stream rejects
a publish *rather than silently evicting unread events*; alert on backlog,
publish failures, consumer lag, and rejected messages. Retention limits apply
even to unread events, so choose and test outage horizon explicitly.

Do not treat a broker ACK as incident resolution. Model source events and
individual alert fingerprints separately from an incident episode and its
current state; reject stale out-of-order resolutions and avoid repeated LLM
triggers on an unchanged episode. Grafana group notifications may contain
multiple alerts; use each alert's stable fingerprint and lifecycle timestamps.

Only allowlisted origins should feed the bus, and bot/agent replies should be
responses *to* an incident rather than new actionable incidents. There must be
no LLM-based routine fan-out. Agents must not acquire execute/restart/deploy
rights through a consumer subscription.

## Next implementation slices (separate reviewable PRs)

1. **Security and topology:** choose broker hosting, SOPS credentials, NATS
   account/subject ACLs, TLS or trusted tunnel transport, private ingress,
   source-local spools, backup and restore. Do not expose 4222 publicly. Ensure
   Epsilon failure does not block the existing Grafana critical-alert route.
   Evaluate broker single-node failure against the actual Alpha/Pi/Epsilon
   availability; do not assume a three-node cluster is safer.
2. **Pure transport pilot:** dual-publish one low-risk existing event without
   changing its current consumer. Test offline producer, offline subscriber,
   duplicate publish, lost ACK, restart, stream full, permission rejection,
   malformed input, replay order, and rollback. No agent or Discord side
   effects in the pilot.
3. **First real cutover:** migrate one existing source's retry/ACK/inbox only
   after pilot parity is proven; delete the replaced plumbing and its redundant
   tests in the same cutover PR. Keep rollback to its old delivery path.
4. **Discord adapter:** independent durable destination, bounded rate limits,
   persistent message ID, edit/delete-on-resolution semantics where we own
   the message, and audit trail. A Grafana-owned webhook message is not
   editable/deletable by our bot. Preserve independent emergency delivery.
5. **Incident lifecycle / Hermes:** signed Grafana bridge with exact
   per-alert semantics, event-triggered Hermes investigations with verified
   acceptance or recovery, guarded tool permissions, no loops, and explicit
   authorization for any repair action. Evaluate Grafana IRM only if it
   actually replaces more incident logic without weakening Discord/replay.
6. **Consolidate other producers:** backup, deployment, page watchers and
   GitHub notifications based on measured code removed and added operations.

## Before production opt-in

- Design NATS user credentials and subject ACLs using SOPS; unauthenticated
  loopback only protects against *remote* clients, not other local processes.
- Configure a documented stream with a finite capacity and explicit overflow
  behavior; configure independent durable consumers before sending real data.
- Add a valid JetStream snapshot/restore path to fleet backups. A live file
  copy of the stream's backing directory is **not** a transactional backup.
- Define exactly which events may drive actions; keep the deployment PAUSE
  and Hermes approval rules unchanged.
- Observe VM checks and any branch CI failures before proposing activation.

## References

- [JetStream streams and consumers](https://docs.nats.io/concepts/jetstream)
- [Stream limits, retention and duplicate window](https://docs.nats.io/nats-concepts/jetstream/streams)
- [NATS authentication and authorization](https://docs.nats.io/running-a-nats-service/configuration/securing_nats/auth_intro)
- [Existing monitoring behavior](../runbooks/monitoring.md)
- [Hermes crash triage](../runbooks/hermes-crash-triage.md)
- [Fleet deployment and pause](../runbooks/fleet-operations.md)
