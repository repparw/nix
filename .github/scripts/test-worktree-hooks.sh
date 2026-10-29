#!/usr/bin/env bash
# Exercise real Git hook installation in an isolated repository with a linked worktree.
set -euo pipefail

source_root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

repo="$scratch/repo"
worktree="$scratch/worktree"
git init -q "$repo"
# GitHub Actions checks out a shallow HEAD; archive copies its exact tracked
# contents without depending on fetch negotiation or shallow-root histories.
git -C "$source_root" archive --format=tar HEAD | tar -xf - -C "$repo"
git -C "$repo" add -A
git -C "$repo" -c user.name=CI -c user.email=ci@example.invalid \
  -c commit.gpgsign=false commit -q -m 'test: seed isolated repository'

# Installing hooks in the primary checkout must also provision the shared
# post-checkout bootstrap used by subsequent linked worktrees.
(
  cd "$repo"
  nix develop --no-update-lock-file --command true
)
test -f "$repo/.pre-commit-config.yaml"
hooks_path=$(git -C "$repo" config --local --get core.hooksPath)
test -n "$hooks_path"
test -x "$hooks_path/pre-commit"
test -x "$hooks_path/post-checkout"

# This must invoke post-checkout -> nix develop automatically.
git -C "$repo" worktree add -q --detach "$worktree" HEAD
test -f "$worktree/.pre-commit-config.yaml"
test -x "$hooks_path/pre-commit"
test "$(git -C "$worktree" config --get core.hooksPath)" = "$hooks_path"

assert_rejected() {
  local dir="$1"
  local name="$2"
  mkdir -p "$dir/.agents/skills/$name"
  cat > "$dir/.agents/skills/$name/SKILL.md" <<'EOF'
---
name: test-hook
description: Verify hook installation.
---

# Hook test

[Missing link](missing.md)
EOF
  git -C "$dir" add ".agents/skills/$name/SKILL.md"
  if git -C "$dir" -c user.name=CI -c user.email=ci@example.invalid \
    -c commit.gpgsign=false commit -q -m 'test: reject malformed skill' \
    >"$scratch/$name.log" 2>&1; then
    echo "Commit unexpectedly succeeded in $dir" >&2
    exit 1
  fi
  if ! grep -q 'broken relative link' "$scratch/$name.log"; then
    echo "Commit failed for a reason other than agent-docs in $dir:" >&2
    cat "$scratch/$name.log" >&2
    exit 1
  fi
}

assert_rejected "$worktree" worktree-probe
# Installing from a second worktree must not invalidate original hooks.
assert_rejected "$repo" primary-probe

# Prove the original hooks can still accept valid staged changes.
touch "$repo/.agents/skills/primary-probe/missing.md"
git -C "$repo" add .agents/skills/primary-probe
git -C "$repo" -c user.name=CI -c user.email=ci@example.invalid \
  -c commit.gpgsign=false commit -q -m 'test: accept valid skill'

echo "Linked worktree bootstrap and commit hooks passed"
