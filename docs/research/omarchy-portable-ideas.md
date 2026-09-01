---
type: Research Note
title: Omarchy Ideas Worth Porting to This NixOS Fleet
description: Source-backed review of DHH's Omarchy (Arch + Hyprland) manual and repo, extracting which of its opinionated patterns fit this den-aspect NixOS repository.
when: Read when planning update-pipeline hardening, theming ergonomics, host bootstrapping, agent-facing tooling, or docs style changes.
resource: modules/hosts/pi.nix
tags: [research, omarchy, updates, migrations, theming, bootstrap, fleet, docs, agents]
---

# Omarchy Ideas Worth Porting to This NixOS Fleet

Research date: 2026-09-01.

## Scope

Omarchy is DHH's opinionated Arch Linux + Hyprland distribution ("omakase
computing": a single blessed golden path, everything configured, nothing
asked).[^welcome] This note reads the full manual (51 sections) end to end,
verifies the ideas that matter against the actual `basecamp/omarchy` source at
HEAD (version `4.0.0.alpha`),[^version] and asks, idea by idea, what could port
to this repo — a den-aspect NixOS flake running a small fleet: `pi` (LAN edge
and the single flake.lock writer), `alpha` (desktop consumer host), `beta`
(parked), and `epsilon` (aarch64 VPS edge that took over apex/authelia/glance/
miniflux and hermes in the phase-2 cutover; it runs no auto-update pipeline
yet).[^epsilon][^hosts] Note: `docs/hosts.md` does not document epsilon and
still says pi fronts every vhost — it is stale relative to the cutover
comments in `modules/hosts/pi.nix`.[^hosts]

The repo already has a strong update story: pi runs a nightly
bump→probe→backup→build→push-lock→switch→soak→rollback pipeline, alpha pulls
pi's lock with health gates, a soak, rollback, and a circuit breaker, and the
stated invariant is "origin/main's flake.lock always equals the pin production
converged on".[^fleet-ops][^alpha] Many Omarchy ideas collide with that and
lose; a few fill real gaps.

## Ideas and verdicts

### 1. One-time migrations with state markers, run inside the update pipeline

**Verdict: ADOPT.**

What Omarchy does. Every `omarchy update` runs `omarchy-migrate` after package
upgrades: timestamped `migrations/*.sh` scripts in the Omarchy tree, with
per-user completion markers in `~/.local/state/omarchy/migrations/`, so each
script runs exactly once per machine/user and is safe to re-run.[^migrate-src][^migrations-skill] Omarchy documents the model as a contract: migrations are
one-time repair scripts for state that the package manager cannot own, they
must be idempotent, and they are written against the packages installed in the
same update — an explicit agent skill (`agents/skills/migrations.md`) tells AI
agents how to author them.[^migrations-skill] There are 103 shipped migrations
on HEAD.[^tree]

What this repo does today. Nothing equivalent. Nix makes *configuration*
switches atomic and rollbackable, but the fleet has mutable state that
upgrades do not touch: nspawn container configs under `/home/containers/config`,
restic repo layout, Discord webhook plumbing, automations state
files.[^fleet-ops] The gap is inferred from the absence of any repair
mechanism (no migration runner, no hook point in either update pipeline)
rather than from a runbook listing such repairs; sops key enrollment policy
lives in `docs/architecture/secret-inventory.md` and is likewise a manual,
per-host step. When one of these needs a one-time repair after a change,
today it is ad hoc by construction.

Why it ports. The pi auto-update pipeline is the natural hook — with one
placement caveat the first draft missed: pi's script exits early when the
lock is unchanged (`modules/hosts/pi.nix:265` "lock unchanged; nothing to
do"), so migrations must be checked *before* that early exit (or run on every
successful cycle), not only after a flip. Run any pending
`modules/migrations/*.sh` against a per-host state directory, wired via
systemd-native `onSuccess`/`postStart` rather than mutable hook directories
(see idea 6), exactly like `omarchy-migrate`'s `--pending`. The Omarchy
contract maps cleanly: idempotent scripts, state markers under
`/var/lib/<pipeline>/migrations/`, and a short agent-facing doc describing when
to add one. Alpha (consumer) runs the same runner after its gated flip;
epsilon has no pipeline yet, so its migrations wait until it gains one — an
explicit coverage hole this idea does not close. This is the single most
portable idea in the whole manual — the repo already has the hard part (a
trusted, unattended, self-rolling-back execution point).

### 2. A single guarded update path with transcript and bypass guard

**Verdict: ADAPT.**

What Omarchy does. `omarchy update` is the only blessed update path: it takes a
lock, checks free disk space, logs the whole session to a transcript
(`/tmp/omarchy-update.log`), supports an unattended `-y` mode, creates a
snapshot first, and runs migrations and post-update hooks afterwards.[^update-src] A libalpm hook (`default/libalpm/hooks/00-omarchy-update-guard.hook`)
intercepts direct `pacman -Syu` and refuses it unless the user passes an
explicit escape hatch (`OMARCHY_ALLOW_DIRECT_PACMAN=1`), pointing them back to
`omarchy update`.[^pacman-guard] Post-update, `omarchy-update-analyze-logs`
scans the transcript for anomalies.[^update-bin]

What this repo does today. The unattended path is strong (pi pipeline, alpha
gated flip), but the *manual* path is raw: `nh os switch` or
`nixos-rebuild switch` straight from the repo, and easy to run without the
gates from an interactive shell.[^fleet-ops][^runbook-rollback] One correction
to the first draft: the most important gate — the strict health probe — is
*already* a reusable binary (`fleet-health-probe --strict/--local`); the
runbook says verbatim that "the probe doubles as a library for
gates".[^fleet-ops] What is genuinely duplicated inline is the *orchestration*
around it: GC headroom check, `nvd diff` review, soak, and rollback logic live
separately in `modules/hosts/pi.nix` and `modules/hosts/alpha.nix`. Also note:
the repo has a second, unused update mechanism — `den.aspects.auto-upgrade`
(`system.autoUpgrade`) is included by no host, and the
`failed-auto-upgrade-rollback.md` runbook still claims it is enabled, which is
stale.[^auto-upgrade-aspect][^runbook-rollback] Epsilon runs no updater at all.

What to port. Not the libalpm hook (there is no pacman to guard; Nix
generations already make a bad manual switch reversible). Portable instead:
one shared orchestration wrapper, e.g. a `host-update` command per host built
from a den aspect, that does what pi's script does for interactive runs —
strict probe gate (reusing the existing probe), GC headroom check, `nvd diff`
shown before flipping, soak after, rollback on failure — so manual updates and
automated updates share one implementation. The wrapper must state lock
ownership explicitly: pi remains the single writer that bumps and pushes the
lock; consumers only pull. Before building, deprecate or delete the unused
`den.aspects.auto-upgrade` and fix the stale runbook so there is one canonical
updater story. Idea 5's `fleet update` subcommand is an alias over this
wrapper, not a second implementation. Omarchy's insight is that the guard only
works when the blessed path is *more* convenient than the raw one.

### 3. Release channels (stable / RC / edge / dev)

**Verdict: IGNORE.**

What Omarchy does. Four channels: stable tracks releases plus an Arch mirror
deliberately one month behind to catch breakage before users do; edge tracks
fresh builds; RC validates majors; dev links to a git checkout in
`~/omarchy`.[^updates-manual]

Why ignore. The repo already implements a better-fitting two-stage channel
with topology: pi is the single writer that bumps all inputs and pushes the
converged lock; alpha is a consumer that never bumps its own lock and only
flips when pi is healthy.[^alpha][^fleet-ops] That *is* "stable lags edge",
enforced by git rather than by a mirror. Adding a channel abstraction would be
ceremony without a third stage to justify it.

### 4. Theme as a switchable parameter over a color engine

**Verdict: ADAPT.**

What Omarchy does. Twenty-two themes, each a small directory: a
`colors.toml` palette plus per-app assets (backgrounds, `icons.theme`,
`neovim.lua`, `unlock.png`, `vscode.json`). One palette regenerates configs for
terminal, editor, browser, compositor, and the whole shell on switch; user
themes live in `~/.config/omarchy/themes` and win over system ones; third-party
themes installed from git have every executable-bearing file (`.lua`, terminal
configs, `vscode.json`) stripped so installing a theme can only change what
your desktop looks like, never what it runs; `~/.config/omarchy/themed/*.tpl`
templates let users theme apps Omarchy does not know, using `{{ color0 }}`
placeholders.[^themes-manual][^theme-making][^tree-themes]

What this repo does today. Stylix already plays the "one palette → all apps"
role — arguably Omarchy's `colors.toml` is a hand-rolled base16 engine. But the
theme is hardcoded as a single choice in the aspect: `tokyodark-terminal.yaml`
plus one pinned, dimmed Stalenhag wallpaper, with fonts and cursor fixed in
the same file.[^style] Switching the whole fleet's look means editing
`modules/aspects/style.nix`; there is no theme notion, no per-host variation,
and no second palette.

What to port. Restructure the style aspect around a theme *parameter*: a
small attrset of named themes (base16 scheme + wallpaper + polarity), an
option like `modules.style.theme = "tokyodark";`, and per-host overrides in
`modules/hosts/`. Omarchy's security rule is worth copying verbatim as design
commentary: a theme must never carry code — with Stylix this is naturally
true (schemes are data), so the port is mostly about naming and switching, not
sandboxing. The template mechanism (`themed/*.tpl`) is unnecessary; Stylix
targets cover the same need declaratively.

### 5. A unified, discoverable CLI for host operations (built agent-first)

**Verdict: ADAPT.**

What Omarchy does. One command, `omarchy`, is the command center for ~30
namespaced groups; every command takes `--help`, there is `omarchy commands
[--all] [--json] [--check]` for machine-readable discovery, and the manual
explicitly frames the CLI as the interface for AI agents working on the
system.[^cli-manual] The 444 `bin/` scripts are the implementation behind both
the menu and the CLI.[^tree]

What this repo does today. Helpers exist but are scattered and ad hoc:
`clip2qr` and `hotswap` as `writeShellApplication`s in the scripts aspect, the
fleet-health probe binary, the auto-update script embedded in
`modules/hosts/alpha.nix`, operator controls documented as raw `ssh pi`
one-liners.[^scripts][^fleet-ops] There is no single surface an agent (or the
user) can enumerate; knowledge of what exists lives in runbooks.

What to port. A namespaced host CLI composed as a den aspect, with the same
discovery contract: `fleet health probe`, `fleet backup status`,
`fleet update --dry-run`, `secrets rekey <host>`, `host debug` (a bundle:
generation, diff, failed units, journal tails — Omarchy's `omarchy debug`
idea). Generate the wrapper commands from a Nix attrset so the aspect stays
declarative, and mirror the menu in a `--json` listing so agents can discover
without reading source. The modification versus Omarchy: it must be built from
the aspects (single source of truth), not as a parallel script tree.

### 6. Event hook directories on the update pipeline

**Verdict: ADAPT.**

What Omarchy does. Well-defined lifecycle events expose hook directories
(`~/.config/omarchy/hooks/<event>.d/`) — `post-boot`, `post-update`,
`theme-set`, `battery-low` — each seeded with a `.sample` file, with
`omarchy hook install` to wire a script in; executables in the directory run
at the event.[^dotfiles-manual]

What this repo does today. The auto-update pipeline is a monolith: the flip,
the soak, the rollback, and the Discord notification all live inline in one
script, and there is no sanctioned way to attach behavior at lifecycle points
without editing it.[^alpha]

What to port. First-draft caution: Omarchy's hook directories are per-user,
session-scoped, and mutable (`~/.config/omarchy/hooks/<event>.d/`); copying
that shape onto a root-run unattended pipeline would create a mutable,
root-executed script directory — a persistence vector on the very pipeline
whose trustworthiness idea 1 depends on — and "Nix-declared state-backed
executables" is self-contradictory (a Nix-declared executable needs no hook
directory). Also, Omarchy orders migrations *before* its post-update hooks;
post-flip-after-soak placement would invert that. The portable, Nix-native
version is therefore not a directory convention but lifecycle wiring declared
in Nix: `systemd.services.<pipeline>.onSuccess` / `onFailure` (or
`postStart`) units that run the migration runner (idea 1) and future
per-host post-update behavior. Treat this idea as folded into idea 1's
mechanism, not a separate deliverable; skip the compositor-session events
(`theme-set`, `battery-low`) — desktop-shell concerns home-manager already
handles.

### 7. Seed-file unattended bootstrap for new hosts

**Verdict: ADAPT.**

What Omarchy does. The ISO checks for a `cidata`-labeled drive (the cloud-init
NoCloud convention) and, if present, skips the wizard entirely: disk layout,
hostname, credentials, SSH keys, and a Tailscale auth key all come from a
handful of plain files, making Omarchy a base image for VMs and fleet
machines; a `defer-provisioning` variant installs with no personal data at
all for handing machines to other people.[^unattended-manual][^getting-started]

What this repo does today. New-host onboarding is procedural: the pi deploy
runbook (SD image + flake activation), an in-repo authorized-keys location,
and sops age keys per host — but nothing that turns "blank machine" into
"fleet member" without someone walking through the steps by
hand.[^hosts][^deploy-pi]

What to port. Not the ISO mechanics — NixOS equivalents are `nixos-anywhere` /
`disko` territory. Portable is the *seed contract*: define one small
"new-host seed" format for this fleet (hostname, flake URL + ref, authorized
keys, Tailscale/auth material) and a runbook + helper that consumes it, so a
future host is a data file plus one command instead of a bespoke evening.
One hard correction from review: the seed file must *not* carry the sops age
private key in plaintext — that would violate the repo's sops-nix rule and be
worse than Omarchy's password *hash*. The age key is retrieved out-of-band
(or wrapped in sops immediately), and the seed media is destroyed after use —
Omarchy's own caveat ("treat the drive as the secret it is") applies
verbatim.[^unattended-manual]

### 8. Firmware updates as part of the update flow

**Verdict: ADOPT.**

What Omarchy does. `Update > Firmware` (backed by `omarchy-update-firmware`)
runs `fwupd` against the Linux Vendor Firmware Service on demand, noting that
some firmware only applies at reboot.[^updates-manual][^update-bin]

What this repo does today. Nothing manages firmware; the fleet keeps current
via flake bumps only, and a stale SSD/dock/dock-controller firmware is an
invisible failure class.

What to port. Trivial in NixOS: enable `services.fwupd` on the hardware hosts
(alpha at minimum) and surface it — either as an occasional manual `fwupdmgr
refresh && fwupdmgr get-updates` documented in the fleet runbook, or as a
fleet-health-style check that alerts when updates are pending. One-line aspect,
real coverage win.

### 9. Bootable filesystem snapshots and reset-to-baseline

**Verdict: IGNORE.**

What Omarchy does. Snapper snapshots before every update, bootable from the
Limine menu, restoring root but not `/home`; a baseline snapshot also powers
"reset computer" for handing a machine on.[^snapshots-manual][^security-manual]

Why ignore. NixOS generations already provide the same rollback story natively
— alpha boots systemd-boot with `configurationLimit = 10` and the rollback
runbook uses system profiles[^alpha][^runbook-rollback] — and the repo's data
recovery story is restic offsite, which is strictly stronger than
"root-only snapshots".[^fleet-ops] Scoping note from review: this is
alpha/beta-shaped (btrfs + systemd-boot); pi boots extlinux on an ext4 root,
where snapper is not applicable at all, and the btrfs aspect covers only
alpha's filesystems. The btrfs aspect adds scrub/balance/health and does not
include snapper; nothing here suggests that was a mistake.
`reset-to-baseline` for NixOS is just "redeploy the flake", which
reproducibility gives for free.

### 10. Defaults-vs-user-overrides dotfile split (`/usr/share/omarchy` vs `~/.config`)

**Verdict: IGNORE.**

What Omarchy does. Package-owned defaults in `/usr/share/omarchy` are never
edited; users override in `~/.config`; updates may push user edits to
`.bak` files; per-file and wholesale config resets exist
(`omarchy reinstall configs`).[^dotfiles-manual][^tweaks-manual]

Why ignore. This is Omarchy rebuilding, in shell, what home-manager and NixOS
options already do structurally: generated read-only defaults, declarative
overrides, atomic switch, and generation rollback. The repo's equivalent —
aspects generate configs, options override, `nh os switch` applies[^den-docs] —
has no mutable-defaults failure mode to guard against. Its keybinding story is
likewise already declarative in the compositor aspects rather than an override
file. Reading the Dotfiles chapter is a useful reminder of *why* the Nix model
is worth maintaining, not a source of features.

### 11. Crash capture surfaced to humans (and optionally agents)

**Verdict: ADAPT.**

What Omarchy does. The system watches systemd-coredump; on a segfault the user
gets a "Process crashed" notification which, when clicked, hands the core
dump to the default AI agent with a diagnose-crash skill; per-program muting
exists for known-noisy crashes.[^ai-manual]

What this repo does today. Fleet-health probes detect *services* being down
(HTTP surfaces, unit states) but say nothing about processes crashing
elsewhere — a silently-restarting user service or repeated coredumps on alpha
is invisible until something else fails.[^fleet-ops]

What to port. The cheap, high-value slice is the notification, not the agent:
a fleet-health check class that inspects `coredumpctl`/journal for new
coredumps since the last run and posts to Discord like any other probe.
Scoping note from review: this lands on **alpha only** — pi runs journald
volatile (`Storage=volatile`, 50M cap, an SD/eMMC wear tradeoff), so coredumps
there vanish at boot and detecting them reliably would require changing that
policy first.[^alpha] The agent-driven diagnosis is optional later (the repo
already runs agents as aspects); Omarchy's per-program mute list is worth
copying so known-buggy binaries don't cry wolf.

### 12. Manual-style docs: "Common tweaks", troubleshooting, and FAQ pages

**Verdict: ADAPT.**

What Omarchy does. Beyond the big chapters, the manual maintains three
patterns the repo lacks: *Common tweaks* — a page of small, named,
copy-paste-able adjustments, each stating which file to edit and warning that
updates may restore configs (moving changes to `.bak`); a *Troubleshooting*
page of symptom→fix pairs ("I broke my system with an update!", subsystem
restarts before rebooting); and an *FAQ* of one-answer questions, including a
"how do I remove all the extra software" escape hatch that deletes the whole
opinionated layer in one action.[^tweaks-manual][^troubleshooting-manual][^faq-manual]

What this repo does today. Docs are excellent for *procedures* (runbooks with
frontmatter routing, agent guidance) and *architecture*, but scattered for
*small* knowledge: the traefik SNI probe gotcha lives inside
`fleet-operations.md`, resize/scale fixes would live in host files, and there
is no symptom-indexed page.[^index][^fleet-ops]

What to port. Two low-cost pages following the existing frontmatter
convention: a `docs/tweaks.md` (named micro-adjustments with source-file
references, mirroring "Common tweaks") and a `docs/troubleshooting.md`
(symptom→diagnosis→fix, cross-linked from runbooks instead of duplicating
them, collecting gotchas like the SNI probe and the btrfs spindown wisdom).
This keeps the repo's agent-first routing intact while giving the
"small but recurring" knowledge a home.

### 13. Text extraction (OCR) as a built-in helper

**Verdict: ADAPT.**

What Omarchy does. `Super + Ctrl + PrtScr` selects a screen region, tesseract
extracts the text, and the result lands on the clipboard; dictation is
Voxtype with push-to-talk and a toggle binding.[^ocr-manual]

What this repo does today. Dictation is already ahead of Omarchy: the repo
runs Voxtype declaratively with a pinned version and a whole research note on
closing the Wispr Flow gap.[^wispr-note][^dictation] There is no OCR
extraction helper, but the pattern for one exists — `clip2qr` is exactly this
shape (input → process → clipboard) as a `writeShellApplication`.[^scripts]

What to port. A sibling `writeShellApplication` (`ocr2clip` or similar:
slurp region → grim → tesseract → wl-copy) in the scripts aspect, plus an
optional compositor binding in the wm aspect — desktop-host material, i.e.
**alpha only** (pi and epsilon are headless). Note the shape is the mirror of
`clip2qr`: clip2qr consumes the clipboard, OCR produces onto it. Small,
self-contained, and it completes the Omarchy capture set the repo otherwise
matches.

## What Omarchy does that this repo already does better

For completeness, three Omarchy pillars the repo has native answers for, so
they should not be re-imported even as adaptations:

- **Opinionated golden path.** Omarchy's "zero bloat, just everything I use"
  default stack maps to the repo's aspect composition and per-host includes;
  the den model is the same philosophy with better mechanics.[^den-docs][^welcome]
  Omarchy's own "Remove > Preinstalls" escape hatch[^faq-manual] is what the
  repo gets by simply not including an aspect.
- **AI-agent integration.** Omarchy ships a system-tailoring skill symlinked
  into agent skill dirs and lazy-loaded agent launchers;[^ai-manual] the repo
  already manages skills, agents, and their configuration as den aspects
  (`modules/aspects/ai/*`), with repo docs written for agent routing from
  day one.[^index]
- **Dictation.** Omarchy's dictation is Voxtype[^ocr-manual] — the same tool
  this repo already pins, configures, and researches.[^wispr-note]

## Summary table

| Idea | Verdict | One-line rationale |
|---|---|---|
| One-time migrations with state markers in the update pipeline | ADOPT | The repo has an unattended trusted execution point (pi pipeline) but no once-per-host state-repair mechanism; run via systemd lifecycle wiring, checked before the lock-unchanged early exit; pi + alpha only until epsilon gains a pipeline. |
| Single guarded update path with transcript | ADAPT | Health probe is already a reusable gate library; the gap is duplicated orchestration (GC/diff/soak/rollback) across pi.nix and alpha.nix — one wrapper, pi stays sole lock writer; deprecate unused `den.aspects.auto-upgrade` first. |
| Release channels (stable/RC/edge/dev) | IGNORE | pi-writer/alpha-consumer topology already implements staged rollout with git as the channel. |
| Theme as a switchable parameter | ADAPT | Stylix covers generation, but the theme is hardcoded in `style.nix`; make it a named, per-host option. |
| Unified discoverable host CLI (agent-first, `--json`) | ADAPT | Ops helpers are scattered across aspects and runbooks; one namespaced surface helps humans and agents — with `fleet update` aliasing the idea-2 wrapper, not re-implementing it. |
| Event hook directories on the update pipeline | ADAPT | Folded into idea 1: Nix-declared systemd `onSuccess`/`onFailure` lifecycle wiring, not mutable root-executable hook directories. |
| Seed-file unattended bootstrap for new hosts | ADAPT | Define a fleet "new-host seed" contract + runbook; age key stays out-of-band, never plaintext on the seed media. |
| Firmware updates in the update flow | ADOPT | `services.fwupd` on hardware hosts is a one-line aspect closing a real coverage gap. |
| Bootable snapshots / reset-to-baseline | IGNORE | Nix generations + restic offsite already exceed root-only snapshot recovery (alpha/beta-shaped; pi's ext4/extlinux makes snapper moot there). |
| Defaults-vs-user-override dotfile split | IGNORE | home-manager/NixOS options are the structural answer Omarchy approximates in shell. |
| Crash capture surfaced to humans | ADAPT | Fleet-health probes services, not coredumps; a coredump check class closes that blind spot on alpha (pi's volatile journald rules it out there). |
| Common tweaks / Troubleshooting / FAQ docs | ADAPT | Small recurring knowledge needs a symptom-indexed home alongside the existing runbooks; the stale `hosts.md`/`failed-auto-upgrade-rollback.md` are first candidates. |
| OCR text extraction helper | ADAPT | Same shape as existing `clip2qr` (mirrored: produces onto the clipboard); alpha desktop only. |

## Sources

Omarchy manual pages were read end to end on 2026-09-01; the manual is the
authoritative in-repo source (`manual/`) mirrored to omarchy.org.[^manual-repo]
GitHub citations reference `basecamp/omarchy` at HEAD (`4.0.0.alpha`).[^version]

[^manual-repo]: [Omarchy README — manual/ is the authoritative source](https://github.com/basecamp/omarchy#the-omarchy-manual)
[^welcome]: [The Omarchy Manual — Welcome to Omarchy!](https://omarchy.org/manual/)
[^getting-started]: [The Omarchy Manual — Getting Started](https://omarchy.org/manual/getting-started/)
[^updates-manual]: [The Omarchy Manual — Updates](https://omarchy.org/manual/updates/)
[^themes-manual]: [The Omarchy Manual — Themes](https://omarchy.org/manual/themes/)
[^theme-making]: [The Omarchy Manual — Making your own theme](https://omarchy.org/manual/making-your-own-theme/)
[^dotfiles-manual]: [The Omarchy Manual — Dotfiles](https://omarchy.org/manual/dotfiles/)
[^cli-manual]: [The Omarchy Manual — Omarchy CLI](https://omarchy.org/manual/omarchy-cli/)
[^snapshots-manual]: [The Omarchy Manual — System snapshots](https://omarchy.org/manual/system-snapshots/)
[^unattended-manual]: [The Omarchy Manual — Unattended Installs](https://omarchy.org/manual/unattended-installs/)
[^security-manual]: [The Omarchy Manual — Security](https://omarchy.org/manual/security/)
[^ai-manual]: [The Omarchy Manual — AI](https://omarchy.org/manual/ai/)
[^ocr-manual]: [The Omarchy Manual — Text Extraction & Dictation](https://omarchy.org/manual/text-extraction-dictation/)
[^tweaks-manual]: [The Omarchy Manual — Common tweaks](https://omarchy.org/manual/common-tweaks/)
[^troubleshooting-manual]: [The Omarchy Manual — Troubleshooting](https://omarchy.org/manual/troubleshooting/)
[^faq-manual]: [The Omarchy Manual — FAQ](https://omarchy.org/manual/faq/)
[^omarchy-on]: [The Omarchy Manual — Omarchy on... (notes henrysipp/omarchy-nix as the NixOS port)](https://omarchy.org/manual/omarchy-on/)
[^update-src]: [`basecamp/omarchy` — `bin/omarchy-update` (snapshot, lock, transcript, unattended mode, migration ordering)](https://github.com/basecamp/omarchy/blob/HEAD/bin/omarchy-update)
[^migrate-src]: [`basecamp/omarchy` — `bin/omarchy-migrate` (state markers, `--pending`)](https://github.com/basecamp/omarchy/blob/HEAD/bin/omarchy-migrate)
[^migrations-skill]: [`basecamp/omarchy` — `agents/skills/migrations.md` (migration model contract)](https://github.com/basecamp/omarchy/blob/HEAD/agents/skills/migrations.md)
[^pacman-guard]: [`basecamp/omarchy` — `bin/omarchy-update-pacman-guard` and `default/libalpm/hooks/00-omarchy-update-guard.hook`](https://github.com/basecamp/omarchy/blob/HEAD/bin/omarchy-update-pacman-guard)
[^snapshot-src]: [`basecamp/omarchy` — `bin/omarchy-snapshot` (snapper create/restore via limine-snapper-restore)](https://github.com/basecamp/omarchy/blob/HEAD/bin/omarchy-snapshot)
[^update-bin]: [`basecamp/omarchy` — `bin/` helper family (`omarchy-update-firmware`, `omarchy-update-analyze-logs`, etc.)](https://github.com/basecamp/omarchy/tree/HEAD/bin)
[^version]: [`basecamp/omarchy` — `version` file at HEAD](https://github.com/basecamp/omarchy/blob/HEAD/version)
[^tree]: File census from the `basecamp/omarchy` git tree at HEAD (103 migrations, 444 bin scripts; 22 theme directories — the per-asset theme file count varied between verification passes and is omitted).
[^tree-themes]: [`basecamp/omarchy` — `themes/<name>/colors.toml` layout (e.g. catppuccin)](https://github.com/basecamp/omarchy/tree/HEAD/themes/catppuccin)
[^hosts]: `docs/hosts.md` (documents alpha, beta, pi; epsilon is missing — stale relative to the phase-2 edge cutover comments in `modules/hosts/pi.nix` and `modules/hosts/epsilon.nix`)
[^epsilon]: `modules/hosts/epsilon.nix` (aarch64 VPS edge: traefik/authelia/glance/miniflux/ddclient, hermes gateway, restic backup; no update pipeline in its `includes`)
[^fleet-ops]: `docs/runbooks/fleet-operations.md`
[^runbook-rollback]: `docs/runbooks/failed-auto-upgrade-rollback.md` (note: its claim that auto-upgrade is enabled via `den.aspects.auto-upgrade` is stale — no host includes that aspect)
[^auto-upgrade-aspect]: `modules/aspects/auto-upgrade.nix` (`system.autoUpgrade`; included by no host — unused mechanism)
[^deploy-pi]: `docs/runbooks/deploy-pi-nixos.md`
[^den-docs]: `docs/architecture/den-aspect-composition.md`
[^alpha]: `modules/hosts/alpha.nix` (alpha-auto-update service: pull pi's lock, gate on idle + pi health, soak, rollback, circuit breaker)
[^style]: `modules/aspects/style.nix` (Stylix, single tokyodark scheme, pinned wallpaper)
[^btrfs]: `modules/aspects/btrfs-maintenance.nix` (scrub/balance/health, no snapper)
[^scripts]: `modules/aspects/cli/scripts.nix` (`clip2qr`, `hotswap`)
[^dictation]: `modules/aspects/ai/dictation.nix`
[^wispr-note]: `docs/research/wispr-flow-features-for-voxtype.md`
[^index]: `docs/index.md`
[^defaults]: `modules/defaults.nix`
