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

Authelia's pnpm-hash override was retired in #237, and the atomic lock planner
and pilot publisher stay armed anyway: `upstream-plan.py` requires exactly one
`atomic` contract, so `authelia-pnpm-hash` remains in `watchers.json`, the
detector reports `completed` while the override marker is absent from
`modules/_services/authelia.nix`, and its cleanup runs through the byte-exact
module handler in `upstream-plan.py` rather than a recipe in `cleanup/`.
Independent `post-lock` contracts publish separate review-required PRs using
the recipes in `cleanup/`. Each candidate starts at the same checked-out main
revision.
`git apply --check` must pass before publication. A conflict requires review.
One failed recipe does not prevent other watchers from processing.

Post-lock workarounds live under `modules/aspects/upstream/`. Existing
`den.aspects` declarations keep their original names and consumers; file
location does not change the provided aspect. Helpers in
`modules/aspects/upstream/_overlays/` are explicitly imported by permanent
modules and excluded from recursive `import-tree` discovery. A cleanup
recipe removes both the temporary helper/aspect and the permanent reference
to it. The test suite checks that these recipes still apply to the current
worktree before their corresponding upstream pin becomes ready. The existing
T3 Code server migration (#402) is independently retiring its watcher.

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
| t3code-server     | Generated unit preserves web arguments, package selection, Connect environment and restart policy                                       |
| t3code-stable010  | Generated units serve the root-pin package (Alpha stock, Pi/Epsilon split server) with the version assertion; Alpha's x86 t3code builds |
| tasks-org         | Build the upstream Tasks.org package                                                                                                    |
| qbittorrent       | Pinned source tag contains upstream #24055; build the unpatched no-X package                                                            |
| wpaperd-fix       | Pinned source contains 442b962; build the unpatched package                                                                             |
| voxtype-graphical | Generated unit uses graphical-session.target for PartOf, After and WantedBy                                                             |
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
its byte-exact cleanup handler and native ARM validation, and every combined
candidate merge-automates under the #265 policy: the registry checker is the
sole landing decision and the cleanup is declarative. Independent watchers without
the flag publish through the separate post-lock sweep.

If the candidate Nixpkgs pin contains the Authelia fix and `nixos-unstable`
contains it too, the updater applies the narrowly validated Authelia removal,
then publishes a stable `automation/atomic-cleanup` branch and a
**combined lock + PR**. It dispatches exact-SHA CI with
native ARM Authelia enabled, and arms auto-merge: GitHub merges exactly when
the required checks pass and the branch is strict up-to-date with main, never
with pending or failed checks. The required PR CI itself runs the native ARM
Authelia build (and the bundled package validations) for atomic candidates,
so the build result gates the merge directly rather than relying on the
updater waiting. When main advances first, the updater re-plans
and re-applies the recipe onto the new main and revalidates — but only when
the existing branch tip is provably its own earlier candidate (the recipe
applied to its parent); a tampered or changed candidate requires review and
is never overwritten. Repeat runs reuse the combined PR and branch without
overwriting human edits or repeating successful CI, dispatching only missing
checks on the exact SHA. Enforced PR checks on the automation branch are
approved with a dedicated approval token (`LOCK_UPDATE_APPROVAL_TOKEN`: a
fine-grained PAT with Actions read+write on this repo, or an App installation
token with actions:write), after verifying the exact
candidate. A candidate is merge-eligible only when its exact SHA, ownership,
watcher manifest, required validation results, and current base are ALL
verified. Publication records trustworthy provenance (a state ref plus a
PR-body trailer); any recovered tip that is not the published SHA — including
a lockfile-only amendment that keeps the cleanups byte-identical — fails
closed, and the planner re-run on the recovered lock is the backstop against
forged provenance. A dangling branch, malformed cleanup or unavailable API
blocks publication rather than overwriting human changes or publishing a
potentially incompatible pin. Until the owner stores the approval token, any
approval-gated run fails closed with a message naming the secret instead of
arming auto-merge.

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

## T3 Code stable version bridge (#288, #289)

The `t3code-stable010` watcher retains its original ID and now tracks the
0.1.1 version bridge. The bridge builds the desktop package from the
existing Nixpkgs recipe with verified release source and pnpm hashes;
the same override applies on all architectures. The separate split aspect
selects the server-only package on Pi and Epsilon. Its detector reuses the nightly-v2
`PINNED-READY` gate plus a 0.1.1 minimum: only a stable
orchestrator-v2 release at least as new as the bridge in the root Nixpkgs
pin may drop the bridge,
because an earlier drop downgrades Alpha to V1 0.0.45 and breaks Android/web
clients. The post-lock cleanup is the complete cutover: it deletes the
bridge aspect, removes its entity includes so every host serves the
root-pin package (Alpha stock, Pi/Epsilon the `t3code-split` server-only
build) and arms the `t3code >= 0.1.1`
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
Alpha's x86 `t3code`. The nightly aspect is already retired: no entity
included it after #288, and deleting the file completes the
`t3code-nightly-v2` detector through the `WORKAROUNDS` path contract
(draft #285 was superseded by this cleanup). Watcher-id retirement for
both `t3code-nightly-v2` and `t3code-stable010` in `watchers.json` stays
a human merge-time chore; Alpha's `watch-t3code-nightly-v2.timer` keeps
runtime completion ownership until its issue-gate proof lands. Protect
`statev2.sqlite` and preserve active conversations while the bridge is
dropped.
