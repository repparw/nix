---
type: Service Architecture
title: Hermes Chief of Staff
description: Epsilon's coordinator, native memory, durable tasks, and routing limits.
when: Read when changing Hermes coordination, model routing, memory, tools, or identity.
resource: modules/aspects/services/hermes.nix
tags: [hermes, epsilon, memory, kanban, models]
---

# Hermes Chief of Staff

The existing Hermes identity coordinates work through the Discord bot. Temporary
workers execute bounded tasks; native Kanban preserves assignments and outcomes
across sessions. The coordinator verifies results and replies to the user.

[hermes.nix](../../modules/aspects/services/hermes.nix) declares the installation,
container/service wiring, Discord connection, and enforced safety settings.
Runtime preferences and personal behavior remain in Hermes's private state.
The service runs inside Epsilon's existing `hermes` nspawn container, with
home `/var/lib/hermes/.hermes` and workspace `/var/lib/hermes/workspace`. Host
storage is `/home/repparw/services/hermes`. Existing container resource limits and
network policy remain in force.

The live `SOUL.md` and Chief of Staff skill define the personal identity and
workflow. Selected checkpoints live in the private
[`hermes-config` repository](https://github.com/repparw/hermes-config), along with
sanitized runtime preferences. Git does not deploy them: live files are
authoritative and changes are checkpointed after verification. Nix installs only
the generic backup helper, not personal behavior files, memories or history.
The private checkout is `/var/lib/hermes/workspace/hermes-config`; its Git key
grants access only to that repository. Nothing automatically pulls or applies
commits to the live profile.
Nix owns installation, service wiring, credentials and approval/resource
safeguards. Model routes, fallbacks, cron and compression models, toolset
selection, memory preferences, Kanban preferences and display options live in
the private `config.yaml`. Activation merges only the infrastructure and safety
settings into that file, preserving runtime preferences. Back up the Hermes
home and workspace before changing them; Epsilon's offsite Restic backup includes
their host parent under `/home/repparw`. Live Restic copies are not guaranteed
consistent across SQLite databases and ordinary files: verify a quiescent,
restorable backup before depending on offsite recovery.

SOPS-managed credentials are mounted read-only into the container; activation
writes the private runtime environment. Interactive provider auth remains in
private `auth.json`. Credential presence does not establish account entitlement
or current provider availability.

## Memory and task ownership

USER memory holds preferences. MEMORY holds concise durable decisions and their
rationale. Searchable session history holds investigations and original messages.
Kanban bodies, comments, attachments, and completion metadata hold current task
state. Repositories and running services remain authoritative for their state.

Discord enables the web, file, terminal, skills, memory, session-search,
delegation, Kanban, and cron toolsets. Existing scheduled jobs retain their own
tool restrictions. Optional browser, voice, image-generation, and Discord
administration tools are outside this configuration.

Automatic Kanban dispatch and automatic subscription are disabled. The coordinator
creates a card assigned to `default`, then claims it through the native CLI.
The reviewed Hermes pin normalizes new cards to `ready` and has no model-facing
claim tool. Comments, blocking, and completion use native model tools.

Native delegation is asynchronous. Worker routing comes from live
`delegation.provider`, `delegation.model` and `delegation.reasoning_effort`.
Workers inherit the coordinator's tools.
Per-call model, provider, and tool restrictions are unsupported in the reviewed
pin. A read-only brief constrains intent, not capabilities. Workers are trusted
contexts with the coordinator's access; human approval remains required.
The coordinator records returned handles and outcomes on the card and checks real
artifacts before completion. Recovering a card does not prove its worker survived
a process crash.

## Routing and approvals

The live coordinator route is Nous `openai/gpt-6.1-sol`; native workers use
`openai/gpt-6.1-terra` with high reasoning. These are runtime choices rather than
Nix defaults. Global child-model routing does not select a model independently
for each task. Compression and cron have separate live routes; session search
reads the native database without an auxiliary LLM.

The upstream package-management marker also locks application settings. This
deployment explicitly selects its supported `false` marker/environment value
to allow native runtime configuration writes in the gateway and, when enabled,
the separate Desktop/dashboard backend. The baked Nix provenance
still refuses self-updates. `/etc/hermes/config.yaml` uses Hermes's native
managed-scope overlay to protect only approval, delegation-resource and loop
safeguards; the native configuration writer refuses those keys and preserves
them when saving other preferences.

The private repository uses an explicit file allowlist. Authentication files,
full runtime configuration, databases, memories, Kanban, browser profiles and
backups belong only in private backed-up state. Its sanitized preference
snapshot cannot replace the full runtime configuration. Restoring a new host
requires the state backup; Nix no longer supplies the personal behavior files.

Approvals are manual. Cron, single-query, and unattended execution deny actions
that require approval; workers cannot approve themselves. This is intentionally
more restrictive than unattended dispatch.

Provider limits and free-model availability can change. No reliable subscription
quota or reset-time API was established. Provider exhaustion remains a visible
blocker requiring an explicit routing decision. No new provider, endpoint, or
credential is introduced here.

## Validation and optional memory research

The [bootstrap runbook](../runbooks/hermes-chief-of-staff.md) covers backup,
activation, continuity checks, and recovery. Isolated CLI probes passed native
recall and task continuity; live Discord behavior requires post-activation tests.

The [OptChat provider](https://github.com/aska-digital/optchat-memory/tree/75d40c049c09aadf6604a79946efd485fd8f5b6d)
was assessed as a possible Hermes MemoryProvider, not installed. It retains
verbatim local history and makes background summary calls, increasing retained
private data and provider disclosure. Its design requires a single-writer log.
Any experiment should use a disposable home and synthetic messages, test recall
and restart behavior, and retain a path back to native memory. Runtime
compatibility, retrieval quality, and cost remain unverified.
