---
type: Research
title: Hermes decision-gate pilot
description: Measurement-first experiment for reducing repeated Hermes investigations without suppressing important events.
when: Before adding model routing or workflow-learning to Hermes intake.
resource: docs/runbooks/hermes-crash-triage.md
tags: [hermes, automation, evaluation, triage]
---

# Hermes decision-gate pilot

## Decision

Do not install AgentRun or add an LLM classifier yet. Existing crash intake already fingerprints and suppresses repeated occurrences, and the change-detection service already performs deterministic extraction. First measure what *actually* wakes Hermes unnecessarily. Preserve current notification, delivery, and retry semantics.

## Scope and baseline

Start with crash triage on Epsilon; package-update research is a second candidate only after its deployed behavior is inspected. Observe a representative sample of scheduled runs and record (without secrets, event payloads, or prompts):

- Scheduled runs, runs with new fingerprints, investigations launched, research retries, and Discord reports.
- Repeated fingerprints skipped by the existing gate.
- Model calls/tokens and estimated cost, if exposed by the runtime.
- Time to first useful result and failures requiring operator action.

Record the denominator and observation period. Never claim savings from a run that was already skipped by the current gate.

## Proposed shadow-only gate

For each already-admitted *new* fingerprint, produce a versioned decision record with: fingerprint identifier, rule version, evidence category, route (`research` / `defer` / `operator-review`), and reason code. Run in **shadow mode**: compute the proposed route but continue the existing Hermes investigation unchanged. No changes to delivery, inbox consumption, receipts, or Discord notification.

Initially use deterministic rules only. Any uncertain case routes to research. Do not use a general-purpose model to decide whether security or operational events can be discarded.

## Safety invariants

- New security-relevant signals, unknown fingerprints, suspected outages, and missing evidence must not be silently suppressed.
- A failed gate or malformed decision falls back to the existing investigation path.
- Research failures remain pending with existing retry behavior; a completed investigation does not imply a repair.
- Deduplication identities and durable receipts remain unchanged.
- Do not include process arguments, environment, core memory, secrets, or unbounded stack traces in metrics.
- Human review is required before any shadow decision can affect live routing.

## Evaluation

Compare shadow decisions with the existing investigation outcome. Track false deferrals (especially any actionable or security-relevant finding), unnecessary investigations, latency, and marginal model cost. Review individual disagreements, not just aggregate accuracy.

**Go/no-go:** only propose enforcement if no actionable findings were deferred in the evaluation sample, the sample includes meaningful novel events, and the measured reduction is material. Zero observed misses is not proof of zero risk; keep a conservative fallback and rollback switch. If the existing gate already removes most redundant work, stop the experiment.

## Implementation sequence

1. Identify the deployed Hermes intake code, scheduled job, and current counters; establish baseline.
2. Add privacy-safe counters and a read-only shadow decision artifact, with fixture tests for unknown, duplicate, security, malformed, and retry cases.
3. Run replay tests with historical sanitized event fixtures; then observe live shadow decisions.
4. Review findings and costs in a follow-up PR. Only then consider selective routing or AgentRun DSL.

No changes to deployment, notifications, model permissions, or live event suppression are authorized by this document.
