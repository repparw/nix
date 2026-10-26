---
type: Runbook
title: Run Moonshine host verification on Alpha
description: Prepare the opt-in disposable runner and retain portable host smoke evidence.
when: Read before enabling or dispatching the Alpha Moonshine hardware runner.
resource: modules/aspects/moonshine-verification.nix
tags: [moonshine, alpha, verification, github-actions]
---

# Run Moonshine host verification on Alpha

This configuration is disabled by default and has not been activated or tested
as a runner. Its first live run must validate container GPU access, the isolated
user bus, idle refusal, job-hook refusal and artifact upload before unattended use.

The container has a disposable root, its own user manager and PulseAudio socket,
and explicit render/uinput/uhid access. It shares the host network and read-only
Nix store/daemon access, but no desktop home, user bus or TV configuration.
It is a trusted-code execution environment, not a hostile-code sandbox.

Configure `services.moonshineVerification.enable = true` and a consumer-scoped
SOPS PAT at `services.moonshineVerification.tokenFile`. Do not put a token in a
Nix expression or workflow. Review and deploy through the normal fleet process.
The token needs runner registration access to this repository; the runner does
not join the public Moonshine repository.

After reserving Alpha, start `container@moonshine-verification.service` manually.
Startup refuses an active Moonshine session or a non-idle graphical login.
Dispatch `moonshine-host-smoke.yml` from `main` with a listed trusted fork branch
and the idle confirmation. The immutable pre-job hook refuses other events,
repositories and workflow refs before their steps execute. It requires GitHub's
default context variables; missing variables fail closed.

The workflow builds inside Moonshine's development shell using this fleet's
nixpkgs, then runs the existing doctor and smoke commands. It uploads the source
SHA, `run.log`, `report.json` and `moonshine-bench.log`. It does not run a benchmark
matrix, control the deployed server or access a TV. The verifier must be present
on the selected branch; `main` becomes usable after the portable verifier lands.

The runner accepts one job, with a 20-minute job limit and 25-minute service
limit. The container stops after 30 minutes. Stop the container after collecting
artifacts to discard its filesystem. Do not interrupt an operator-owned session.
An idle check is advisory: reserve the host for the entire run and recheck it
before dispatch. TV tests remain separately authorized and opt-in.

The [GitHub pre-job hook contract](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/run-scripts)
defines access to default context variables and refusal on a nonzero exit.
