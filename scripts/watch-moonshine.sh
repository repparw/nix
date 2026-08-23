#!/usr/bin/env bash
# Watch for Nixpkgs #544393 (services.moonshine) landing on nixos-unstable.
# When ready: bump the pin, verify eval, push, merge PR #31, close issue #24.
set -euo pipefail

URL="https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/nixos/modules/services/networking/moonshine.nix"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

notify() { notify-send -a watch-moonshine "$1" "$2" 2>/dev/null || true; }

# Already done? (head branch deleted by merge)
if ! git ls-remote --heads origin codex/use-upstream-moonshine-module | grep -q .; then
  echo "PR #31 head branch gone (already merged); disabling watcher"
  systemctl --user disable --now watch-moonshine.timer || true
  exit 0
fi

if ! curl -sfI "$URL" | grep -q "^HTTP/.* 200"; then
  echo "not ready: $URL still 404"
  exit 0
fi

notify "Moonshine module landed on nixos-unstable" "Bumping pin and merging PR #31..."

echo "upstream ready, bumping flake pin..."
git fetch origin main
git checkout main
git pull --ff-only origin main

nix flake update nixpkgs
pin=$(nix flake metadata --json | jq -r '.locks.nodes.root.inputs.nixpkgs as $k | .locks.nodes[$k].locked.rev')
echo "pin now at $pin"

echo "verifying services.moonshine resolves from nixpkgs..."
for host in $(nix eval .#nixosConfigurations --apply 'builtins.attrNames' --json | jq -r '.[]'); do
  if ! nix eval ".#nixosConfigurations.$host" --apply 'c: c.config.services.moonshine.enable' >/dev/null 2>&1; then
    notify "Moonshine unblock FAILED" "Eval failed for host $host — pin bumped but not pushed. Check journalctl --user -u watch-moonshine"
    echo "eval failed for $host" >&2
    exit 1
  fi
  echo "  $host: ok"
done

git add flake.lock
git commit -m "flake.lock: Update"
git push origin main

gh pr ready 31
gh pr merge 31 --squash --delete-branch

gh issue close 24 \
  --comment "NixOS/nixpkgs#544393 is on nixos-unstable ($pin); vendored module removed in #31."

systemctl --user disable --now watch-moonshine.timer || true
notify "Moonshine unblock complete" "nixpkgs pin bumped to $pin, PR #31 merged, issue #24 closed."
echo "done: pin bumped, PR #31 merged, issue #24 closed"
