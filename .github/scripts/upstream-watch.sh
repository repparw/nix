#!/usr/bin/env bash
# CI-native upstream watcher. Pilot: the Epsilon Authelia pnpm hash override
# from PR #168, retired once nixpkgs#572207 reaches nixos-unstable AND this
# flake's own pin on main.
#
# Scheduled runs are quiet while waiting: one line, exit 0. On readiness this
# opens a cleanup PR and dispatches CI on the exact candidate SHA — GITHUB_TOKEN
# pushes do not trigger workflows, so the explicit dispatch is required.
# Validation is delegated to the dispatched ci.yml run; this script runs no Nix.
#
# Predicates match the local watcher (watch-authelia-pnpm-hash.sh): ancestry
# via merge_base_commit.sha, accepting ahead or identical, failing closed when
# the comparison is unavailable.
set -euo pipefail

MERGE=6b157b9637b15f44d1f07065cdfd681166014455
MODULE=modules/_services/authelia.nix
BRANCH=fix/authelia-drop-pnpm-hash-override
# The stale hash this workaround exists to replace; still correct upstream.
STALE_HASH=sha256-YUInqRclRdnMzxfJKuVdXwKaRzJd9sFu16dxCAgVJI8
PR_NUM=572207

waiting() { printf '%s\n' "$1"; exit 0; }
api() { gh api "$1"; }

# Trigger gate: when fired by a lock-update completion, only proceed if it
# published successfully. Push and dispatch triggers have no workflow_run
# payload and always proceed.
if [ -n "${GITHUB_EVENT_PATH:-}" ] && jq -e '.workflow_run != null' "$GITHUB_EVENT_PATH" >/dev/null 2>&1; then
  conclusion=$(jq -r '.workflow_run.conclusion // ""' "$GITHUB_EVENT_PATH")
  [ "$conclusion" = "success" ] || waiting "skipping: lock-update concluded ${conclusion:-unknown}"
fi
# True when $3 is a descendant of (or equal to) $2 in $1's repository.
contains_merge() {
  api "repos/$1/compare/$2...$3" \
    | jq -e --arg m "$2" '(.status == "ahead" or .status == "identical") and .merge_base_commit.sha == $m' >/dev/null
}
# The pinned revision of a root input, read from the checked-out lock.
pin_for() {
  jq -r --arg k "$1" '.nodes.root.inputs[$k] as $n | .nodes[$n].locked.rev' flake.lock
}

# Readiness report for every PR-based upstream wait. Detection is shared and
# read-only; completions stay with their current owners until the Authelia
# pilot proves the autonomous publication lifecycle. Every watcher is
# classified: repo-only completions migrate to CI, host-owned ones (runtime,
# GPU, SSH) stay with the fleet.
pr_watchers=(
  "authelia-pnpm-hash|NixOS/nixpkgs|572207|nixpkgs|active pilot: prepares the cleanup PR"
  "t3code-connect|NixOS/nixpkgs|555921|nixpkgs|repo-only completion"
  "t3code-split|NixOS/nixpkgs|555814|nixpkgs|repo + ARM builder completion"
  "tasks-org|NixOS/nixpkgs|518221|nixpkgs|repo-only completion"
  "nautilus-module|NixOS/nixpkgs|319535|nixpkgs|notify-only, never auto-edits"
  "moonshine-pr227|hgaiser/moonshine|227|nixpkgs|host-owned completion"
  "t3code-server|nix-community/home-manager|9695|home-manager|repo-only completion"
  "cliamp-hm-module|nix-community/home-manager|9842|home-manager|repo-only completion"
)
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
{
  echo "### upstream-watch readiness"
  echo "| watcher | upstream | status | completion owner |"
  echo "| --- | --- | --- | --- |"
} >> "$summary"
for w in "${pr_watchers[@]}"; do
  IFS='|' read -r name repo pr input note <<<"$w"
  pr_json=$(api "repos/$repo/pulls/$pr" 2>/dev/null || true)
  merge_sha=$(jq -r '.merge_commit_sha // empty' <<<"$pr_json" 2>/dev/null || true)
  pin=$(pin_for "$input" 2>/dev/null || true)
  if [ -z "$pr_json" ] || [ "$(jq -r '.merged // "false"' <<<"$pr_json" 2>/dev/null)" != "true" ]; then
    status="waiting-upstream ($repo#$pr open)"
  elif [ -z "$merge_sha" ] || [ -z "$pin" ]; then
    status="unavailable (comparison error; treated as not-ready)"
  elif contains_merge "$repo" "$merge_sha" "$pin"; then
    status="PINNED-READY ($repo#$pr in pin)"
  else
    status="merged-not-pinned (pin predates merge)"
  fi
  printf '  %s: %s — %s\n' "$name" "$status" "$note"
  echo "| $name | $repo#$pr | $status | $note |" >> "$summary"
done
# Not yet PR-based: release/version/runtime predicates and their owners.
for w in \
  "qbittorrent|release-based (PR #24055 in a release)|CI detector pending" \
  "wpaperd-fix|release carrying wpaperd@442b962|CI detector pending" \
  "voxtype-graphical|version-based (graphical-session fix)|CI detector pending" \
  "cliamp-attach|upstream CLI capability check|CI detector pending" \
  "gamescope-vkroots|ancestry + GPU probe|host-owned (alpha)" \
  "sonarr-jellyfin|runtime: running service version on alpha|host-owned"
do
  IFS='|' read -r name note owner <<<"$w"
  printf '  %s: %s — %s\n' "$name" "$note" "$owner"
  echo "| $name | — | $note | $owner |" >> "$summary"
done

# Idempotent: judge completion on the checked-out main, never a working copy.
if ! grep -qF "$STALE_HASH" "$MODULE"; then
  waiting "already done: $MODULE carries no override"
fi

api "repos/NixOS/nixpkgs/pulls/$PR_NUM" | jq -e '.merged == true' >/dev/null \
  || waiting "waiting-upstream: NixOS/nixpkgs#$PR_NUM is not merged"

CHANNEL_REV=$(api repos/NixOS/nixpkgs/commits/nixos-unstable | jq -er .sha) \
  || waiting "unavailable: cannot read nixos-unstable; treated as not-ready"
contains_merge NixOS/nixpkgs "$MERGE" "$CHANNEL_REV" \
  || waiting "waiting-unstable: nixos-unstable $CHANNEL_REV does not contain #$PR_NUM ($MERGE)"

PIN=$(pin_for nixpkgs)
contains_merge NixOS/nixpkgs "$MERGE" "$PIN" \
  || waiting "waiting-pin: nixos-unstable $CHANNEL_REV carries #$PR_NUM, but main pins $PIN which predates it"

# Ready. Reuse an existing candidate before creating one: each scheduled run
# must not recreate the commit and force-push the branch, which would overwrite
# intentional reviewer edits and redispatch CI. An open PR that still
# represents the cleanup is left untouched; one that no longer does needs a
# human, and is never automatically overwritten.
pr=$(gh pr list --head "$BRANCH" --base main --state open --json number --jq '.[0].number // empty')
if [ -n "$pr" ]; then
  remote_tip=$(git ls-remote --heads origin "$BRANCH" | cut -f1)
  if [ -z "$remote_tip" ]; then
    echo "PR #$pr is open but its branch is gone; needs human attention" >&2
    exit 1
  fi
  git fetch --quiet origin "$BRANCH"
  branch_module=$(git show "FETCH_HEAD:$MODULE" 2>/dev/null || true)
  if grep -qF "$STALE_HASH" <<<"$branch_module" || grep -q 'autheliaPackage' <<<"$branch_module"; then
    echo "PR #$pr branch no longer represents the cleanup; refusing to overwrite; needs human attention" >&2
    exit 1
  fi
  ci_state=$(gh run list --repo "$GITHUB_REPOSITORY" --workflow ci.yml --commit "$remote_tip" \
    --json conclusion,status --limit 5 \
    | jq -r '[.[] | select(.status == "completed")][0].conclusion // "pending"')
  if [ "$ci_state" = "success" ]; then
    waiting "waiting-merge: PR #$pr already open with the cleanup; CI green on $(echo "$remote_tip" | cut -c1-10)"
  fi
  waiting "waiting-ci: PR #$pr already open with the cleanup; CI ${ci_state} on $(echo "$remote_tip" | cut -c1-10)"
fi

# No candidate exists yet. Fail closed on a pre-existing branch without an
# open PR: a partial earlier run or a closed PR may have left it behind.
# Never overwrite it — a human decides whether to reopen or delete.
remote_tip=$(git ls-remote --heads origin "$BRANCH" | cut -f1)
if [ -n "$remote_tip" ]; then
  echo "Branch $BRANCH exists without an open cleanup PR (tip ${remote_tip:0:10}); refusing to overwrite; needs human attention" >&2
  exit 1
fi

# Prepare one from the checked-out main.
MAIN_SHA=$(git rev-parse HEAD)
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git switch -C "$BRANCH"

# Delete two contiguous, self-verified line ranges rather than brace-matching.
# Every endpoint is matched against literal content, so an upstream reformat
# aborts instead of mangling the module.
start=$(grep -nF '  # pnpm 12.9 changed the dependency output: nixpkgs issue #571789.' "$MODULE" | cut -d: -f1)
end=$(awk '/^      pkgs\.authelia;$/ { print NR; exit }' "$MODULE")
consumer=$(grep -nF '        package = autheliaPackage;' "$MODULE" | cut -d: -f1)
if [ -z "$start" ] || [ -z "$end" ] || [ -z "$consumer" ]; then
  echo "Override shape not found; refusing to edit $MODULE" >&2
  exit 1
fi
if [ "$start" -ge "$end" ] || [ "$consumer" -le "$end" ]; then
  echo "Override line order unexpected; refusing to edit" >&2
  exit 1
fi
head=$(sed -n "${start},$((start + 2))p" "$MODULE")
grep -qF '  autheliaPackage =' <<<"$head" || { echo 'Override head changed; refusing to edit' >&2; exit 1; }

cp "$MODULE" /tmp/authelia-before.nix
awk -v s="$start" -v e="$end" -v c="$consumer" '
  NR >= s && NR <= e { next }
  NR == c { next }
  { print }
' "$MODULE" > "$MODULE.new"

grep -qF "$STALE_HASH" "$MODULE.new" && { echo 'Stale hash survived removal; refusing to push' >&2; exit 1; }
grep -q 'autheliaPackage' "$MODULE.new" && { echo 'autheliaPackage references survived removal' >&2; exit 1; }
diff -u /tmp/authelia-before.nix "$MODULE.new" > /tmp/removal.diff || true
grep -q '^+[^+]' /tmp/removal.diff && { echo 'Removal added lines; refusing to push' >&2; exit 1; }
removed=$(grep -c '^-[^-]' /tmp/removal.diff || true)
if [ "$removed" -ne 18 ]; then
  echo "Expected 18 removed lines, found $removed; refusing to push" >&2
  exit 1
fi
mv "$MODULE.new" "$MODULE"
git add "$MODULE"
git diff --cached --name-only | awk '$0 != "'"$MODULE"'" { bad = 1 } END { exit bad }' \
  || { echo 'Unexpected staged paths; refusing to push' >&2; exit 1; }

git commit -q -m "fix(authelia): drop stale ARM pnpm hash override

NixOS/nixpkgs#$PR_NUM fixed fetchPnpmDeps for pnpm 12.7+, which stopped
fetching foreign optional dependencies. That restored the original
frontend dependency fetch, so pnpm 12.9 is no longer implicated and the
hash workaround from #168 is obsolete.

Left in place it would actively break the build: upstream sources.nix
keeps pnpmDepsHash sha256-B/Au9... (set 2026-09-30, before the pnpm
bump), so the guard in #168 still matches after the fix and would force
the stale sha256-YUInq... hash."
REVISION=$(git rev-parse HEAD)

# Publish the candidate. The branch is guaranteed absent (checked above); if
# one appears between check and push, the push fails closed.
git push origin "HEAD:refs/heads/$BRANCH"

pr=$(gh pr list --head "$BRANCH" --base main --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  url=$(gh pr create --base main --head "$BRANCH" \
    --title "Retire Epsilon Authelia pnpm hash override" \
    --body "Removes the workaround from #168.

- Upstream fix: NixOS/nixpkgs#$PR_NUM (merge ${MERGE}), fixing issue #571789
- nixos-unstable: ${CHANNEL_REV}
- This flake's nixpkgs pin: ${PIN}
- Prepared automatically by upstream-watch; CI is dispatched on the exact candidate SHA

Left in place the guard would still match and force the stale hash, so removal is atomic with the pin that carries the fix.")
  pr=${url##*/}
fi

# GITHUB_TOKEN pushes do not trigger workflows; dispatch CI on the exact SHA.
# The opt-in ARM build is part of the candidate's required validation: the
# dispatched run's overall gate fails if the unpatched aarch64 package does
# not build, so a green result establishes the original failure is gone.
gh workflow run ci.yml --ref "$BRANCH" -f expected_sha="$REVISION" -f build_arm_authelia=true

{
  echo "### upstream-watch: cleanup candidate prepared"
  echo "- PR: #$pr"
  echo "- Candidate SHA: $REVISION (from main $MAIN_SHA)"
  echo "- nixos-unstable: $CHANNEL_REV, pin: $PIN"
  echo "- CI dispatched on the candidate; merge needs human review"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'candidate=%s\nbranch=%s\n' "$REVISION" "$BRANCH" >> "$GITHUB_OUTPUT"
fi
printf 'done: PR #%s prepared at %s; CI dispatched\n' "$pr" "$REVISION"
