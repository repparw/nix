---
name: verify-nixos-config
description: Verify NixOS flake changes through evaluation, generated files, builds, and closure diffs. Use after editing modules/, before deployment, or when a rebuild surprises you.
---

# Verify NixOS config

Run from the repository root. Select the checks in the
[feature map](features/README.md) that observe the changed behavior. Shared
aspects and defaults require evaluation of every affected host; a host-specific
change can target that host. Discover host names from the flake.

This procedure evaluates and builds without activation. For deployment, use
the [fleet runbook](../../../docs/runbooks/fleet-operations.md) and the user's
authorization for that task. A successful build does not prove activation or
runtime health.

## Prepare

```bash
set -euo pipefail
VERIFY_EVIDENCE=$(mktemp -d /tmp/nix-verify.XXXXXX)
VERIFY_HOST=alpha  # select the host affected by the change
VERIFY_BUILD=.agents/skills/verify-nixos-config/scripts/build.sh
nix eval .#nixosConfigurations --apply builtins.attrNames --json --no-update-lock-file
```

The [build helper](scripts/build.sh) creates a unique evidence directory for
each invocation. It prints one store path only after a successful build,
preserves Nix's failure status and logs, and leaves `result` and the lockfile
unchanged. Build logs are available at the printed evidence location while
the command runs.

## Diagnose evaluation failures

```bash
jq -e . flake.lock > /dev/null
git diff -- flake.nix flake.lock modules/
nix flake metadata --json --no-update-lock-file > "$VERIFY_EVIDENCE/metadata.json"
```

Read the error before changing inputs. These commands inspect the current
checkout without updating its lock or stashing edits. JSON validity alone
does not prove that a lockfile describes the intended inputs.

## Verify

- [Evaluate host configurations and changed options](features/flake-eval.md).
- [Build and inspect generated Home Manager files](features/home-manager-files.md).
- [Build the system closure](features/system-build.md).
- [Compare the system closure with the running target](features/closure-diff.md).

Keep Home Manager and system output paths in separate variables. For a
generated-file change, read the file from the returned output and compare its
contents with the requested behavior. Run additional checks when the change
needs them; one feature per session is not a limit.

## Report evidence

Record the target hosts, commands, observed values, returned store paths, and
evidence directory. State which relevant checks were skipped. Repository
checks in `modules/checks.nix` deliberately stub selected packages, so report
those checks as evaluation with stubs, not as full host builds.

Keep successful and failed evidence for review. Remove only scratch directories
created by this run when they are no longer needed; verification never needs
to remove `result` or a store path.
