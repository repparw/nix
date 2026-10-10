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

Run `python3 .github/scripts/upstream-readiness.test.py` for detector fixtures,
and `python3 .github/scripts/upstream-pilot.test.py` for the pilot lifecycle.
