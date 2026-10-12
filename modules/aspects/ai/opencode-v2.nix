{ den, ... }:
{
  den.aspects.ai.provides.opencode-v2 = {
    nixos.nixpkgs.overlays = [
      (final: _prev: {
        opencode-v2 = final.callPackage ../../_packages/opencode-v2.nix { };
      })
    ];
    homeManager =
      { config, pkgs, ... }:
      let
        launcher = pkgs.writeShellScriptBin "opencode2" ''
          export XDG_DATA_HOME=${pkgs.lib.escapeShellArg "${config.xdg.dataHome}/opencode-v2"}
          export XDG_CONFIG_HOME=${pkgs.lib.escapeShellArg "${config.xdg.configHome}/opencode-v2"}
          export XDG_CACHE_HOME=${pkgs.lib.escapeShellArg "${config.xdg.cacheHome}/opencode-v2"}
          export XDG_STATE_HOME=${pkgs.lib.escapeShellArg "${config.xdg.stateHome}/opencode-v2"}
          exec ${pkgs.opencode-v2}/bin/opencode2 "$@"
        '';
      in
      {
        home.packages = [ launcher ];
        xdg.configFile = {
          "opencode-v2/opencode/opencode.json".text = builtins.toJSON (
            config.programs.opencode.settings // { plugin = [ ]; }
          );
          "opencode-v2/opencode/plugins/nous-live.ts".source = ./opencode-plugins/nous-live-v2.ts;
          "opencode-v2/opencode/skills".source =
            config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/opencode/skills";
          "opencode-v2/opencode/AGENTS.md".source =
            config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/opencode/AGENTS.md";
        };
        programs.t3code.userSettings.providerInstances.opencode-v2 = {
          driver = "opencode";
          displayName = "OpenCode 2";
          enabled = true;
          config = {
            enabled = true;
            binaryPath = "${launcher}/bin/opencode2";
            serverUrl = "";
          };
        };
      };
  };
  perSystem = { pkgs, ... }: {
    packages.opencode-v2 = pkgs.callPackage ../../_packages/opencode-v2.nix { };
  };
}
