---
type: Runbook
title: Bootstrap and validate Hermes Chief of Staff
description: Back up existing Epsilon state, activate the coordinator policy, and verify continuity without replacing private history.
when: Read before activating or restoring Hermes, or validating cross-session coordination and memory.
resource: modules/aspects/services/hermes-chief-of-staff/backup.py
tags: [hermes, epsilon, backup, validation, kanban]
---

# Bootstrap and validate Hermes Chief of Staff

Read the [architecture and audit](../services/hermes-chief-of-staff.md) first.
This change is prepared declaratively; production activation remains pending.
No new secrets or manual provider enrollment are required.

## Preserve state before activation

The 22 October audit retained these private backups on Epsilon, under host
`/home/repparw/services/hermes/bootstrap-backups/`:

- `chief-of-staff-20261022T1730Z`: the complete `.hermes` tree, six SQLite
  databases verified by `PRAGMA integrity_check`.
- `chief-of-staff-20261022T1730Z-workspace`: the existing workspace.
- `chief-of-staff-20261022T1800Z`: a second complete `.hermes` backup after
  tightening connection closure and standalone SQLite output. All six passed.

These names identify this audit run; they are not an automatic retention policy.
Backups include credentials and private conversations. Keep them on the private
host and existing private backup storage. Never commit or attach them to a PR.
Check offsite backup coverage separately before relying on disaster recovery.

`backup.py` uses SQLite's online backup API, closes connections explicitly,
converts each destination database to standalone DELETE journaling, checks
integrity, and omits original WAL/SHM/journal files. Ordinary files are copied;
symlinks are preserved without following them; sockets and other special files
are omitted and recorded in a private manifest. It creates owner-only backup
directories and files, refuses an existing destination or one under the source,
and bounds each database backup to 60 seconds. It does not provide an atomic
snapshot across multiple databases or concurrently changing ordinary files.
For a fully quiescent restore point, first arrange an idle gateway and workers.
A failed backup leaves its incomplete directory for inspection; retry with a new
name and require the successful summary and manifest.

Before deployment, copy the repository's `backup.py` privately to Epsilon or use
the installed `.hermes/scripts/chief_of_staff_backup.py` after first activation.
Inside the existing container, use its installed Python:

```bash
sudo nixos-container run hermes -- /etc/profiles/per-user/hermes/bin/python3 \
  /var/lib/hermes/.hermes/scripts/chief_of_staff_backup.py \
  /var/lib/hermes/.hermes /var/lib/hermes/bootstrap-backups/UNIQUE-NAME
```

Repeat for `/var/lib/hermes/workspace` into a distinct destination. Before the
first activation the script is not installed yet: stream the repository file to
`python3 - SOURCE DESTINATION` over SSH, or copy it to a private temporary path.
Keep the existing backup trees intact.

## Validate and activate

1. Run the verification skill against Epsilon. Inspect the generated Hermes
   settings and `hermesHomeFiles`; build the complete system without activation.
   Run the repository's pre-commit, formatting, Epsilon evaluation, agent-docs,
   Hermes triage, and `hermes-chief-of-staff` backup-recovery checks.
2. Review the closure difference from the running host. This branch already
   changes the package's Node selection from the running Node 26 to Node 24.
   Container activation can interrupt Discord conversations or running jobs.
   Arrange an idle window before authorizing it.
3. With activation authorized, review `nix run .#deploy-rs -- .#epsilon --dry-activate`,
   then use the repository's local deploy-rs activation path. Do not substitute
   this for the controller's `fleet-update deploy` transaction.
4. Run `fleet debug epsilon`. Inside the container confirm
   `systemctl is-active hermes-agent`, read the managed config without printing
   `.env` or `auth.json`, and confirm the new identity and skill are installed.
   Existing `auth.json`, USER memory, sessions, Discord channel settings, and
   scheduled jobs must remain present.
5. Through the existing private Discord interface, ask Hermes for a bounded
   read-only documentation review and a durable task. Confirm it loads the skill,
   searches history and cards, records acceptance criteria, delegates through
   `delegate_task`, preserves a handoff, and verifies the result before completion.
   Native workers inherit the coordinator route; do not request nonexistent
   per-call model/toolset selectors. Avoid any task that needs a new permission.
6. Start fresh conversations for the recall and duplicate-work probes below.
   Verify actual task/session records as well as the assistant's response.
   Keep synthetic entries clearly tagged so they cannot become project policy.

## Reproduce independent-session probes

Use a separate private `HERMES_HOME` on Epsilon with copies of backed-up
`state.db`, `kanban.db`, native memories, `.env`, and `auth.json`. Install the PR's
SOUL and skill there; set an isolated working directory, disable dispatch and
notifications, and do not start a second Discord gateway. Never point test memory
writes at the production home. Auth refresh may update only the copied auth file;
do not copy it back over the production file.

Use the installed package from `systemctl show hermes-agent -p ExecStart` and
run it as `hermes`, with `HERMES_HOME` explicitly set. Each probe uses a new
`hermes chat --oneshot -Q --in ISOLATED-DIRECTORY --max-turns 16 --run-budget 240
-s chief-of-staff --query-file -` process. Redirect stdout/stderr to a private file
inside the isolated directory. Do not use `--resume` for these probes.

1. Record a tagged synthetic decision and its rationale in MEMORY. Create a
   tagged local-only documentation card with a stable idempotency key. Record
   acceptance criteria, artifact path, ownership, and next action. Delegate a
   read-only document review, then persist its actual returned findings on the
   card. Block it pending independent verification and exit the process.
2. In a fresh process, ask for the tagged decision and rationale. Ask session
   search to retrieve the exact earlier finding and cite its session before
   re-reading the document. Read the existing card and recover status, artifact,
   blocker, and next action. Request the same investigation again; require it to
   reuse the existing card without creating another or launching another worker.
3. In another fresh process, retrieve the native delegation tool result, persist
   a continuation-ready handoff, independently verify the document facts, unblock
   and claim the same card, then complete with structured metadata. Re-read the
   card and query SQLite read-only to confirm one card with status `done`.

## Evidence from 22 October 2026

The isolated home remains at container
`/var/lib/hermes/bootstrap-validation-20261022/.hermes`. Private output files
remain beside it. The production SOUL and USER memory matched the first backup
byte-for-byte after validation; production retained its 107 sessions. No test
card was inserted into production.

- Decision recall passed. Seed session `20261022_142614_d648a4` saved the synthetic
  choice of one coordinator and temporary workers, with the rationale that
  independent personalities duplicate context and maintenance. Fresh session
  `20261022_142845_151959` recovered both; the memory file independently contains
  the tagged decision.
- Historical retrieval passed. Fresh session `20261022_142845_151959` used native
  session search to recover seed session message 562 before reading the source
  again. Exact recovered strings were `/var/lib/hermes/.hermes/crash/inbox` and
  `.hermes/scripts/crash_triage_enroll.py`, from the public crash-triage runbook.
- Continuity passed for a graceful interruption. Card `t_3ed2d0d6` retained owner
  `default`, blocked status, source artifact, findings, blocker, and next action
  after the seed process exited. This did not simulate abrupt process death.
- Deduplication passed. The fresh duplicate request reused `t_3ed2d0d6`, created
  no additional card, and launched no worker. Independent SQL inspection found
  exactly one card for idempotency key `COS-VALIDATION-20261022`.
- The first worker selection was a partial failure. The coordinator used a native
  CLI child on Step Flash rather than `delegate_task`, and needed a CLI claim
  after card creation returned `ready`. Its findings were saved, but this is not
  counted as a clean native delegation pass. The skill was corrected afterward.
- Native delegation then passed in session `20261022_142847_b88978`. Its actual
  `delegate_task` result, message 577, identified both exact paths; the child
  trace contained one `read_file`. It ran the inherited strong model. Requests
  for cheap per-call routing and restricted toolsets were unsupported, not met.
- Completion passed in session `20261022_143005_ce612d`. It retrieved message 577,
  persisted the native worker evidence in comment 3, independently read the
  document, verified lines 14 and 32, and completed the original card with
  structured metadata. Independent SQL inspection confirmed one `done` card and
  three comments. Verification concerned documentation, not running enrollment.

The native delegation check used an explicit CLI delegation/file tool selection;
production Discord tool exposure still needs the post-activation probe. Forced
compression, abrupt-crash recovery, provider exhaustion, and end-to-end Discord
responses remain untested. Existing provider credentials were not rotated.

## Recover without losing newer history

For a policy rollback, revert the declarative settings/SOUL/skill and activate the
previous known-good configuration. Keep live memories, auth, Kanban, and sessions.
Do not restore an old database merely to remove an identity change.

For state corruption, first stop the container so the gateway, cron, and workers
cannot write. Preserve the current host state tree under a new private name.
Stage a copy of the chosen backup outside `.hermes`, check each SQLite database
read-only, then restore the selected files into the host bind-mount source.
Remove stale sidecars only for the replaced databases, after preserving the
original state. Reestablish ownership for the container service UID/GID
328025 and private permissions before starting the container. Retain newer
original records for later reconciliation; do not merge SQLite files by copying
individual tables blindly. Restore workspace artifacts separately if needed.
Validate service startup, original-session retrieval, memory, Discord, and task
state before treating recovery as complete.
