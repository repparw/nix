#!/usr/bin/env bash
set -euo pipefail

: "${CACHIX_AUTH_TOKEN:?Publishing requires a cache-scoped write token}"
# A failed setup/build may have produced no manifest. A successful build
# must have one, otherwise publication would silently do nothing.
if [[ ! -f ci-logs/packages.json ]]; then
  if [[ "${BUILD_SUCCEEDED:-false}" == true ]]; then
    echo 'Missing ci-logs/packages.json after successful package build' >&2
    exit 1
  fi
  exit 0
fi
jq -r '.results[] |
  select(.success and (.type == "BUILD" or (.type == "EVAL" and .cacheStatus == "local"))) |
  .outputs[]' ci-logs/packages.json | sort -u > ci-logs/package-outputs
mapfile -t outputs < ci-logs/package-outputs
safe=()
for path in "${outputs[@]}"; do
  closure=$(nix-store --query --requisites "$path")
  if grep -E '\.sops\.ya?ml$' <<< "$closure" >/dev/null; then
    printf 'Skipping vault-containing package closure: %s\n' "$path" >&2
    continue
  fi
  safe+=("$path")
done
if (( ${#safe[@]} )); then
  cachix push repparw "${safe[@]}"
fi
