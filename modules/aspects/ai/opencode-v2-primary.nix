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
        launcherPackage = pkgs.writeShellScriptBin "opencode2" ''
          export XDG_DATA_HOME=${lib.escapeShellArg "${config.xdg.dataHome}/opencode-v2"}
          export XDG_CONFIG_HOME=${lib.escapeShellArg "${config.xdg.configHome}/opencode-v2"}
          export XDG_CACHE_HOME=${lib.escapeShellArg "${config.xdg.cacheHome}/opencode-v2"}
          export XDG_STATE_HOME=${lib.escapeShellArg "${config.xdg.stateHome}/opencode-v2"}
          exec ${pkgs.opencode-v2}/bin/opencode2 "$@"
        '';
        launcher = "${launcherPackage}/bin/opencode2";
        json5 = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.json5;
      in
      {
        home.packages = [ launcherPackage ];
        home.activation.t3codeProviderCleanup = lib.hm.dag.entryBefore [ "t3codeSettingsActivation" ] (
          lib.hm.generators.mkImpureConfigMerger {
            inherit pkgs;
            format = "json";
            empty = "{}";
            jqOperation = ''
              $dynamic | del(
                .providerInstances."opencode-v2",
                .providerInstances."opencode-v2-trial",
                .providerInstances."opencode-v1"
              )
            '';
            path = "${config.home.homeDirectory}/.t3/userdata/settings.json";
            mode = "600";
            staticSettings = pkgs.writeText "t3code-provider-cleanup" "{}";
            reader = "${lib.getExe json5} --as-json";
          }
        );
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
