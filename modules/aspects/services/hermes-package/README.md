# Hermes package-update triage

Turns deployed package-version changes into a weekly, deduplicated research
digest. It reports on packages that actually reached a host, not on what is
available upstream.

## Flow

1. `fleet-update deploy` converges the fleet. After convergence it parses each
   reached host's recorded `nix store diff-closures` output
   (`$FLEET_UPDATE_STATE/diff-<host>.txt`) through
   `modules/scripts/package-update-event.py`, which emits a protocol-v1 event
   containing only relevant packages with a real version transition — filtered
   from the fleet's triage tiers (kernel, Mesa, systemd, Nix, plus Gamescope,
   Moonshine, Steam, Niri, Neovim, Heroic, Jellyfin, Firefox, Chromium,
   Authelia). Path additions and removals, size-only rebuilds, and unknown
   packages are omitted; the raw diff stays on disk.

2. Pi persists each serialized event atomically in a private outbox before
   rollback-root cleanup. Its independent `fleet-package-deliver.timer` attempts
   delivery every five minutes, even when deployment automation is paused or
   no new deployment occurs. Deployment performs no intake SSH call. Temporary
   Epsilon unavailability retains the original event bytes and timestamp.
   Entries leave the outbox only after a valid JSON acknowledgement names the
   exact event ID.
3. `hermes-package-ingest` accepts one protocol-v1 JSON event on standard input.
   It validates the event, drops root privileges to the existing Hermes home
   owner, and durably stores private receipts and inbox entries before
   returning an acknowledgement. Receipts reject a reused event ID with
   different content, including after the inbox has been consumed.

4. The weekly cron gate groups events by host and upgrade set. Repeats update
   counts without another model call. A successful observed scheduler
   completion marks the upgrade reported; a failed provider or delivery stays
   pending with a bounded backoff, so the same upgrade is never reported twice.

5. The research prompt directs Hermes to primary upstream sources only: it
   verifies each transition against the release notes for that exact version,
   prioritizes the fleet's high-interest packages, and replies `[SILENT]` when
   nothing is noteworthy. Delivery is Discord via the same channel pattern as
   Arr; a silent run means no message.

## Suppression

`_package.nix` accepts `knownWaits`, a trusted mapping from exact fingerprint to
a note, currently empty. A suppressed fingerprint stays unreported until it
leaves the catalog.

## Enrollment

After deployment, explicitly run `package_triage_enroll.py` with the installed
Hermes Python environment, as the container's Hermes user. Enrollment is
idempotent and preserves an existing job's schedule and enabled state, matching
the crash triage procedure. The persisted job survives gateway restarts;
deployment does not automatically create or resume jobs.

For an immediate run, call `cron.jobs.trigger_job("Fleet package triage")` in
that environment.

## Limitations

- Reporting describes packages that actually converged at the named revision; hosts that deferred a
  deployment are not covered until they converge.
- The event carries version metadata only. It does not carry the raw closure
  diff, so Hermes researches the upstream release for the transition it is
  given.
- The weekly schedule is the delivery cadence; a deployment that happens two
  minutes earlier is reported one week earlier at most.
