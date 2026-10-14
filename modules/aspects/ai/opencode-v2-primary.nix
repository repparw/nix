{ den, ... }:
{
  den.aspects.ai.provides.opencode-v2-primary = {
    includes = [ den.aspects.ai._.opencode-v2 ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        launcher = pkgs.writeShellScriptBin "opencode2" ''
          export XDG_DATA_HOME=${lib.escapeShellArg "${config.xdg.dataHome}/opencode-v2"}
          export XDG_CONFIG_HOME=${lib.escapeShellArg "${config.xdg.configHome}/opencode-v2"}
          export XDG_CACHE_HOME=${lib.escapeShellArg "${config.xdg.cacheHome}/opencode-v2"}
          export XDG_STATE_HOME=${lib.escapeShellArg "${config.xdg.stateHome}/opencode-v2"}
          exec ${pkgs.opencode-v2}/bin/opencode2 "$@"
        '';
      in
      {
        home.packages = [ launcher ];
        programs.opencode = {
          package = pkgs.writeShellScriptBin "opencode" ''
            exec ${lib.escapeShellArg launcher} "$@"
          '';
          web.enable = lib.mkForce false;
        };
        programs.t3code.userSettings.providerInstances.opencode = {
          displayName = "OpenCode 2";
          config = {
            binaryPath = lib.mkForce launcher;
            serverUrl = lib.mkForce "";
          };
        };
      };
  };
}
