---
type: Runbook
title: Hermes crash triage
description: Inspect queued coredumps, investigation results, and repeated-crash suppression.
when: Read when a coredump notification repeats, a crash needs investigation, or Hermes crash intake stops working.
resource: modules/aspects/services/coredump-watch/collector.py
tags: [hermes, coredump, alpha, epsilon, alerting]
---

# Hermes crash triage

Alpha collects systemd coredump metadata every 15 minutes. The collector stores each event in `/var/lib/fleet-health/coredumps-outbox` before advancing its journal cursor. It sends JSON to Epsilon's fixed `hermes-crash-ingest` command over the existing fleet SSH identity. Failed delivery retains the event. A matching durable receipt removes it from the outbox.

Hermes reads the private inbox at `/var/lib/hermes/.hermes/crash/inbox`. The native gate counts occurrences and selects new executable/build, signal, and stack fingerprints for investigation. Repeated occurrences do not wake the model. Research and delivery failures leave the investigation pending with a retry delay. Successful research means investigated, not repaired.

The scheduled agent has web research tools only. It checks primary upstream sources and sends a Discord report only for a concrete operator action or an outage that needs attention. Routine findings and confirmed upstream waits remain silent. The existing Wine mute remains in the collector.

A matching library or subsystem is not sufficient evidence for a diagnosis. Security reports require a verified affected build and evidence of the specific trigger. Harmless process-exit crashes and optional patches awaiting upstream review normally remain silent. If one case warrants a report, the agent omits unrelated unresolved cases and reports only the verified finding, impact, required action, and primary source.

Crash events exclude arguments, environment variables, and core memory. Stack frames are normalized and bounded. Treat the event files as private diagnostic data.

## Inspect the producer

Read `journalctl -u fleet-health-coredumps.service` on Alpha. A delivery failure leaves JSON files in the outbox. The cursor and delivery receipts are separate, so a failed network connection cannot discard crashes.

Initial enrollment reads the preceding 24 hours. A vacuumed journal cursor causes the next run to use that overlapping baseline. Receipt identities prevent repeated counts when the baseline is replayed.

## Inspect Hermes

Inspect the `Fleet crash triage` cron job, its output, and its `last_error` and `last_delivery_error` fields. Inside the container, `.hermes/crash/state.json` records occurrence counts, pending investigations, retry delays, and completed research. The same files are visible on Epsilon under `/home/repparw/services/hermes/.hermes/crash`.

The packaged enrollment script is `.hermes/scripts/crash_triage_enroll.py`. Run it with the installed Hermes Python environment after deployment. It creates one job or updates the existing job without duplicating it.

A known-wait rule must match the exact crash fingerprint and cite its upstream dependency. Never mute all wpaperd crashes because one historical issue is waiting upstream. The existing output-removal race workaround does not establish that the observed Mesa index-draw crash has the same cause.
