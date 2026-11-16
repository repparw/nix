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
        stitch = pkgs.callPackage ../../_packages/kof-stitch-mcp.nix { nodejs = pkgs.nodejs_24; };
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
    { config, pkgs, ... }:
    let
      browse = pkgs.callPackage ../../_packages/opencode-browse.nix { };
      browseMcp = pkgs.writeShellScriptBin "browse-mcp" ''
        exec ${lib.getExe pkgs.python3} ${../../scripts/browse-mcp-lazy.py} \
          ${lib.getExe browse} \
          ${lib.getExe' config.programs.helium.package "helium"} \
          ${lib.getExe' pkgs.procps "pgrep"}
      '';
    in
    {
      programs.mcp.servers.browse = {
        command = lib.getExe browseMcp;
        args = [ ];
        env = {
          OPENCODE_BROWSER_AUTO_UPDATE = "off";
        };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        browse-mcp =
          let
            browse = pkgs.callPackage ../../_packages/opencode-browse.nix { };
          in
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
              {
                printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}'
                printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
              } | timeout 15 ${lib.getExe browse} mcp > "$TMPDIR/response.json"
              jq -se '
                any(.[]; .id == 1 and .result.serverInfo.name == "browse" and .result.serverInfo.version == "0.1.0")
                and any(.[]; .id == 2 and (
                  [.result.tools[].name] as $tools
                  | ($tools | index("navigate") != null)
                    and ($tools | index("snapshot") != null)
                    and ($tools | index("execute") == null)
                ))
              ' "$TMPDIR/response.json"
              touch "$out"
            '';
      };
    };
}
