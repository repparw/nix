---
type: Service Architecture
title: Hermes Chief of Staff
description: Epsilon's single coordinator, native memory and durable task workflow, with audited routing limits.
when: Read when changing Hermes coordination, model routing, memory, tools, or identity.
resource: modules/aspects/services/hermes.nix
tags: [hermes, epsilon, memory, kanban, models]
---

# Hermes Chief of Staff

One existing Hermes identity coordinates work through the existing Discord bot.
Temporary workers provide execution context; native Kanban preserves assignments
and outcomes across sessions. The coordinator verifies results and replies to the
user. No extra service, profile, frontend, or task database is introduced.

`SOUL.md` contains the short identity and authorization policy. The
`chief-of-staff` skill contains the workflow and handoff requirements. Both are
installed through upstream `hermesHomeFiles`. Existing memory files are never
declared or overwritten by Nix. Upstream activation deep-merges managed settings
and retains other runtime settings, including Discord presentation preferences.

## Deployment audit, 22 October 2026

The flake pins Hermes v0.22.2, commit
`d923a5eb487a17c0a68801bba9ef0f56c81040a8`. The running wrapper reports that same
revision, although the Nix derivation calls itself `hermes-agent-0.0.0`.
The upstream messaging package is wrapped by `modules/_packages/hermes-agent.nix`
to select Node 24. This branch already contains that wrapper; the running package
still bundles Node 26. This PR does not migrate or update the Hermes input.

The host's `container@hermes` runs a NixOS nspawn container with private user base 327680. Inside it, `hermes-agent.service` runs as `hermes:hermes`, UID/GID 345,
with `HERMES_HOME=/var/lib/hermes/.hermes`, `HOME=/var/lib/hermes`, and working
directory `/var/lib/hermes/workspace`. Host storage is
`/home/repparw/services/hermes`; the corresponding host service UID is 328025.
The container retains its existing network policy and 2 GiB / 512-task limits.

Secrets are SOPS-managed host files, mounted read-only into the container.
Upstream activation writes the private runtime `.env`; the unit does not use
`EnvironmentFile`. The runtime `.env` contains Discord bot/allowlist settings,
OpenRouter, Exa, GitHub, and OpenCode Go credential names. Interactive Nous auth
lives in private `auth.json`, which Nix does not overwrite. Credential presence
alone does not establish provider availability or entitlement.

At audit time, native `state.db` contained 107 sessions and 529 messages:
101 cron sessions, four Discord sessions, and two tool sessions. `kanban.db` had
no cards. `memories/USER.md` contained 298 bytes; no MEMORY file existed yet.
Other state includes `shared-state.db`, cron records, session files, cache,
provider auth, gateway state, and existing triage skills. No user plugins were
installed. Original private memory and conversation contents are excluded here.
The service was active with no failed host units. Discord bot authentication
returned HTTP 200. The existing Discord transport was not sent a test message.

## Memory and task ownership

Native USER memory holds preferences and operating rules. Native MEMORY holds
small durable decisions and rationale. Searchable SQLite session history holds
investigations and original messages. Kanban bodies, comments, attachments, and
completion metadata hold current task state. Project repositories and services
remain authoritative for their current state.

The pinned version supports profiles, Kanban model tools, CLI claims, structured
completion metadata, PR acceptance contracts, and session search. Kanban tools
are opt-in and were absent from the default Discord surface. The explicit
Discord toolsets enable web, files, terminal, skills, memory, session search,
delegation, Kanban, and cron management. Browser, image generation, voice,
Discord administration, and other optional surfaces are not enabled here.
Existing scheduled jobs keep their own tool restrictions.

Automatic Kanban dispatch is disabled because there are no persistent worker
profiles. The coordinator creates a card assigned to `default`, then claims it
through the native CLI. Despite the `initial_status: running` argument, this pin
normalizes creation to `ready`; there is no model-facing claim tool. Later
comments, blocking, and completion use native model tools. Claims and dispatch
remain Hermes functionality, not a local implementation. A relevant
[upstream claim-recovery issue](https://github.com/NousResearch/hermes-agent/issues/82622)
was checked; no local upstream patch is introduced.

Top-level `delegate_task` runs asynchronously and inherits the coordinator's model
and tool access. It exposes no per-call model/provider/toolset selectors.
Instructions can restrict worker actions but do not create OS isolation.
The coordinator records the assignment and returned handle before waiting,
saves the structured outcome when it arrives, and verifies artifacts before
completion. Interruption recovery means reconstructing work from the card and
checking live workers and artifacts. It does not guarantee a worker survives a
process crash or an unattended task resumes automatically.

## Worker trust and approval boundary

Delegated workers are trusted execution contexts with inherited coordinator tools.
A read-only brief is an operating instruction, not capability isolation. Do not
hand untrusted content to a worker assuming it cannot use terminal, memory, or
scheduling tools. Per-worker capability restrictions remain a prerequisite for
broader unattended autonomy. Future routing work must investigate the native
Hermes API and T3 execution capabilities without weakening this boundary.

The deployed upstream default was `approvals.mode: smart`, which can ask a model
to approve flagged actions. This PR explicitly selects `manual`; dangerous
commands that reach the approval gate require a human decision. Cron, one-shot,
and unattended approval modes remain `deny`, and subagent auto-approval stays
disabled. These guards are pattern-based safeguards, not a sandbox or a universal
classifier of production changes. SOUL's authorization policy still applies.
Existing Discord allowlists, nspawn capabilities, and network isolation remain.

## Effective routing

The coordinator, routine conversation, research, simple coding, complex
engineering, and native workers initially use Nous `openai/gpt-6.1-sol`.
Independent review uses a fresh worker context on that route. This preserves
capability when work becomes harder than initially expected. General per-task
cheap/strong routing is a documented gap in the model-facing delegation API.
Global `delegation.model` and `delegation.provider` can pin all children, which
is too broad for this mixed workload.

Native `auxiliary.compression` uses Nous `stepfun/step-3.7-flash:free`.
The existing live cron route, Nous `reflection/beam-1.0-501b-a23b:free`, is now
recorded declaratively. Session search returns database messages without an
auxiliary LLM in this pin; no fictitious search route is configured. Other
auxiliary routes retain upstream behavior. The configured compression route
has not been exercised by forcing a large production compaction.

The live fallback chain at audit was Reflection Beam, Upstage Solar Mini4,
and Step Flash, all marked free by the provider. The repository had a different
chain. This PR intentionally disables coordinator and worker fallbacks so a
provider failure cannot quietly downgrade complex work. Scheduled and auxiliary
routing have their own upstream failure handling; this is not a global provider
policy. Existing providers are retained; no credential or endpoint is added.

The isolated test authenticated Nous on both the strong and Step Flash routes.
Free model availability, rate limits, and account entitlements can change.
No subscription quota API, reset time, or reliable remaining-budget signal was
established. OpenRouter, Exa, GitHub, and OpenCode Go credentials were inventoried,
not comprehensively revalidated. There is no quota proxy or scheduler. A limit
must produce an honest blocker and an explicit routing decision.

## Validation boundaries

Read the [bootstrap runbook](../runbooks/hermes-chief-of-staff.md) for private
backup locations, independent-session evidence, activation, and recovery.
The behavioral tests used a separate home on Epsilon with the deployed package
and copies of existing memory/history/auth. Production configuration and identity
were not activated by this work. A staged CLI test is not proof of post-deployment
Discord behavior. A graceful blocked-card interruption is not a SIGKILL test.

## Reversible OptChat research

The [OptChat provider](https://github.com/aska-digital/optchat-memory/tree/75d40c049c09aadf6604a79946efd485fd8f5b6d)
was inspected at commit `75d40c049c09aadf6604a79946efd485fd8f5b6d`.
It implements Hermes's MemoryProvider interface rather than replacing the
conversation loop. Its imported memory API names and lifecycle hooks exist in
the pinned Hermes source; runtime compatibility remains untested. Its log keeps
verbatim messages locally and builds a summary tree using background auxiliary
calls. Zoom tools can recover original text. More retention means more private
data to protect and back up. Summarizer requests also disclose retained content
to the chosen provider. Summary recall accuracy needs an independent benchmark.

The [design](https://github.com/aska-digital/optchat-memory/blob/75d40c049c09aadf6604a79946efd485fd8f5b6d/DESIGN.md)
keeps a stable system block and native recent context to preserve prompt caching;
its recall view is not UniiChat's replacement turn loop. Background compaction
adds calls and storage; recovery still depends on intact original logs and native
sessions. Native Hermes instead combines bounded curated memory, original
session search, and its ContextCompressor. Its separate ContextEngine extension
can change context selection, which can also change cached prefixes.

A later experiment can pin the plugin in a disposable home with synthetic
messages, compare retrieval, latency, token/cache usage and compaction cost,
then switch back to native memory while retaining both logs. Do not share one
OptChat home between gateway and separate CLI processes: the design documents a
single-writer log lock. Test restart/recovery and original-message zoom before
using real history. No experimental provider is activated in this PR.
