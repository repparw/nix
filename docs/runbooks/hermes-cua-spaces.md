---
type: Runbook
title: Enroll a remote CUA Space for Hermes
description: Prepare the named remote Linux desktop used by Epsilon's version-gated CUA integration.
when: Read when enrolling CUA, updating Hermes past v0.22.2, or validating remote browser and computer-use routing.
resource: modules/aspects/services/hermes-cua.nix
tags: [hermes, epsilon, cua, desktop, security]
---

# Enroll a remote CUA Space for Hermes

Epsilon remains headless. The existing Hermes identity uses one named remote
Linux Space, `hermes-gui`, for terminal, files, code, browser and computer-use
work. This name is an enrollment contract, not a provisioned resource. No Space
exists yet. No cloud account, credentials, extra Hermes profile or local desktop
is created by this configuration.

## Prepare the remote machine

1. Choose a separate machine or a VM in your own cloud account. Read
   [CUA Spaces](https://cua.ai/docs/spaces),
   [Add a computer](https://cua.ai/docs/spaces/guides/add-a-computer), and
   [Create a Space](https://cua.ai/docs/spaces/guides/add-a-space).
   CUA's former hosted Cloud offering has ended. Do not use `on: cloud` from
   older plugin examples. Provisioning and charges require separate approval.
2. Create a Linux Space on that machine and register it as `hermes-gui` in the
   service user's CUA registry. Alternatively change `space` in
   `modules/aspects/services/hermes-cua/_integration.nix` to its exact existing
   name or ID before activation. A name is resolved by the SDK; `on` selects
   placement only when creating a Space and does not relocate a named Space.
   The policy accepts remote `relay:`, `aws:`, `gcp:`, `modal:` or `direct:` IDs,
   rejects local and loopback IDs, and requires the resolved OS to be Linux.
   Verify that a direct endpoint is on a separate machine, not Epsilon.
3. Prepare the Linux guest's desktop stack through a separately reviewed image
   or provisioning change. It needs TigerVNC (`Xvnc`), Xfce (`xfwm4`),
   `xdpyinfo`, `cua-driver`, `agent-browser`, and Playwright Chromium under
   `/opt/playwright/chromium-*/chrome-linux*/chrome`. Review the
   [pinned plugin desktop requirements](https://github.com/trycua/hermes-cua-spaces/blob/82bb8d31517d2d1b8f1ef7f64701558dcac8aea9/hermes_cua_spaces/desktop-stack.sh)
   as a reference. Do not run a downloaded installer in production.
   `desktop: false` deliberately prevents the plugin from installing packages
   into the named machine. Missing components cause an error.
4. Complete CUA enrollment for container UID/GID 345, with `HOME=/var/lib/hermes`
   (host storage `/home/repparw/services/hermes`). The SDK and CLI must see the
   same registry and signed-in session. Check `cua auth status` and
   `cua spaces ls` as that user. Sign-in is needed for account/relay access;
   direct connections require the remote endpoint's authentication.
   Do not paste credentials into chat, Nix settings, Git or command arguments.
   Store any actual deployment credential/session material with `sops-nix` and
   add only the required service-owned secret mount once the chosen enrollment
   method and file format are known. This PR declares no fabricated secret key.
   An interactive login alone is not a completed declarative credential setup.

## Check the version and packages

Before the temporary release gate is retired by [`hermes-cua-version` watcher](../../.github/upstream/README.md#hermes-cua-version-gate),
the integration enables automatically when both gates pass:

- The Hermes input has a release ref of at least `v0.22.3`, and its selected
  source declares `supports_streams` and `default_cwd`. The version comes from
  the locked input ref, not the derivation's misleading `0.0.0` version. A branch
  or revision-only pin fails closed pending an explicit compatibility review.
- The packaged CUA SDK/CLI is at least 0.7.0 and below 0.8. The package supplies
  both from the same hashed upstream wheel, built for Hermes's Python family.

After that cleanup, the release/ref restriction is removed; the source-API
and packaged-runtime checks remain. The watcher initially notifies only while
the fleet pause is active. Its prepared cleanup cannot publish or auto-merge
until a reviewed change promotes it to post-lock mode after pause clearance.

The flake still pins Hermes v0.22.2. CUA plugin installation, backend selection,
SDK/CLI dependencies and Discord GUI tools are currently absent. Updating the
input is a separate change. Hermes
[#142225](https://github.com/NousResearch/hermes-agent/pull/142225), merge
`71633f762d2d74faebe604d0b8a2a2e6cf48346a`, is an ancestor of tag v0.22.3;
that tag's actual provider source contains both required APIs.

The plugin is version 0.4.0, pinned to reviewed catalog commit
`82bb8d31517d2d1b8f1ef7f64701558dcac8aea9`. Nix installs it using upstream
`extraPlugins` and installs the SDK through `extraPythonPackages`; no mutable
`hermes plugins install`, `pm repair`, or installer runs in production. A small
entrypoint enforces named remote Linux enrollment and errors on absent GUI
streams. Both the native SDK library and the wheel's real Rust CLI receive Nix
ELF fixups. No local VM engine, display service or CUA daemon is enabled.

Read the [reviewed plugin documentation](https://hermes-agent.nousresearch.com/docs/plugins/cua-spaces)
and [pinned source](https://github.com/trycua/hermes-cua-spaces/tree/82bb8d31517d2d1b8f1ef7f64701558dcac8aea9).
Upstream [issue 4](https://github.com/trycua/hermes-cua-spaces/issues/4) records
scanner cautions around installer text and a Unicode literal; this is explicit
reviewed declarative installation, not a scanner verdict override. The unused
Windows setup and desktop installers cannot run through this entrypoint.
[Issue 6](https://github.com/trycua/hermes-cua-spaces/issues/6) concerns Android
package resolution; these packages target Linux only.

## Validate before allowing production use

The fleet pause remains in force: the Epsilon gateway is deliberately stopped.
The security thread owns activation. Do not run full native/system builds,
activate the service, retry old deployments, or interfere with existing builds.
PR338's security, native dry-run, backup and Discord gates remain independent.

After those gates are lifted, the supported input lands, credentials are managed,
and the remote Space is enrolled:

1. Verify generated settings select `terminal.backend: cua`, enable
   `plugins.entries.cua-spaces`, name `hermes-gui`, and include the Discord
   `browser` and `computer_use` toolsets. Retain all manual approval settings.
2. As the service user, verify `cua --version`, `cua sandbox exec --help`
   (`--stdin`), SDK import, and `cua spaces ls`. Native ARM package validation
   is required before Epsilon activation.
3. Ask Hermes for `hostname` and `/etc/os-release`; confirm the remote guest.
   Test terminal, files, code, a browser screenshot and a computer-use screenshot.
   Verify both GUI streams stay on that machine while Epsilon has no display
   process. Watch the Space through CUA's viewer on your own computer.
4. Verify a dangerous command requests manual approval. Named Spaces retain
   prompts and are never deleted by the plugin. This policy always retains
   guards and refuses `space: create`, even through environment overrides.
   The upstream named-Space path can start a stopped machine; account for that
   machine's costs and lifecycle during enrollment.
5. With a test Space, verify a missing name, missing desktop component, or
   unavailable CLI stream produces an error and no local GUI fallback.

Scoped checks in `checks.<system>.hermes-cua-policy` cover version/API/runtime
gates and the real pinned plugin with a fake remote transport. They do not prove
remote connectivity, GUI operation, authentication, or ARM execution. The
supported-source evaluation also does not build or run a future Hermes package.

## Preparation evidence, 23 October 2026

Scoped verification used `/tmp/hermes-cua-review/` on the development host:

- Real Epsilon evaluation returned `modules.hermes-cua.ready = false`, empty
  `extraPlugins`/`extraPythonPackages`, and no CUA backend or GUI tools.
  Its evaluated system derivation is
  `/nix/store/f2xnlbb1d16zsngjl6pqzaplxcam6qh5-nixos-system-epsilon-26.11.20261020.02c087f.drv`;
  this was not built or activated.
- An isolated checkout substituted the actual v0.22.3 provider file and release
  ref into the feature aspect. Evaluating Epsilon selected CUA, the named Space,
  browser/computer-use toolsets, and the existing manual approval settings.
  The rest of the Hermes input remained v0.22.2: this checks configuration
  composition, not a built v0.22.3 package or remote GUI operation.
- The x86_64 CUA package built at
  `/nix/store/sk22z8p4y1y2nlwh3aga27lrrrs91l1v-python3.14-cua-0.7.0`.
  SDK import, native ELF dependency resolution, CLI version and `--stdin` checks
  passed. The aarch64 package only evaluated to a derivation; it was not built.
- The policy check and CI-selection tests passed. No full system/native build,
  activation, enrollment, paid provisioning or remote integration test ran.
