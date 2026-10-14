# Hermes crash intake

The host command `hermes-crash-ingest` accepts one protocol-v1 JSON event on
standard input. It validates the event, drops root privileges to the existing
Hermes home owner, and durably stores private receipts and inbox entries before
returning an acknowledgement. Receipts reject a reused event ID with different
content, including after the inbox has been consumed.

The native cron script groups occurrences by host, exact executable build,
application unit, signal, and normalized stack. Transient hexadecimal scope
suffixes are removed from unit identity. Repeats update counts without another
model call. A successful observed scheduler completion marks an investigation
complete; it never marks a crash resolved. Provider or delivery failures stay
pending and retry with a bounded backoff.

`_package.nix` accepts `knownWaits`, a trusted mapping from exact fingerprint to
an upstream issue URL. Pass this argument at the import in `hermes.nix` and
rebuild to update the immutable catalog. The default catalog is empty. The
wpaperd output-removal waiter does not cover the observed Mesa crash and must
not be used to suppress it.

After deployment, explicitly run `crash_triage_enroll.py` with the installed
Hermes Python environment, as the container's Hermes user. Enrollment is
idempotent and preserves an existing job's schedule and enabled state. It uses
the same Discord home channel as Arr, with only the `web` toolset and MCP
disabled. The persisted job survives gateway restarts; deployment does not
automatically create or resume jobs.

For an immediate run, call `cron.jobs.trigger_job("Fleet crash triage")` in
that environment. The running gateway executes it on its next scheduler tick,
including normal output persistence and delivery handling. Historical crash
metadata alone does not establish a current service outage.
