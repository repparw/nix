{
  den,
  inputs,
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
    { pkgs, ... }:
    {
      programs.mcp.servers.browse = {
        command = lib.getExe pkgs.opencode-browse;
        args = [ ];
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      checks = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        browse-mcp =
          let
            browse = inputs.self.nixosConfigurations.alpha.pkgs.opencode-browse;
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
                any(.[]; .id == 1 and .result.serverInfo.name == "browse" and .result.serverInfo.version == "${browse.version}")
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
