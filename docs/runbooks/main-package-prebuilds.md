---
type: Runbook
title: Main package prebuilds
description: Build missing fleet packages on native CI runners without realizing cached system closures.
when: Inspecting or manually running fleet package prebuilds and Cachix publication.
resource: .github/workflows/main-packages.yml
tags: [ci, nix, cachix, builds]
---

# Main package prebuilds

The `main-packages` workflow runs on pushes to main that change modules, flake
inputs, or the workflow and publishing script. A native x86 runner handles
Alpha, and a native ARM runner handles Pi and Epsilon together. Runs are
serialized per ref, so later revisions can reuse earlier uploads. This workflow
is separate from the required validation gate, and it does not deploy hosts.

`ciPackages.<system>` selects the installed system and Home Manager packages,
the enabled services that have visible top-level `enable` and `package`
options, and the matching packages in declarative containers. It does not
enumerate arbitrary package references inside service command strings or nested
service instance options. It excludes system toplevels and activation
assemblies. This prebuilds packages. It does not validate a full system closure.

The flake's pinned Nixpkgs supplies `nix-fast-build`. Its `--skip-cached` option
checks substituter metadata and skips cached targets without downloading their
runtime closures. It also deduplicates repeated derivations. A missing package
still needs its build inputs, and those downloads are unavoidable for that
build. Final system assembly stays on the hosts.

The workflow publishes successful local package outputs synchronously, using the
existing cache-scoped Actions token. It skips outputs that have `.sops.yml` or
`.sops.yaml` paths in their runtime closure. A closure inspection error or an
upload error fails publication. The build step does not receive the token, and
no cache signing identity or fleet trust setting changes.

## Run a reviewed revision

Use the workflow's manual dispatch with the selected ref and its exact commit:

```sh
branch=main # replace with the reviewed ref
expected_sha=$(git rev-parse "$branch") # verify this is the reviewed commit
gh workflow run main-packages.yml --ref "$branch" -f "expected_sha=$expected_sha"
```

GitHub requires the workflow to exist on the default branch before manual
dispatch is available. The SHA guard rejects a branch that moved since review.
This setup adds no PR-triggered native package sweep.

Inspect the per-architecture job summary and the `main-packages-<system>`
artifact. `packages.json` records evaluation, cache status, and build results.
`package-outputs` records the local outputs considered for publication. A run
where everything is cached should have no build results. For failures, tell
apart evaluation errors, missing-package builds, runner disk exhaustion, and
upload errors before you retry. The jobs have a three-hour limit and use one
evaluation worker, an 8 GiB evaluation budget, one build job, and two cores per
build.
