---
type: Runbook
title: Obsidian vault bisync recovery
description: Recover the Obsidian vault sync after a failed bisync run without losing vault copies or listing state.
when: Read when the Obsidian vault sync stops or a manual resync is needed.
resource: modules/aspects/obsidian.nix
tags: [runbook, recovery, obsidian, bisync, rclone]
---

# Obsidian vault bisync recovery

Inspect the user service before touching state:

```sh
journalctl --user -u obsidian-bisync.service
```

[obsidian.nix](../../modules/aspects/obsidian.nix) declares the timer, paths,
and sync flags.

The listings under `~/.local/state/rclone/obsidian-bisync` are required state,
not cache. Before a manual resync, pause edits and stop both the timer and the
service. Preserve the local and remote vault copies and the listing state, and
reconcile changes using the [bisync recovery guidance](https://rclone.org/bisync/).
Verify a normal incremental run before you restart the timer.
