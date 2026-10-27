---
type: Runbook
title: Run Moonshine host verification on Alpha
description: Run portable host smoke and opt-in real-TV Moonshine verification on Alpha.
when: Read before enabling the hardware runner or validating Moonshine on the LG C3.
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

## Default real-TV scenario: Steam and Sekiro

Use this manual scenario for changes that need real-client validation. It is
separate from the host smoke job and requires an available LG C3, Alpha and an
operator who can observe the screen. Do not add TV control or game credentials
to the disposable runner. Reserve the GPU and TV for the whole comparison and
confirm that no stream or game is active. Launching Moonshine's Steam Big
Picture application stops the desktop Steam client; make sure its current work
can be interrupted before proceeding. Keep the TV muted.

1. Record the deployed server version or commit, client version, display and
   game settings, and the exact source workload. Use the fork's TV verification
   plan and doctor before its guarded launch of Steam Big Picture. Start Sekiro
   through Steam's normal interface and use a safe, repeatable scene or route;
   avoid actions that change an important save. Record any game updates or
   settings changes that could affect a later comparison.
2. Start with 4K60 HEVC and the intended bitrate. Record the effective game,
   stream and client resolution and frame rate, rather than treating requested
   settings as negotiated values. Confirm real HDR source content and TV HDR
   mode independently. If Sekiro or the selected configuration does not provide
   genuine HDR, report it as SDR and use a separately verified HDR workload for
   the HDR case.
3. Observe visible playback on the physical TV and preserve timestamped host
   logs and Moonlight's performance overlay. Record codec, bitrate, network
   latency, frame drops, host processing and client decode/display evidence
   where available, plus stalls and recovery. Mark unavailable measurements
   as unavailable. A launch response, host frame count or TV video-input status
   alone does not prove visible playback or unique frame presentation.
4. For performance comparisons, use the same scene, route, settings, client and
   network for the deployed baseline, current upstream and each candidate.
   Warm up and run repeated interleaved comparisons; retain every run, including
   failures. A game with variable camera motion or unlocked frame rate needs a
   reproducible sequence before its timings can support a speedup claim.
5. Stop the owned test through Moonlight's normal interface, verify the host
   session ended, and retain the evidence locally. Do not force-close another
   session or power-cycle the TV. Do not publish device identifiers, credentials,
   private paths, or game-save data with upstream contributions.

The existing host smoke remains the default automated check. A successful
Sekiro run is a real-game integration case; it does not replace the controlled
HDR comparison or establish a change's GPU lifetime safety.

The [GitHub pre-job hook contract](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/run-scripts)
defines access to default context variables and refusal on a nonzero exit.
