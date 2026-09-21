#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: build.sh INSTALLABLE [EVIDENCE_DIRECTORY]" >&2
  exit 2
fi

evidence_parent=${2:-/tmp/nix-verify}
mkdir -p "$evidence_parent"
evidence=$(mktemp -d "$evidence_parent/build.XXXXXX")
printf 'Build evidence: %s\n' "$evidence" >&2

if nix build "$1" --no-link --no-update-lock-file --print-out-paths --print-build-logs \
    > "$evidence/output-paths" 2> "$evidence/build.log"; then
  cat "$evidence/build.log" >&2
else
  status=$?
  cat "$evidence/build.log" >&2
  exit "$status"
fi

mapfile -t outputs < "$evidence/output-paths"
if [[ ${#outputs[@]} != 1 || ${outputs[0]} != /nix/store/* || ! -e ${outputs[0]} ]]; then
  echo "Expected one realized output; inspect $evidence/output-paths" >&2
  exit 1
fi
printf '%s\n' "${outputs[0]}"
