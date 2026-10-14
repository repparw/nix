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
        launcher = config.programs.t3code.userSettings.providerInstances.opencode-v2.config.binaryPath;
      in
      {
        programs.opencode = {
          package = pkgs.writeShellScriptBin "opencode" ''
            exec ${lib.escapeShellArg launcher} "$@"
          '';
          web.enable = lib.mkForce false;
        };
        programs.t3code.userSettings.providerInstances = {
          opencode = {
            displayName = "OpenCode 2";
            config = {
              binaryPath = lib.mkForce launcher;
              serverUrl = lib.mkForce "";
            };
          };
          opencode-v2 = {
            enabled = lib.mkForce false;
            config.enabled = lib.mkForce false;
          };
          opencode-v1 = {
            driver = "opencode";
            displayName = "OpenCode 1 rollback";
            enabled = false;
            config = {
              enabled = false;
              binaryPath = "${pkgs.opencode}/bin/opencode";
              serverUrl = "http://127.0.0.1:4096";
            };
          };
        };
      };
  };
}
