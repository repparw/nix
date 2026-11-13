#!/usr/bin/env bash
set -euo pipefail

: "${CI_CHECKS:?CI_CHECKS must name at least one check}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY must name the job summary file}"
if [[ ! "$CI_CHECKS" =~ [a-z0-9] ]]; then
  echo 'CI_CHECKS must name at least one check' >&2
  exit 1
fi

mkdir -p ci-logs
failed=0
for check in $CI_CHECKS; do
  if [[ ! "$check" =~ ^[a-z0-9-]+$ ]]; then
    echo 'Invalid CI check name' >&2
    exit 1
  fi
  echo "::group::$check"
  started=$SECONDS
  if nix build ".#checks.x86_64-linux.$check" \
    --no-update-lock-file --no-link --print-build-logs 2>&1 | tee "ci-logs/$check.log"; then
    result=success
  else
    result=failure
    failed=1
    echo "::error title=$check failed::See $check.log in this job's artifacts"
  fi
  echo '::endgroup::'
  printf '%s: %s (%ss)\n' "$check" "$result" "$((SECONDS - started))" >> "$GITHUB_STEP_SUMMARY"
done
exit "$failed"
