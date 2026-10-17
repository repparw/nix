# Upstream watcher migration

`upstream-watch.yml` inspects the current `main` pins every two hours, after
successful lock publication, after manual lock merges, and on manual dispatch.
The lock updater owns input changes.

The registry includes the stable T3 orchestrator-v2 gate and the
[OpenCode v2 package detector](opencode-release-watch.md). Readiness notices
go to #209 and #229 respectively. Package readiness does not complete either
fleet runtime migration.

Authelia retains its atomic lock planner and pilot publisher. Independent
`post-lock` contracts publish separate review-required PRs using the recipes
in `cleanup/`. Each candidate starts at the same checked-out main revision.
`git apply --check` must pass before publication. A conflict requires review.
One failed recipe does not prevent other watchers from processing.

The publisher uses `automation/upstream-<watcher>` branches. It reconstructs
the exact expected candidate tree before reusing an existing branch and
dispatches only missing checks. This also recovers interruptions between
branch publication, PR creation, and dispatch.

Candidates are merge-automated: GitHub merges exactly when the required
checks pass and the branch is current with main (strict up-to-date). When
main advances first, the publisher re-applies the recipe onto the new main
and revalidates — but only when the branch tip is provably its own earlier
candidate (the recipe applied to its parent); a tampered or changed
candidate requires review, and a recipe that no longer applies fails
closed. Nothing is merged with pending or failed checks.

Before disabling a local timer, verify its replacement's live CI run and all
of that watcher's completion checks. Fixtures prove the publication algorithm,
but do not prove a production cleanup or runtime cutover. Close replaced drafts
only after their replacement candidates pass validation.

Candidate CI evaluates every host without updating the lock. The required
aggregate also includes actual package builds and generated behavior checks
from `upstream-validate.py`. T3 split candidates use native x86 and ARM jobs.
The package-specific gates are:

| Watcher           | Additional verification                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| t3code-connect    | Desktop and server bundles contain the configured Connect identifiers; desktop entry supports the scheme         |
| t3code-split      | Native ARM CLI builds, Pi/Epsilon select it with no Electron in the closure; Alpha selects/builds desktop        |
| t3code-server     | Generated unit preserves web arguments, package selection, Connect environment and restart policy                |
| t3code-stable010  | Generated units fall back to the nightly package on every host; Alpha's x86 nightly builds                       |
| tasks-org         | Build the upstream Tasks.org package                                                                             |
| qbittorrent       | Pinned source tag contains upstream #24055; build the unpatched no-X package                                     |
| cliamp-hm-module  | Generated Home Manager unit and settings preserve current behavior                                               |
| cliamp-attach     | Build upstream cliamp and verify both attach and quit in its help output                                         |
| wpaperd-fix       | Pinned source contains 442b962; build the unpatched package                                                      |
| voxtype-graphical | Generated unit uses graphical-session.target for PartOf, After and WantedBy                                      |
| gamescope-vkroots | Inspect source after Nixpkgs patches at both flagged-queue lookup sites; build with enableWsi=true               |
| moonshine-pr227   | Pinned source contains PR227 and the UnitRemoved reload guard; Alpha selects the unpatched package and it builds |

Nautilus is notify-only. Ready notifications use tracked issues and durable
comment markers to avoid repeats. T3 receives readiness notices while
retaining its runtime completion checks. Sonarr/Jellyfin depends on
the running service version and remains host-owned; its local timer is
retired in favor of the verified Pi adapter below.

The Moonshine PR227 test build is declarative alpha config
(`modules/aspects/moonshine-pr227-test.nix`, #147): the generated unit
selects the test package, so activation and rollback belong to deploy-rs and
the `waiting-source` predicate requires the pinned upstream source to carry
the UnitRemoved reload guard before the cleanup candidate may publish. The
runtime predicates of the host-owned watchers moved to Pi: the
`fleet-readiness-probe` service evaluates the running Sonarr version, the
Sonarr log gate, and Moonshine's runtime-vs-generated-unit match over SSH,
enqueues a durable event per status change, and
`fleet-readiness-deliver` posts queued events to Discord on an independent
timer. It also runs after each Alpha convergence, non-blocking for the
deployment. The replacement is verified on Pi (durable per-watcher states
plus a drained event queue), so Alpha's `watch-moonshine-pr227` and
`watch-sonarr-jellyfin` timers are disarmed; their units and scripts remain
on Alpha and only Sonarr completion itself deletes them. The Sonarr/Jellyfin
completion action moved with it: the deliverer runs Alpha's one-shot watch
service after Discord accepts a delivered `sonarr-jellyfin` `ready` event.
A failed action leaves the event queued, at-least-once delivery retries
notification and action together, and a missing unit counts as terminal
clean, so the weekly Jellyfin scan drop cannot be orphaned by the
retirement.

Gamescope inspects `inputs.nixpkgs.legacyPackages`, bypassing repository
overlays. Alpha's patched package cannot establish upstream readiness. Its
cleanup retains WSI, removes only the queue workaround, and builds with
`enableWsi=true`. It requires no GPU or Alpha runtime test.

Run `python3 .github/scripts/upstream-readiness.test.py` for detector fixtures,
`python3 .github/scripts/upstream-pilot.test.py` for the Authelia pilot, and
`python3 .github/scripts/upstream-publish.test.py` for independent publication,
interruption recovery, drift rejection, and notification deduplication.

## Lock candidate planner (apply-coupled cleanups)

`upstream-plan.py plan --old BASE --candidate CANDIDATE` runs **before** the lock
updater publishes to main. Watcher contracts live in `watchers.json`.
Watchers with `coupling: apply` (qbittorrent, gamescope-vkroots,
moonshine-pr227) break the moment the candidate pin carries their fix — or any
context-shifting bump of their package — so their cleanup rides the lock
candidate instead of racing the post-lock sweep. Readiness runs against the
candidate tree; `PINNED-READY` diverts publication into a combined atomic
candidate. A watcher that is not ready but whose package the pin moved gets a
stubbed-phase compatibility build of the actual fleet package; failure blocks
the lock, and so does an unavailable readiness API. The Authelia pilot keeps
its byte-exact cleanup handler and native ARM validation, and any combined
candidate containing Authelia remains human-reviewed. Other apply-coupled
candidates arm auto-merge under the #265 policy. Independent watchers without
the flag publish through the separate post-lock sweep.

If the candidate Nixpkgs pin contains the Authelia fix and `nixos-unstable`
contains it too, the updater applies the narrowly validated Authelia removal,
then publishes a stable `automation/atomic-cleanup` branch and a
review-required **combined lock + cleanup PR**. It dispatches exact-SHA CI with
native ARM Authelia enabled, and **never fast-forwards main automatically**.
Repeat runs leave the combined PR and branch unchanged, even when new upstream
pins are available. A dangling branch, malformed cleanup or unavailable API
blocks publication rather than overwriting human changes or publishing a
potentially incompatible pin.

If the atomic predicate is negative, the original lock-only CI and compare-and-
swap fast-forward remain unchanged. If ancestry is unavailable, or a candidate
contains the fix before the authoritative channel, publication fails closed.
The existing Authelia post-lock pilot remains responsible for its readiness
and completion on `main` when the planner did not combine the cleanup with a
lock update. Independent cleanup candidates retain their own validation gates.

## T3 Code nightly-v2 (read-only, #209)

The `t3code-nightly-v2` detector tracks a stable, non-prerelease T3 Code
release containing orchestrator-v2 merge `de343914`, the corresponding
`nixos-unstable` package source, and the root Nixpkgs pin. The check uses
exact tag ancestry and verifies the pinned tag against a stable GitHub Release.
Statuses are `waiting-upstream`, `waiting-unstable`,
`merged-not-pinned`, and `PINNED-READY` (or unavailable on API errors).

CI posts a deduplicated readiness notice to #209. The Alpha
`watch-t3code-nightly-v2.timer` retains runtime completion ownership until the
fleet CI adapter is verified. Protect `statev2.sqlite` and preserve active
conversations during a cutover.

## T3 Code stable 0.1.0 bridge (#288, #289)

The `t3code-stable010` watcher retires the bridging overlay that serves
stable 0.1.0 from the upstream release archive ahead of nixpkgs#575132. Its
detector reuses the nightly-v2 `PINNED-READY` gate: only a stable
orchestrator-v2 release carrying the root Nixpkgs pin may drop the bridge,
because an earlier drop downgrades Alpha to V1 0.0.45 and breaks Android/web
clients. The post-lock cleanup restores the `t3code-nightly` includes for
Alpha, Pi and Epsilon, returning the fleet to the pre-bridge workload; the
human cutover (#285) then removes the nightly and asserts the pin version.
A cleanup that conflicts with an earlier cutover fails closed for review.
Candidate validation keeps every generated `t3code-web` unit on the nightly
package and builds Alpha's x86 nightly. Protect `statev2.sqlite` and
preserve active conversations while the bridge is dropped.
