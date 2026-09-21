#!/usr/bin/env bash
set -euo pipefail

gate=${1:?gate ID required}
action=${2:?completed, apply, or verify required}
ai=modules/aspects/ai/default.nix
cliamp=modules/aspects/cliamp.nix
t3code=modules/aspects/ai/t3code.nix
arr=modules/aspects/services/arr.nix

absent() {
  [[ -f $2 ]] || { echo "Missing completion-check file: $2" >&2; return 2; }
  local status
  if grep -F -- "$1" "$2" > /dev/null; then
    return 1
  else
    status=$?
    [[ $status == 1 ]] || return "$status"
  fi
}

replace_block() {
  local file=$1 start=$2 end=$3 replacement=${4:-} tmp
  tmp=$(mktemp)
  if awk -v start="$start" -v end="$end" -v replacement="$replacement" '
    $0 == start { starts++; skipping=1; if (replacement != "") print replacement; next }
    skipping && $0 == end { ends++; skipping=0; next }
    !skipping { print }
    END { if (starts != 1 || ends != 1 || skipping) exit 1 }
  ' "$file" > "$tmp"; then
    cat "$tmp" > "$file"
    rm "$tmp"
  else
    rm "$tmp"
    echo "Expected one complete block in $file" >&2
    exit 1
  fi
}

if [[ $action == completed ]]; then
  case "$gate" in
    moonshine-pulse-fix)
      [[ ! -e modules/aspects/streaming-pulse-crash-fix.nix ]] &&
        [[ ! -e modules/aspects/moonshine-pr184-pulse-client-stall.patch ]] &&
        [[ ! -e modules/aspects/moonshine-pr167-timerfd-eagain.patch ]] &&
        absent 'pulse-crash-fix' modules/hosts/alpha.nix ;;
    qbittorrent-pr-24055) absent 'qbittorrent-nox.overrideAttrs' "$arr" ;;
    nixpkgs-555921-t3code-connect)
      [[ ! -e modules/aspects/ai/t3code-connect.nix ]] && absent 't3code-connect' "$ai" ;;
    nixpkgs-555814-t3code-split)
      [[ ! -e modules/aspects/ai/t3code-split.nix ]] &&
        absent 't3code-split' "$ai" && absent 't3code-split' modules/entities.nix ;;
    home-manager-9695-t3code-server)
      absent 't3code-web' "$t3code" && absent 't3code-web' docs/runbooks/prune-t3code-opencode-dbs.md ;;
    nixpkgs-voxtype-graphical-session)
      [[ ! -e modules/aspects/ai/voxtype-graphical-workaround.nix ]] && absent 'voxtype-graphical-workaround' "$ai" ;;
    home-manager-9842-cliamp) absent 'hmCliampModule' "$cliamp" ;;
    cliamp-attach-453) absent 'ryanrpj' "$cliamp" ;;
    *) echo "No completion check for $gate" >&2; exit 2 ;;
  esac
elif [[ $action == apply ]]; then
  case "$gate" in
    moonshine-pulse-fix)
      git rm -- modules/aspects/streaming-pulse-crash-fix.nix \
        modules/aspects/moonshine-pr184-pulse-client-stall.patch modules/aspects/moonshine-pr167-timerfd-eagain.patch
      sed -i '/^[[:space:]]*den\.aspects\.streaming\._\.pulse-crash-fix[[:space:]]*$/d' modules/hosts/alpha.nix ;;
    qbittorrent-pr-24055)
      replace_block "$arr" '              nixpkgs.overlays = [' '              ];' ;;
    nixpkgs-555921-t3code-connect)
      git rm -- modules/aspects/ai/t3code-connect.nix
      sed -i '/^[[:space:]]*t3code-connect[[:space:]]*$/d' "$ai" ;;
    nixpkgs-555814-t3code-split)
      git rm -- modules/aspects/ai/t3code-split.nix
      sed -i '/^[[:space:]]*t3code-split[[:space:]]*$/d' "$ai"
      sed -i '/^[[:space:]]*den\.aspects\.ai\._\.t3code-split[[:space:]]*$/d' modules/entities.nix ;;
    home-manager-9695-t3code-server)
      replacement=$(cat <<'BLOCK'
        programs.t3code.package = pkgs.t3code;
        programs.t3code.server = {
          enable = true;
          extraArgs = [ "--mode" "web" ];
        };
        systemd.user.services.t3code.Service.Environment =
          lib.mapAttrsToList (name: value: "${name}=${value}") connectEnvironment
          ++ [ "T3CODE_DISABLE_PROVIDER_UPDATE_NOTIFICATIONS=1" ];
BLOCK
)
      replace_block "$t3code" '        # TODO: Replace this hand-rolled service with programs.t3code.server' '        };' "$replacement"
      sed -i 's/t3code-web\.service/t3code.service/g' docs/runbooks/prune-t3code-opencode-dbs.md ;;
    nixpkgs-voxtype-graphical-session)
      git rm -- modules/aspects/ai/voxtype-graphical-workaround.nix
      sed -i '/^[[:space:]]*voxtype-graphical-workaround[[:space:]]*$/d' "$ai" ;;
    home-manager-9842-cliamp)
      replace_block "$cliamp" 'let' 'in'
      sed -i '/home-manager\.sharedModules = \[ hmCliampModule \];/d' "$cliamp" ;;
    cliamp-attach-453)
      replace_block "$cliamp" '      nixpkgs.overlays = [' '      ];' ;;
    *) echo "No cleanup for $gate" >&2; exit 2 ;;
  esac
elif [[ $action == verify ]]; then
  hosts=$(nix eval .#nixosConfigurations --apply builtins.attrNames --json --no-update-lock-file)
  mapfile -t host_names < <(jq -r '.[]' <<< "$hosts")
  for host in "${host_names[@]}"; do
    nix eval ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" --raw --no-update-lock-file > /dev/null
  done
  build() { nix build "$1" --no-link --print-out-paths --no-update-lock-file; }
  case "$gate" in
    moonshine-pulse-fix) build .#nixosConfigurations.alpha.pkgs.moonshine > /dev/null ;;
    qbittorrent-pr-24055) build .#nixosConfigurations.alpha.pkgs.qbittorrent-nox > /dev/null ;;
    nixpkgs-555921-t3code-connect)
      output=$(build .#nixosConfigurations.alpha.pkgs.t3code)
      key=pk_live_Y2xlcmsudDMuY29kZXMk
      grep -rF "$key" "$output/libexec/t3code/apps/server/dist/client/assets" > /dev/null
      grep -F "$key" "$output/libexec/t3code/apps/server/dist/bin.mjs" > /dev/null
      grep -F 'x-scheme-handler/t3code' "$output/share/applications/t3code.desktop" > /dev/null ;;
    nixpkgs-555814-t3code-split)
      for host in alpha pi; do
        output=$(build ".#nixosConfigurations.$host.pkgs.t3code")
        [[ -e $output/bin/t3 && ! -e $output/bin/t3code-desktop ]]
        if [[ $host == pi ]]; then
          closure=$(nix-store -qR "$output")
          if grep -i electron <<< "$closure" > /dev/null; then
            echo 'Pi t3code closure still contains Electron' >&2
            exit 1
          fi
        fi
      done ;;
    home-manager-9695-t3code-server)
      unit=$(nix eval .#nixosConfigurations.alpha.config.home-manager.users.repparw.systemd.user.services.t3code --json --no-update-lock-file)
      jq -e '.Service.ExecStart | contains("serve")' <<< "$unit" > /dev/null ;;
    nixpkgs-voxtype-graphical-session) nix flake check --no-build --no-update-lock-file ;;
    home-manager-9842-cliamp) ;;
    cliamp-attach-453)
      output=$(build .#nixosConfigurations.alpha.pkgs.cliamp)
      help=$("$output/bin/cliamp" --help)
      grep -F attach <<< "$help" > /dev/null ;;
    *) echo "No validation for $gate" >&2; exit 2 ;;
  esac
else
  echo "Unknown action: $action" >&2
  exit 2
fi
