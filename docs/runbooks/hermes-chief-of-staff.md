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
3. Before activation, finish existing workers and stop the gateway for the
   backup window. Verify that no Hermes worker processes or external cron workers
   remain and that the cron tick/fire locks are idle. Take one fresh state and
   workspace backup while all writers are stopped. This makes the independent
   database/file copies a quiescent recovery point. Keep online backups for normal
   operation; no new snapshot service is required.
4. With activation authorized, review `nix run .#deploy-rs -- .#epsilon --dry-activate`,
   then use the repository's local deploy-rs activation path. Do not substitute
   this for the controller's `fleet-update deploy` transaction.
5. Run `fleet debug epsilon`. Inside the container confirm
   `systemctl is-active hermes-agent`, read the managed config without printing
   `.env` or `auth.json`, and confirm the new identity and skill are installed.
   Existing `auth.json`, USER memory, sessions, Discord channel settings, and
   scheduled jobs must remain present.
6. Through the existing private Discord interface, ask Hermes for a bounded
   read-only documentation review and a durable task. Confirm it loads the skill,
   searches history and cards, records acceptance criteria, delegates through
   `delegate_task`, preserves a handoff, and verifies the result before completion.
   Native workers inherit the coordinator route; do not request nonexistent
   per-call model/toolset selectors. Avoid any task that needs a new permission.
7. Start fresh conversations for the recall and duplicate-work probes below.
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

## Nix validation evidence

Implementation commit `691a0d28d` evaluated Epsilon's full toplevel and the
container's effective settings without updating the lockfile. The x86-64
`epsilon` check is evaluation with package stubs, not a full system build.
Local checks passed for `epsilon`, `pre-commit`, `formatting`, `agent-docs`,
`ci-workflow`, `hermes-chief-of-staff`, `hermes-crash-triage`, and
`hermes-package-triage`. The backup check recovered committed content from an
open WAL database and checked privacy and destination guards. All seven CI
impact-selection tests also passed.

The local full-system attempt could not build ARM derivations, and local daemon
policy refused an ad-hoc remote-builder setting. No trust settings were changed.
Instead, `nix copy --derivation --to ssh-ng://epsilon` transferred the evaluated
derivation; ordinary `nix-store --realise` on Epsilon built it natively.

The full successful output is
`/nix/store/y1fsncbqnq31kf3c6nbd415nj3fqbq42-nixos-system-epsilon-26.11.20261014.55bfb4d`.
It was built without activating or changing the system profile. Generated files
were built at `/nix/store/71mdm1kpwzvc4am5h613qc1k7hg5vvap-hermes-documents`;
SHA-256 comparisons matched all three repository inputs. The generated
`/nix/store/l78c02lb009l3zilygiry06j7gmxkisz-hermes-config.yaml` contains the
expected toolsets, native memory, no coordinator/worker fallback, disabled
Kanban dispatch, and the explicit compression/cron routes.

`nix store diff-closures /run/current-system BUILT-SYSTEM` on Epsilon reported
only the Hermes configuration closure, 10.8 KiB. The running gateway remained
active after the build. The audit's Node 26 observation describes the live
container process, while the host already has the newer package closure.
Activation must still reconcile the live container and be checked in an idle
window. GitHub CI is separate from these local and native checks.

## Review safety checks, 22 October 2026

All checks on reviewed head `3156033c1` succeeded, including `validate / gate`.
The two unrelated conditional package jobs were skipped by design. Changes made
after that head require their own validation before activation.

The private Discord allowlist contains one numeric user ID, with no wildcard or
allow-all environment override. A probe using the installed GatewayRunner
and live configuration admitted that identity and rejected a synthetic unknown
identity for both DM and group sources. This exercised the authorization method
without sending messages or starting another gateway.

The live effective approval mode was `smart`, not manual. The revision responding
to review makes manual approval explicit. Installed guard probes against an
isolated home confirmed that the human callback is invoked, a denial blocks the
flagged command, and a one-shot run fails closed. Only the approval predicate was
called; the illustrative delete command was never executed. A simulated gateway
notification/deny round trip exercises the same pending-approval queue without
sending Discord messages. The real Discord approval UI still needs its smoke test.

Before these checks, the existing gateway had already received SIGTERM at 15:00
local time. Systemd marked its shutdown exit code as failed; no new configuration
had been activated. No service-user execution processes, session leases, async
records, external cron workers, or busy cron locks remained. With writers idle,
fresh private state/workspace backups were taken at
`bootstrap-backups/chief-of-staff-preactivate-20261022T223530Z` and its
`-workspace` sibling. All six SQLite databases passed integrity checks. Any
resumed gateway activity requires another quiescent backup immediately before
activation.

## Combined native build failure, 23 October 2026

All applicable GitHub CI jobs passed on `487038c172827b02c423506e305ec6146917b59f`,
which includes the current main's Node security fixes and manual approvals.
Its full native deployment dry run failed before activation. The failing
dependency was `python3.14-torchaudio-2.11.0`; its test process was terminated
with exit code 143 while running the wav2vec2 model tests. That prevented
`sentence-transformers`, Paperless, and therefore the Epsilon system from building.
The available output does not establish why the process received SIGTERM.
The Nix daemon remained active with no recorded restart at inspection time.

The private operational log is `/tmp/hermes-security-dry-activate.log` on the
workstation. It contains the exact failing derivation and dependency chain.
The earlier daemon-disconnection text in the background command notification
came from the older security-build log printed before the new command.
It is not evidence that this dry run failed for the same reason.

No Chief of Staff activation occurred. The original Hermes gateway remains
stopped pending a verified patched runtime. Earlier successful build evidence
applies to the earlier input revision and does not satisfy this combined
revision's deployment gate. Private state/workspace backups remain intact.
The temporary ten-minute build wake was removed when this attempt finished.

The next step is to establish the termination cause in the failed Torchaudio
check and obtain a successful full native build. Do not disable package tests,
restart the vulnerable old runtime, or activate a partially built system to
bypass this gate. Any retry must retain the existing backups and account for
the security-maintenance thread's separate native builds.

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
