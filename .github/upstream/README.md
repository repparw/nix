# Upstream watcher migration

`upstream-watch.yml` inspects the current `main` pins after lock publication,
manual lock merges, and manual dispatch. The lock updater owns input changes.

The Authelia watcher is the only active CI publisher. All other detectors are
read-only. Their cleanup patches in `cleanup/` preserve the prepared migrations
from drafts #29, #30 and #32 and the remaining local watchers. `git apply
--check` must pass against the exact candidate base before a cleanup is used.
A patch conflict requires review, never a fuzzy edit or forced application.

Before transferring publication authority from a local timer, verify the live
Authelia lifecycle: create the expected cleanup PR, pass candidate-SHA CI with
the native ARM build, reuse the PR without modifying its branch or repeating
CI, merge it, then observe completion on `main`. A waiting-path run and fixture
tests do not satisfy this gate. Until then, keep the existing local publication
owners and the three prepared draft PRs. After cutover, close replaced drafts
and disable each local timer when its CI replacement becomes active.

For each future cleanup candidate, evaluate every host without updating the
lock. Build the actual upstream package, not the package stubs in configuration
checks, and dispatch CI on its exact SHA. Package-specific gates:

| Watcher           | Additional verification                                                                                   |
| ----------------- | --------------------------------------------------------------------------------------------------------- |
| t3code-connect    | Desktop and server bundles contain the configured Connect identifiers; desktop entry supports the scheme  |
| t3code-split      | Native ARM CLI builds, Pi/Epsilon select it with no Electron in the closure; Alpha selects/builds desktop |
| t3code-server     | Generated unit preserves web arguments, package selection, Connect environment and restart policy         |
| tasks-org         | Build the upstream Tasks.org package                                                                      |
| qbittorrent       | Pinned source tag contains upstream #24055; build the unpatched no-X package                              |
| cliamp-hm-module  | Generated Home Manager unit and settings preserve current behavior                                        |
| cliamp-attach     | Build upstream cliamp and verify both attach and quit in its help output                                  |
| wpaperd-fix       | Pinned source contains 442b962; build the unpatched package                                               |
| voxtype-graphical | Generated unit uses graphical-session.target for PartOf, After and WantedBy                               |
| gamescope-vkroots | Inspect source after Nixpkgs patches at both flagged-queue lookup sites; build with enableWsi=true        |

Nautilus is notify-only. Moonshine keeps host-owned completion until deployment
and safe runtime-override removal are verified. Sonarr/Jellyfin depends on the
running service version and remains host-owned. Gamescope needs source and
build verification, and does not require a GPU or Alpha runtime test.

The runtime predicates of the host-owned watchers moved to Pi: the
`fleet-readiness-probe` service evaluates the running Sonarr version, the
Sonarr log gate, Moonshine's PR227 test-build drop-ins, its candidate GC root
and stream activity over SSH, enqueues a durable event per status change, and
`fleet-readiness-deliver` posts queued events to Discord on an independent
timer. It also runs after each Alpha convergence, non-blocking for the
deployment. Until the replacement is verified on Pi, Alpha's
`watch-moonshine-pr227` and `watch-sonarr-jellyfin` timers remain armed and
stay the completion owners.

Run `python3 .github/scripts/upstream-readiness.test.py` for detector fixtures,
and `python3 .github/scripts/upstream-pilot.test.py` for the pilot lifecycle.

## Lock candidate planner (Authelia pilot only)

`upstream-plan.py plan --old BASE --candidate CANDIDATE` runs **before** the lock
updater publishes to main. Watcher contracts live in `watchers.json`.
Only Authelia has `mode=atomic`; independent watchers remain detection-only,
with their prepared cleanup patches and local publication owners unchanged.

If the candidate Nixpkgs pin contains the Authelia fix and `nixos-unstable`
contains it too, the updater applies the narrowly validated Authelia removal,
then publishes a stable `automation/atomic-authelia-pnpm-hash` branch and a
review-required **combined lock + cleanup PR**. It dispatches exact-SHA CI with
native ARM Authelia enabled, and **never fast-forwards main automatically**.
Repeat runs leave the combined PR and branch unchanged, even when new upstream
pins are available. A dangling branch, malformed cleanup or unavailable API
blocks publication rather than overwriting human changes or publishing a
potentially incompatible pin.

If the atomic predicate is negative, the original lock-only CI and compare-and-
swap fast-forward remain unchanged. If ancestry is unavailable, or a candidate
contains the fix before the authoritative channel, publication fails closed.
The existing `upstream-watch` post-lock pilot remains responsible for normal
read-only readiness and completion on `main`. This PR does not turn on other
publishers or disable local timers. When Authelia's live cutover is proven, the
remaining post-lock cleanup policies can be activated individually.

## T3 Code nightly-v2 (read-only, #209)

The `t3code-nightly-v2` detector tracks a stable, non-prerelease T3 Code
release containing orchestrator-v2 merge `de343914`, the corresponding
`nixos-unstable` package source, and the root Nixpkgs pin. The check uses
exact tag ancestry and verifies the pinned tag against a stable GitHub Release.
Statuses are `waiting-upstream`, `waiting-unstable`,
`merged-not-pinned`, and `PINNED-READY` (or unavailable on API errors).

This is detection only. The Alpha `watch-t3code-nightly-v2.timer` retains
publication and runtime completion ownership until stable v2 is deployed and
verified; protect `statev2.sqlite` and never restart active conversations as
part of readiness checks. The existing #209 issue tracks retirement.
