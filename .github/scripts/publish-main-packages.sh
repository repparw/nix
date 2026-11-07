#!/usr/bin/env bash
set -euo pipefail

: "${CACHIX_AUTH_TOKEN:?Publishing requires a cache-scoped write token}"
# Fail rather than silently skipping publication without a results manifest.
test -s ci-logs/packages.json
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
