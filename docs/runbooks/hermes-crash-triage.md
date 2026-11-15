---
type: Runbook
title: Hermes crash triage
description: Inspect queued coredumps, investigation results, and repeated-crash suppression.
when: Read when a coredump notification repeats, a crash needs investigation, or Hermes crash intake stops working.
resource: modules/aspects/services/coredump-watch/collector.py
tags: [hermes, coredump, alpha, epsilon, alerting]
---

# Hermes crash triage

Alpha collects systemd coredump metadata every 15 minutes. The collector stores
each event in `/var/lib/fleet-health/coredumps-outbox` before it advances its
journal cursor. It sends JSON to Epsilon's fixed `hermes-crash-ingest` command
over the existing fleet SSH identity. If delivery fails, the event stays in the
outbox. A matching durable receipt removes it.

Hermes reads the private inbox at `/var/lib/hermes/.hermes/crash/inbox`. The
native gate counts occurrences. A fingerprint combines the executable and
build, the signal, and the stack. The gate selects only fingerprints it has not
seen before for investigation. Repeated occurrences do not wake the model. When research or delivery fails, the investigation stays pending
with a retry delay. Successful research means the crash was investigated, not
repaired.

The scheduled agent has web research tools only. It checks primary upstream
sources and sends a Discord report only when an operator must act or an outage
needs attention. Routine findings and confirmed upstream waits stay silent. The
collector keeps the existing Wine mute.

A matching library or subsystem is not enough evidence for a diagnosis. Security
reports need a verified affected build and evidence of the specific trigger.
Harmless process-exit crashes and optional patches awaiting upstream review
normally stay silent. If one case warrants a report, the agent leaves out
unrelated unresolved cases and reports only the verified finding, the impact,
the required action, and the primary source.

Crash events exclude arguments, environment variables, and core memory. The
collector normalizes and bounds stack frames. Treat the event files as private
diagnostic data.

## Inspect the producer

Read `journalctl -u fleet-health-coredumps.service` on Alpha. A delivery failure
leaves JSON files in the outbox. The cursor and the delivery receipts are
separate, so a failed network connection cannot discard crashes.

Initial enrollment reads the preceding 24 hours. If the journal cursor was
vacuumed, the next run uses that overlapping baseline. Receipt identities
prevent repeated counts when the baseline is replayed.

## Inspect Hermes

Inspect the `Fleet crash triage` cron job, its output, and its `last_error` and
`last_delivery_error` fields. Inside the container, `.hermes/crash/state.json`
records occurrence counts, pending investigations, retry delays, and completed
research. The same files appear on Epsilon under
`/home/repparw/services/hermes/.hermes/crash`.

The packaged enrollment script is `.hermes/scripts/crash_triage_enroll.py`.
After deployment, run it with the installed Hermes Python environment. It
creates one job, or updates the existing job without duplicating it.

A known-wait rule must match the exact crash fingerprint and cite its upstream
dependency. Never mute all wpaperd crashes because one historical issue is
waiting upstream. The existing workaround for the output-removal race does not
show that the observed Mesa index-draw crash has the same cause.
