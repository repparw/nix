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
    { config, pkgs, ... }:
    let
      browseMcp = pkgs.writeShellScriptBin "browse-mcp" ''
        exec ${lib.getExe pkgs.python3} ${../../scripts/browse-mcp-lazy.py} \
          ${lib.getExe pkgs.opencode-browse} \
          ${lib.getExe' config.programs.helium.package "helium"} \
          ${lib.getExe' pkgs.procps "pgrep"}
      '';
    in
    {
      programs.mcp.servers.browse = {
        command = lib.getExe browseMcp;
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
                pkgs.python3
              ];
            }
            ''
              ${lib.getExe pkgs.python3} -m unittest discover -s ${../../scripts} -p test_browse_mcp_lazy.py
              export HOME="$TMPDIR/browse-home"
              mkdir -p "$HOME"
              {
                printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}'
                printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
              } | timeout 15 ${lib.getExe pkgs.python3} ${../../scripts/browse-mcp-lazy.py} \
                ${lib.getExe browse} /missing-helium ${lib.getExe' pkgs.procps "pgrep"} \
                > "$TMPDIR/response.json"
              jq -se '
                any(.[]; .id == 1 and .result.serverInfo.name == "browse" and .result.serverInfo.version == "${browse.version}")
                and any(.[]; .id == 2 and (
                  [.result.tools[].name] as $tools
                  | ($tools | index("navigate") != null)
                    and ($tools | index("snapshot") != null)
                    and ($tools | index("execute") == null)
                ))
              ' "$TMPDIR/response.json"
              # Codex and other non-OpenCode clients receive the execute tool.
              {
                printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"codex","version":"1"}}}'
                printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
              } | timeout 15 ${lib.getExe pkgs.python3} ${../../scripts/browse-mcp-lazy.py} \
                ${lib.getExe browse} /missing-helium ${lib.getExe' pkgs.procps "pgrep"} \
                > "$TMPDIR/execute-response.json"
              jq -se '
                any(.[]; .id == 1 and (
                  (.result.instructions | contains("Never solve") | not)
                  and (.result.instructions | contains("handoff"))
                ))
                and any(.[]; .id == 2 and any(.result.tools[];
                  .name == "execute"
                  and (.description | contains("never solve") | not)
                  and (.inputSchema.properties.code.description | contains("when only the user") | not)
                ))
              ' "$TMPDIR/execute-response.json"
              touch "$out"
            '';
      };
    };
}
