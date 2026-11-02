# Upstream watcher migration

## FSR 4.1 on Alpha's RDNA2 GPU (#323)

`fsr4-rdna2` is notify-only. Until a source-reviewed and runtime-tested
support commit is recorded in `watchers.json`, stable GE-Proton releases
newer than the recorded baseline with FSR4/RDNA2 changes produce a
deduplicated `upstream-review-required:<tag>` Discord notice. These notices
are candidates, not compatibility claims. AMD's Windows driver and Vulkan
announcements alone do not satisfy readiness. Discovery inspects up to 100
releases and fails closed if that bound is exhausted; advance the baseline
after reviewing candidates.

After the issue records the actual model, RADV requirements, real package
build and Alpha game verification (including Steam and Heroic/UMU), set
`support_commit` to the full reviewed GE-Proton SHA. CI then requires exact
ancestry in a stable upstream release and in the actual upstream release
archives packaged by both the root input's channel and root pin. A newer
version alone never produces `PINNED-READY`. Package layout changes and API
errors fail closed. Runtime completion and the choice of per-game/global
FSR activation remain with the issue owner; this watcher has no cleanup or
global configuration mutation.

`upstream-watch.yml` inspects the current `main` pins every two hours, after
successful lock publication, after manual lock merges, and on manual dispatch.
The lock updater owns input changes.

The registry includes the stable T3 orchestrator-v2 gate and the
[OpenCode v2 package detector](opencode-release-watch.md). Readiness notices
go to the run summary and Discord. Package readiness does not complete either
fleet runtime migration.

Independent `post-lock` contracts publish separate review-required PRs using
the recipes in `cleanup/`. Each candidate starts at the same checked-out main
revision.
`git apply --check` must pass before publication. A conflict requires review.
One failed recipe does not prevent other watchers from processing.

Post-lock workarounds live under `modules/aspects/upstream/`. Each module
contributes to its permanent owner through `den.aspects.<owner>.provides.<aspect>`,
without changing the provided aspect's name or explicit host includes.
The four former inline overrides (qBittorrent, Gamescope vkroots, Tasks.org,
wpaperd) are separate provided modules, not imports from their permanent
modules. Their cleanup recipes can therefore delete just the temporary
provider (plus any attached patch asset). The test suite checks each recipe
against the worktree. The T3 Code server migration retired its watcher in #402.

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

| Watcher           | Additional verification                                                                                                                 |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| t3code-connect    | Desktop and server bundles contain the configured Connect identifiers; desktop entry supports the scheme                                |
| t3code-split      | Native ARM CLI builds, Pi/Epsilon select it with no Electron in the closure; Alpha selects/builds desktop                               |
| t3code-stable010  | Generated units serve the root-pin package (Alpha stock, Pi/Epsilon split server) with the version assertion; Alpha's x86 t3code builds |
| tasks-org         | Build the upstream Tasks.org package                                                                                                    |
| qbittorrent       | Pinned source tag contains upstream #24055; build the unpatched no-X package                                                            |
| wpaperd-fix       | Pinned source contains 442b962; build the unpatched package                                                                             |
| gamescope-vkroots | Inspect source after Nixpkgs patches at both flagged-queue lookup sites; build with enableWsi=true                                      |
| nodejs-security   | Retired overlay family absent from the fleet; alpha's OpenCode builds against the pinned Bun and Node                                   |
| moonshine-pr227   | Pinned source contains PR227 and the UnitRemoved reload guard; Alpha selects the unpatched package and it builds                        |

Nautilus is notify-only. Ready notices print in every upstream-watch run
summary and, once per status change, post to the fleet Discord channel
through the approved bot identity (`DISCORD_BOT_TOKEN` +
`DISCORD_CHANNEL_ID`); delivery state lives on the
`automation/upstream-notify-state` ref, so a persistent status pings exactly
once. Workaround-holding watchers are `post-lock` instead — their cleanup PR
is the notice, and the removed workaround file disarms the watcher.
Sonarr/Jellyfin depends on
the running service version and remains host-owned; its local timer is
retired in favor of the verified Pi adapter below.

`tridactyl-reader` is notify-only for #316. It reads `tridactyl-vim` from the
pinned `firefox-addons` manifest and checks whether that release tag contains
tridactyl/tridactyl#5515. Nixpkgs' native messaging host does not determine
the extension version. CI pings Discord when the pin is ready. Browser
verification and removal of Obsidian Reader remain completion steps because
this checkout has no Obsidian Reader declaration to remove.

The Moonshine PR227 test build is declarative alpha config
(`modules/aspects/upstream/moonshine-pr227-test.nix`, #147): the generated unit
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
Notification and action are acknowledged separately: once a post is
accepted, its acknowledgment is persisted and retry cycles re-run only the
action, so an unreachable Alpha or a failing action never re-posts the
notification. Completion is verified against Alpha's manager, not the
start's exit code: the outcome is terminal only when the manager reports
the completion-owned units not-found (the watcher self-deletes them once
the scan drop and restart succeed); a start that gated out, a regressed
pre-gate run, or silence from the transport keeps the event queued for
retry, so the weekly Jellyfin scan drop cannot be orphaned by the
retirement.

Gamescope inspects `inputs.nixpkgs.legacyPackages`, bypassing repository
overlays. Alpha's patched package cannot establish upstream readiness. Its
cleanup retains WSI, removes only the queue workaround, and builds with
`enableWsi=true`. It requires no GPU or Alpha runtime test.

Run `python3 .github/scripts/upstream-readiness.test.py` for detector fixtures
and `python3 .github/scripts/upstream-publish.test.py` for independent
publication, interruption recovery, drift rejection, and notification deduplication.

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
the lock, and so does an unavailable readiness API. Only active apply-coupled
watchers can divert the lock update; their recipe-defined changes are
validated on the exact candidate commit. Atomic publication preserves the
exact-SHA CI, provenance, fail-closed recovery, strict up-to-date and
GitHub approval gates described by the lock-update workflow.

If the atomic predicate is negative, the original lock-only CI and compare-and-
swap fast-forward remain unchanged. If ancestry is unavailable, or a candidate
contains the fix before the authoritative channel, publication fails closed.
Independent cleanup candidates retain their own validation gates.

## T3 Code stable version bridge (#288, #289)

The `t3code-stable010` watcher retains its ID and tracks the stable 0.1.5 bridge. It builds the desktop package from the
existing Nixpkgs recipe with verified release source and pnpm hashes;
the same override applies on all architectures. The separate split aspect
selects the server-only package on Pi and Epsilon. Its detector requires a stable orchestrator-v2 release at least as new as 0.1.5 in the root Nixpkgs pin before dropping the bridge,
because an earlier drop downgrades Alpha to V1 0.0.45 and breaks Android/web
clients. The post-lock cleanup is the complete cutover: it deletes the
bridge aspect, removes its entity includes so every host serves the
root-pin package (Alpha stock, Pi/Epsilon the `t3code-split` server-only
build) and arms the `t3code >= 0.1.5`
version assertion in `t3code.nix` that keeps a pin regression from silently
downgrading `statev2.sqlite`. The `t3code-split` watcher independently keeps
the server-only layer until nixpkgs#555814 reaches the pin, then selects
`pkgs.t3code-cli`. Connect's `.env` build patch stays in its own overlay until
nixpkgs#555921 reaches the pin. Neither cleanup removes the shared launcher
or the Home Manager desktop entry. All three cleanup recipes are tested in
every order, and the version detector accepts both Nixpkgs package layouts.
A cleanup that conflicts with edited modules fails closed for review.
Candidate validation requires the `PINNED-READY` pin, checks every
generated `t3code-web` unit against the selected CLI (or the combined package
before the upstream split), and builds
Alpha's x86 `t3code`. The separate nightly migration watcher is retired;
the stable-version bridge retains its own release and pin gates. Preserve
`statev2.sqlite` and active conversations while the bridge is dropped.
