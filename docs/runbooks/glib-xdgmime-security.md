---
type: Runbook
title: GLib MIME parser security backport
description: Verify and retire the GLib 2.88.3 MIME byte-swap security patch.
when: Read when updating GLib or Nixpkgs, investigating MIME parser crashes, or retiring the CVE-2026-16118 backport.
resource: modules/aspects/glib-xdgmime-fix.nix
tags: [glib, security, nixpkgs, workaround]
---

# GLib MIME parser security backport

The pinned GLib 2.88.3 tarball contains an out-of-bounds write in the little-endian MIME magic byte-swap parser. Its package patches do not include the fix. The overlay applies to fleet hosts and their registered service containers. It applies upstream [commit ca75aff83af9875](https://github.com/GNOME/glib/commit/ca75aff83af9875ea2ad2bfbe48a85dfd99c2ce5), which corrects byte offsets for both values and masks. The patch URL and content hash are pinned.

An isolated AddressSanitizer parser test with a four-byte value and a two-byte word size reproduces the heap-buffer-overflow in the original tarball. The same input passes after the upstream patch. This establishes the missing parser fix. It does not establish that the historical Nautilus alias-table crash used this trigger.

The overlay asserts the exact affected version. Before changing the GLib version, inspect the proposed source and package patches for the upstream commit or equivalent byte-offset correction. When the pinned package carries the fix, remove the aspect and its defaults include together. Do not remove the guard merely to allow a lock update.

TPM2-TSS uses `swtpm` only for its install tests. The aspect selects the stock pinned `swtpm` for that test fixture, retaining the original TPM2-TSS and systemd derivations. Their installed runtime closures do not contain `swtpm` or GLib. Actual runtime consumers, including `swtpm` itself, still use patched GLib. This avoids rebuilding systemd and its dependents for an unrelated MIME parser change while keeping the TPM install tests enabled.

Inspect the target-native dry-run build plan before deployment. GLib runtime consumers still rebuild, so a package build alone does not establish enough disk space for a system rollout. The controller must continue capturing derivations without realizing target closures. NixOS `system.replaceDependencies` performs reference-graph realization during evaluation and therefore does not preserve this fleet's controller and target build split.

Historical diagnostic evidence is in `/home/repparw/crash-followup-evidence/`. The user MIME magic file inspected on Alpha contained only the empty 12-byte magic header; no crafted matchlet was present.
