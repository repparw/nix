#!/usr/bin/env bash
set -euo pipefail

check_only=false
if [[ ${1:-} == --check-only ]]; then
  check_only=true
  shift
fi
if [[ $# -lt 2 || $# -gt 3 || ! $2 =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo 'usage: run.sh [--check-only] REPO GATE_ID [ACTION_SCRIPT]' >&2
  exit 2
fi
repo=$(realpath "$1")
gate_id=$2
actions=$(realpath "${3:-$(dirname "${BASH_SOURCE[0]}")/actions.sh}")
common_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
exec 9> "$common_dir/watch-upstream-$gate_id.lock"
flock -n 9 || { echo "$gate_id: another run is active"; exit 0; }
scratch=$(mktemp -d "${TMPDIR:-/tmp}/watch-upstream-$gate_id.XXXXXX")
worktree=$scratch/tree
cleanup() {
  cd "$repo"
  if [[ -e $worktree/.git ]]; then
    git worktree remove --force "$worktree"
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
trap 'printf "%s: failed at line %s; timer remains armed\n" "$gate_id" "$LINENO" >&2' ERR

git -C "$repo" fetch --quiet origin main
git -C "$repo" worktree add --quiet --detach "$worktree" refs/remotes/origin/main
cd "$worktree"
registry=$worktree/data/upstream-gates.json
gate=$(jq -ce --arg id "$gate_id" '.gates[$id] // error("unknown gate: " + $id)' "$registry")
input=$(jq -er '.input' <<< "$gate")
watcher=$(jq -er '.watcher' <<< "$gate")
issue=$(jq -r '.issue // empty' <<< "$gate")

completed() {
  local status
  if bash "$actions" "$gate_id" completed; then
    return 0
  else
    status=$?
    if [[ $status != 1 ]]; then
      echo "$gate_id: completion check failed" >&2
      exit "$status"
    fi
    return 1
  fi
}

finish() {
  if [[ -n $issue ]]; then
    gh issue close "$issue" --comment "Gate $gate_id: cleanup is present on origin/main at $(git rev-parse HEAD)."
  fi
  systemctl --user disable --now "$watcher"
  printf '%s: completed on origin/main; %s disabled\n' "$gate_id" "$watcher"
}

if completed; then
  if $check_only; then
    echo "$gate_id: completed on origin/main"
  else
    finish
  fi
  exit 0
fi

gate_state() {
  UPSTREAM_GATES_REGISTRY="$registry" UPSTREAM_GATES_REPO="$worktree" \
    UPSTREAM_GATES_LOCKFILE="$worktree/flake.lock" \
    bash modules/scripts/upstream-gates.sh check "$gate_id" --json \
    | jq -er --arg id "$gate_id" 'select(.id == $id) | .status'
}

state=$(gate_state)
case "$state" in
  waiting-upstream|waiting-unstable) echo "$gate_id: $state"; exit 0 ;;
  waiting-pin|adopting) ;;
  *) echo "$gate_id: unexpected state $state" >&2; exit 2 ;;
esac
if $check_only; then
  echo "$gate_id: $state"
  exit 0
fi
if [[ $state == waiting-pin ]]; then
  nix flake update "$input"
  state=$(gate_state)
  case "$state" in
    waiting-upstream|waiting-unstable|waiting-pin) echo "$gate_id: $state after updating $input"; exit 0 ;;
    adopting) ;;
    *) echo "$gate_id: unexpected state $state" >&2; exit 2 ;;
  esac
fi

bash "$actions" "$gate_id" apply
completed || { echo "$gate_id: cleanup is incomplete" >&2; exit 1; }
mapfile -t owned_paths < <(jq -r '.workaround[]' <<< "$gate")
git add -- flake.lock "${owned_paths[@]}"
check_writes() {
  local path allowed owned
  while IFS= read -r -d '' path; do
    allowed=false
    for owned in flake.lock "${owned_paths[@]}"; do
      [[ $path != "$owned" ]] || allowed=true
    done
    if ! $allowed; then
      echo "$gate_id: cleanup staged an unowned path: $path" >&2
      exit 1
    fi
  done < <(git diff --cached --name-only -z)
  if ! git diff --quiet || [[ -n $(git ls-files --others --exclude-standard) ]]; then
    echo "$gate_id: cleanup left changes outside the staged paths" >&2
    exit 1
  fi
}
check_writes
bash "$actions" "$gate_id" verify
check_writes
git diff --cached --quiet && { echo "$gate_id: cleanup produced no changes" >&2; exit 1; }
git commit -m "fix(upstream): adopt $gate_id" -m "Gate: $gate_id"
commit=$(git rev-parse HEAD)
git push origin HEAD:main
git fetch --quiet origin main
git merge-base --is-ancestor "$commit" refs/remotes/origin/main
git reset --hard --quiet refs/remotes/origin/main
completed || { echo "$gate_id: cleanup is absent from origin/main" >&2; exit 1; }
finish
