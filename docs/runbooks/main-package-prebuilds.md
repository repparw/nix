---
type: Runbook
title: Main package prebuilds
description: Build missing fleet packages on native CI runners without realizing cached system closures.
when: Inspecting or manually running fleet package prebuilds and Cachix publication.
resource: .github/workflows/main-packages.yml
tags: [ci, nix, cachix, builds]
---

# Main package prebuilds

The `main-packages` workflow runs on main pushes that change modules, flake
inputs, or the workflow and publishing script. A native x86 runner handles
Alpha; a native ARM runner handles Pi and Epsilon together. Runs are serialized
per ref so later revisions can reuse earlier uploads. This workflow is separate
from the required validation gate and does not deploy hosts.

`ciPackages.<system>` selects installed system and Home Manager packages,
enabled services with visible top-level `enable` and `package` options, and
the corresponding packages in declarative containers. It does not enumerate
arbitrary package references embedded in service command strings or nested
service instance options. It excludes system toplevels and activation
assemblies. This is package prebuilding, not validation of a full system closure.

The flake's pinned Nixpkgs supplies `nix-fast-build`. Its `--skip-cached` option
checks substituter metadata and skips cached targets without downloading their
runtime closures. It also deduplicates repeated derivations. A missing package
still needs its build inputs; those downloads are unavoidable for that build.
Final system assembly remains on the hosts.

Successful local package outputs are published synchronously with the existing
cache-scoped Actions token. Outputs with `.sops.yml` or `.sops.yaml` paths in
their runtime closure are skipped. A closure inspection error or upload error
fails publication. The token is not passed to the build step, and no cache
signing identity or fleet trust settings change.

## Run a reviewed revision

Use the workflow's manual dispatch with the selected ref and its exact commit:

```sh
gh workflow run main-packages.yml --ref <branch> -f expected_sha=<commit>
```

GitHub requires the workflow to exist on the default branch before manual
dispatch is available. The SHA guard rejects a branch that moved since review.
No PR-triggered native package sweep is added.

Inspect the per-architecture job summary and `main-packages-<system>` artifact.
`packages.json` records evaluation, cache status, and build results;
`package-outputs` records the local outputs considered for publication.
An all-cached run should have no build results. For failures, distinguish
evaluation, missing-package builds, runner disk exhaustion, and upload errors
before retrying. The jobs have a three-hour limit and use one evaluation worker,
an 8 GiB evaluation budget, one build job, and two cores per build.
