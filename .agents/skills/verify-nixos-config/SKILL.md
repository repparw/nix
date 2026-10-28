---
name: verify-nixos-config
description: Verify NixOS flake changes with targeted evaluation, generated-file inspection, and optional builds. Use after editing modules/, before deployment, or when a rebuild surprises you.
---

# Verify NixOS config

Work from the repository root. Commit hooks in `modules/git-hooks.nix` and
revision CI own repeatable formatting, documentation, script, test, and
host-evaluation checks. Review CI for the exact PR revision instead of
repeating its matrix locally. CI host checks are not native system builds.

Use the [verification map](features/README.md) for behavior-specific checks.
Evaluate every affected host for shared aspects/defaults, or just the target
host for host-specific edits. Inspect the **changed option values or generated
files** as well as evaluation success. Discover hosts from the flake rather
than relying on a copied host list.

For local checks that need saved evidence:

```bash
VERIFY_EVIDENCE=$(mktemp -d /tmp/nix-verify.XXXXXX)
VERIFY_HOST=alpha # replace with the affected host
VERIFY_BUILD=.agents/skills/verify-nixos-config/scripts/build.sh
```

The [build helper](scripts/build.sh) uses `--no-link` and
`--no-update-lock-file`, preserves Nix failure status, and stores logs in a
unique directory. Use it only when inspecting generated outputs or realizing
a closure is needed.

## Boundaries

Prefer evaluation and targeted assertions for PRs. Build a full local
system closure only when activation is imminent and CI cannot cover it.
Honor the execution host's global Nix `max-jobs` and `cores` limits;
do not override them for verification. Builds and closure comparisons do
not prove activation or runtime health. For runtime inspection or authorized
activation, use [fleet-operations](../fleet-operations/SKILL.md).

## Report

Record hosts, commands, observed values, output paths, evidence directories,
and relevant skipped checks. Distinguish CI's selected-package stubs from
native builds. Retain useful evidence; do not delete `result` or store paths.
