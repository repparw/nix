#!/usr/bin/env bash
set -euo pipefail

# Cachix manages signing; keep the upload token scoped to this step.
: "${CACHIX_AUTH_TOKEN:?Trusted publishing requires a cache-scoped CACHIX_AUTH_TOKEN with write permission}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY must name the job summary file}"

readonly cache_url='https://repparw.cachix.org'
readonly upstream_url='https://cache.nixos.org'
readonly fleet_key='repparw.cachix.org-1:QMnZnrTTNgO9m8cewBLWaPK9bLyvSI2GrLpzOpbJVrw='

mkdir -p ci-logs
nix path-info .#checks.x86_64-linux.host-neovim --no-update-lock-file \
  > ci-logs/host-neovim-paths
mapfile -t roots < ci-logs/host-neovim-paths
if (( ${#roots[@]} == 0 )); then
  echo 'No Neovim output paths to publish' >&2
  exit 1
fi

# The closure is the coverage universe: every path the fleet must be able to
# substitute after merging. Cachix's default upstream filtering deliberately
# skips paths that cache.nixos.org already distributes, so the cache is only
# expected to host what nixpkgs cannot serve.
nix path-info --recursive .#checks.x86_64-linux.host-neovim --no-update-lock-file \
  > ci-logs/host-neovim-closure
mapfile -t closure < ci-logs/host-neovim-closure

# Synchronous publishing makes authentication and upload failures fail the job.
cachix push repparw "${roots[@]}"

# Split the closure by which substituter can serve it. Narinfo probes are
# metadata-only HEAD requests; nothing is realized or downloaded.
classify() {
  local path=$1 hash
  hash=$(basename "$path")
  hash=${hash%%-*}
  if curl -fsSI -o /dev/null "$cache_url/$hash.narinfo"; then
    printf 'repparw %s\n' "$path"
  elif curl -fsSI -o /dev/null "$upstream_url/$hash.narinfo"; then
    printf 'upstream %s\n' "$path"
  else
    printf 'missing %s\n' "$path"
  fi
}
export -f classify
export cache_url upstream_url

# shellcheck disable=SC2016  # '$0' is expanded by the xargs child shell on purpose
printf '%s\n' "${closure[@]}" \
  | xargs -P 16 -n1 bash -c 'classify "$0"' | LC_ALL=C sort > ci-logs/host-neovim-classification

mapfile -t published < <(awk '$1 == "repparw" {print $2}' ci-logs/host-neovim-classification)
mapfile -t upstream < <(awk '$1 == "upstream" {print $2}' ci-logs/host-neovim-classification)
mapfile -t missing < <(awk '$1 == "missing" {print $2}' ci-logs/host-neovim-classification)

if (( ${#missing[@]} > 0 )); then
  printf 'Neither repparw.cachix.org nor cache.nixos.org can serve %d closure paths:\n' "${#missing[@]}" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

# Verify the cache-hosted paths against the fleet's pinned key without walking
# the closure: upstream paths are served by cache.nixos.org, not this cache.
if (( ${#published[@]} > 0 )); then
  nix store verify --store "$cache_url" --no-contents --sigs-needed 1 \
    --option trusted-public-keys "$fleet_key" \
    "${published[@]}"
fi

{
  printf 'Neovim closure published to repparw.cachix.org; %d cache paths verified against the fleet key.\n' "${#published[@]}"
  printf '%d closure paths remain served by the cache.nixos.org upstream.\n\n' "${#upstream[@]}"
  printf 'Output: %s\n' "${roots[@]}"
} >> "$GITHUB_STEP_SUMMARY"
