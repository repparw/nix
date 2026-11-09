{
  den,
  lib,
  ...
}:
{
  den.aspects.ai.provides.mcp = {
    homeManager =
      { pkgs, ... }:
      let
        stitch = pkgs.callPackage ../../_packages/kof-stitch-mcp.nix { nodejs = pkgs.nodejs-runtime; };
      in
      {
        home.packages = [
          pkgs.mcp-nixos
          pkgs.google-cloud-sdk
        ];

        programs.mcp = {
          enable = true;
          servers = {
            nixos = {
              command = "${lib.getExe pkgs.mcp-nixos}";
              args = [ ];
            };
            stitch = {
              command = lib.getExe stitch;
              args = [ ];
              env = {
                GOOGLE_CLOUD_PROJECT = "gen-lang-client-0649723761";
              };
            };
          };
        };
      };
  };

  den.aspects.ai.provides.browse-desktop.homeManager =
    { pkgs, ... }:
    let
      browse = pkgs.callPackage ../../_packages/opencode-browse.nix {
        nodejs-runtime = pkgs.nodejs-runtime;
      };
    in
    {
      programs.mcp.servers.browse = {
        command = lib.getExe browse;
        args = [ "mcp" ];
        env = {
          OPENCODE_BROWSER_AUTO_UPDATE = "off";
        };
      };
    };

  # Exercise the real packaged CLI, not the host-eval stubs.
  perSystem =
    { pkgs, ... }:
    let
      browse = pkgs.callPackage ../../_packages/opencode-browse.nix {
        # perSystem packages do not inherit host-scoped overlays.
        nodejs-runtime = pkgs.nodejs_24;
      };
    in
    {
      # Keep the CLI accessible on demand without adding it to the user PATH.
      # Run from the flake checkout with: nix run .#browse -- pair
      packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        inherit browse;
      };

      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        browse-mcp =
          pkgs.runCommand "check-browse-mcp"
            {
              nativeBuildInputs = [
                pkgs.jq
                pkgs.coreutils
              ];
            }
            ''
              export HOME="$TMPDIR/browse-home"
              mkdir -p "$HOME"
              test "$(${lib.getExe browse} --version)" = "0.0.15"
              status=0
              printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"nix-ci","version":"1"}}}' \
                | timeout 15 ${lib.getExe browse} mcp > "$TMPDIR/initialize.json" || status=$?
              # The CLI currently exits 130 when the JSON-RPC input pipe closes.
              # Accept that shutdown only if initialization produced a valid response.
              test "$status" -eq 0 || test "$status" -eq 130
              jq -se 'any(.[]; .id == 1 and .result.serverInfo.name == "browse" and .result.serverInfo.version == "0.0.15")' \
                "$TMPDIR/initialize.json"
              touch "$out"
            '';
      };
    };
}
