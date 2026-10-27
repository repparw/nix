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

[hermes.nix](../../modules/aspects/services/hermes.nix) owns settings and container
wiring. The service runs inside Epsilon's existing `hermes` nspawn container, with
home `/var/lib/hermes/.hermes` and workspace `/var/lib/hermes/workspace`. Host
storage is `/home/repparw/services/hermes`. Existing container resource limits and
network policy remain in force.

Alpha installs the pinned upstream `hermes-desktop` application through the
`hermes-desktop` aspect. Epsilon and Pi do not install this desktop package.
Installation does not configure a remote connection: select the existing
Epsilon Chief of Staff backend when connecting Desktop. A local Alpha profile
would have separate history, memory, and credentials. Remote access and its
authentication must be verified before treating Desktop as the Chief of Staff
interface.

`SOUL.md` contains the identity and authorization policy. The
[Chief of Staff skill](../../modules/aspects/services/hermes-chief-of-staff/SKILL.md)
defines task ownership, handoffs, and verification. Upstream `hermesHomeFiles`
installs these files. Nix does not declare or overwrite native user memories.
Upstream activation merges managed settings with other runtime preferences.

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

Native delegation is asynchronous and inherits the coordinator's model and tools.
Per-call model, provider, and tool restrictions are unsupported in the reviewed
pin. A read-only brief constrains intent, not capabilities. Workers are trusted
contexts with the coordinator's access; human approval remains required.
The coordinator records returned handles and outcomes on the card and checks real
artifacts before completion. Recovering a card does not prove its worker survived
a process crash.

## Routing and approvals

The coordinator and workers use the configured strong Nous route. Explicit
fallback chains are empty, so provider failure cannot silently downgrade complex
work. Global child-model routing is available upstream but does not select a
model independently for each task. Compression and cron have separate routes in
`hermes.nix`; session search reads the native database without an auxiliary LLM.

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
