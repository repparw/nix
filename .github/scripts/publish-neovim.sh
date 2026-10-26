#!/usr/bin/env bash
set -euo pipefail

# Keep the cache-scoped key in this step, rather than exporting it before builds.
: "${CACHIX_SIGNING_KEY:?Trusted publishing requires CACHIX_SIGNING_KEY}"
: "${CACHIX_AUTH_TOKEN:?Trusted publishing requires a cache-scoped CACHIX_AUTH_TOKEN with write permission}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY must name the job summary file}"

mkdir -p ci-logs
nix path-info .#checks.x86_64-linux.host-neovim --no-update-lock-file \
  > ci-logs/host-neovim-paths
mapfile -t paths < ci-logs/host-neovim-paths
if (( ${#paths[@]} == 0 )); then
  echo 'No Neovim output paths to publish' >&2
  exit 1
fi

# Synchronous publishing makes authentication and upload failures fail the job.
cachix push repparw "${paths[@]}"
# Query the remote closure, then verify the roots against the fleet's exact key.
# Neither command realizes outputs or rebuilds the package.
nix path-info --store https://repparw.cachix.org --recursive "${paths[@]}" \
  > ci-logs/host-neovim-cached-closure
nix store verify --store https://repparw.cachix.org --no-contents --sigs-needed 1 \
  --option trusted-public-keys 'repparw.cachix.org-1:QMnZnrTTNgO9m8cewBLWaPK9bLyvSI2GrLpzOpbJVrw=' \
  "${paths[@]}"
{
  printf 'Neovim closure published to repparw.cachix.org; root signatures verified.\n\n'
  printf 'Output: %s\n' "${paths[@]}"
} >> "$GITHUB_STEP_SUMMARY"
