---
type: Host Profiles
title: Host Profiles
description: The alpha desktop and beta laptop profiles.
resource: modules/hosts/
tags: [hosts, alpha, beta]
---

# Host Profiles

Both hosts share the baseline in `modules/defaults.nix` and add hardware or
workload-specific aspects in `modules/hosts/`.

## Alpha

`alpha` is the desktop workstation. It carries the heavier local service set,
gaming, streaming, and backup behavior.

Source: `modules/hosts/alpha.nix`

## Beta

`beta` is the laptop profile. It adds laptop-specific input, power, and display
handling to the shared baseline.

Source: `modules/hosts/beta.nix`

## Related

- [Service model](services/service-model.md)
- [Restore service backups](runbooks/restore-service-backups.md)
- [Den aspect composition](architecture/den-aspect-composition.md)
