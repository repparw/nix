---
type: Agent Guide
title: Upstream Landing Gates
description: Machine-checked tracking for changes waiting on an upstream branch or flake input.
when: Read when creating or reviewing an upstream landing gate.
resource: data/upstream-gates.json
tags: [agents, upstream, nixpkgs, home-manager, watchers]
---

# Upstream landing gates

The registry is [data/upstream-gates.json](../../data/upstream-gates.json).
Check it with:

```sh
nix run .#upstream-gates -- validate
nix run .#upstream-gates -- check
```

The [watch-upstream skill](../../modules/aspects/ai/skills/watch-upstream/SKILL.md)
defines how agents create, watch, and adopt gates. Issues and systemd timers
link to gate IDs; they are not separate status stores.
