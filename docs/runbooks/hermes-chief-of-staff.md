---
type: Runbook
title: Bootstrap and validate Hermes Chief of Staff
description: Preserve Epsilon state and verify the coordinator before production use.
when: Read before activating or restoring Hermes, or checking continuity across sessions.
resource: modules/aspects/services/hermes-chief-of-staff/backup.py
tags: [hermes, epsilon, backup, validation, kanban]
---

# Bootstrap and validate Hermes Chief of Staff

Read the [service architecture](../services/hermes-chief-of-staff.md) and use the
[fleet operations skill](../../.agents/skills/fleet-operations/SKILL.md) for deployment.
Merging configuration does not establish that the running gateway has changed.

## Preserve state

Before activation, finish workers and keep the gateway stopped. Back up both
container paths `/var/lib/hermes/.hermes` and `/var/lib/hermes/workspace` to
separate, uniquely named directories under `/var/lib/hermes/bootstrap-backups`.
Their host parent is `/home/repparw/services/hermes`.

Use [backup.py](../../modules/aspects/services/hermes-chief-of-staff/backup.py)
with `SOURCE DESTINATION`. Before its first activation, stream the repository
file to the container's Python rather than assuming the installed script exists.
After installation, it is `.hermes/scripts/chief_of_staff_backup.py`.

Require a successful exit, integrity summary, and `backup-manifest.json` before
using a backup. The script uses SQLite's online backup API, checks each database,
and omits source WAL, SHM, and journal files. Ordinary files can change during
copying, so a complete restore point requires quiescent writers. Symlinks are
preserved without following them; special files are skipped and recorded.
Directories and ordinary files are owner-only. Failed output is incomplete;
retain it for diagnosis and retry with a new destination.

Backups contain credentials and conversations. Keep them private and preserve
older copies. Epsilon's offsite Restic configuration includes the Hermes host
state under `/home/repparw`, but a routine live filesystem copy is not an
application-consistent SQLite/home-and-workspace backup. Check offsite coverage
of a completed quiescent backup and periodically test restoring it in isolation;
do not treat a successful Restic run alone as proof of database recovery.
Existing audit backups remain
under `bootstrap-backups/chief-of-staff-20261022T1730Z` and its `-workspace`
companion. Detailed historical test evidence is attached to
[PR #338](https://github.com/repparw/nix/pull/338).

## Validate and activate

1. Run the [configuration verification skill](../../.agents/skills/verify-nixos-config/SKILL.md).
   Inspect the effective Hermes settings and managed home files. Build the full
   Epsilon system; CI's stubbed host evaluation does not replace that build.
   Run `hermes-chief-of-staff`, Hermes triage, formatting, and agent-docs checks.
2. Review the closure difference and dry-activation plan. Verify the actual
   selected Node runtime, including the container wrapper. Resolve build failures
   before clearing a deployment pause. Keep intentionally stopped services stopped
   until their restart is authorized.
3. Take the fresh quiescent backups above, then use the normal controller
   transaction in the fleet skill. Preserve existing provider credentials, memory,
   history, workspace, and runtime settings outside the managed configuration.
4. Check the gateway's executable, environment paths, ownership, provider access,
   manual approvals, and persisted state after activation. Verify that the
   gateway and any enabled Desktop/dashboard backend have
   `HERMES_MANAGED=false`, the home `.managed` marker reads `false`, and
   managed-scope approval/resource keys still reject runtime overrides.
   Test Discord replies, task continuity, delegation, and approval denial
   before accepting production operation. A successful isolated CLI test does
   not prove the Discord path.

## Check continuity safely

Use a separate private `HERMES_HOME` with copies of existing state and auth.
Disable dispatch and notifications; never start a second Discord gateway or copy
refreshed test credentials back over production.

In independent sessions, record a tagged decision, create and claim one native
Kanban card, save a real delegation result, block the card, then recover the
original decision and result through session search. Repeat the request and
verify that no duplicate card or worker appears. Independently check the artifact,
then complete the same card with structured metadata. Inspect actual database
records as well as model replies. The live, privately maintained
`.hermes/skills/chief-of-staff/SKILL.md` defines handoff and ownership rules;
Nix no longer installs that personal skill.

The pre-activation isolated probes passed decision recall, historical retrieval,
blocked-card continuity, deduplication, native delegation, and verified completion
of a read-only documentation card. They did not prove abrupt-crash recovery,
forced compression, provider exhaustion, or the production Discord route.

## Recover

Stop the gateway and workers before restoring a matched, quiescent backup of
both `.hermes` and `workspace`. Preserve the current trees first; restore
databases from the backup helper's consistent SQLite copies, without original
WAL/SHM/journal sidecars, and restore `hermes:hermes` ownership inside the
container. Verify SQLite integrity, the live `SOUL.md`, Chief of Staff skill,
runtime `config.yaml` (including model/tool preferences), memories, sessions,
Kanban and provider access before restarting. Restore the private
`hermes-config` checkout only as a checkpoint source, not as a replacement
for the full home and workspace backup.

If restoring from an offsite Restic snapshot taken while Hermes was active,
first restore it to an isolated location and verify the databases with their
associated sidecars; the live filesystem snapshot is not guaranteed consistent.
Do not promote an unverified restore to production. Nix rollback reinstates
Nix-owned installation, wiring, and safety declarations on activation; it does
not roll back private runtime preferences or personal behavior, credentials,
history, database writes, or other mutable state.
