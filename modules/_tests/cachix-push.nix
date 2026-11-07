{ pkgs }:
let
  mockNix = pkgs.writeShellScriptBin "nix-store" ''
    case "$3" in
      /nix/store/failed-query) exit 1 ;;
      /nix/store/system) printf '%s\n' "$3" /nix/store/activation /nix/store/vault.sops.yaml ;;
      /nix/store/vault.sops.yml|/nix/store/vault.sops.yaml) printf '%s\n' "$3" ;;
      *) printf '%s\n' "$3" /nix/store/library ;;
    esac
  '';
  mockCachix = pkgs.writeShellScriptBin "cachix" ''
    printf '%s\n' "$*" >> "$TEST_CALLS"
    test "''${TEST_UPLOAD_FAIL:-0}" = 0
  '';
  aspect = (import ../aspects/cachix-push.nix { den = { }; }).den.aspects.cachix-push;
  module = aspect.nixos {
    pkgs = pkgs // {
      nix = mockNix;
      cachix = mockCachix;
    };
    config = {
      networking.hostName = "alpha";
      sops.secrets.cachix-push-token.path = "/run/secrets/cachix-push-token";
    };
  };
  hook = module.nix.settings.post-build-hook;
in
pkgs.runCommand "check-cachix-push" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
  shellcheck ${hook}
  export TEST_CALLS="$PWD/calls"
  touch "$TEST_CALLS"
  OUT_PATHS="" ${hook}
  test ! -s "$TEST_CALLS"
  OUT_PATHS="/nix/store/vault.sops.yml /nix/store/vault.sops.yaml /nix/store/system /nix/store/failed-query" ${hook}
  test ! -s "$TEST_CALLS"
  OUT_PATHS="/nix/store/package /nix/store/system /nix/store/other" ${hook}
  printf '%s\n' \
    'daemon push --socket /run/cachix-push/daemon.sock /nix/store/package' \
    'daemon push --socket /run/cachix-push/daemon.sock /nix/store/other' > expected
  diff -u expected "$TEST_CALLS"
  TEST_UPLOAD_FAIL=1 OUT_PATHS="/nix/store/package" ${hook}
  touch $out
''
