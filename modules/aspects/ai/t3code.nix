{
  den,
  lib,
  pkgs,
  ...
}:
let
  connectEnvironment = {
    T3CODE_CLERK_PUBLISHABLE_KEY = "pk_live_Y2xlcmsudDMuY29kZXMk";
    T3CODE_CLERK_JWT_TEMPLATE = "t3-relay";
    T3CODE_CLERK_CLI_OAUTH_CLIENT_ID = "hzxSgY2cH10sDU2r";
    T3CODE_RELAY_URL = "https://relay.t3.codes";
  };
in
{
  den.aspects.ai.provides.t3code = {
    homeManager =
      { pkgs, ... }:
      {
        home.sessionVariables = connectEnvironment;

        programs.t3code.enable = true;

        # TODO: Replace this hand-rolled service with programs.t3code.server
        # once https://github.com/nix-community/home-manager/pull/9695 merges
        # and reaches our pinned input.
        systemd.user.services.t3code-web = {
          Unit = {
            Description = "T3 Code Web Service";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${pkgs.t3code}/bin/t3 serve --mode web";
            Restart = "always";
            RestartSec = 5;
            Environment = (lib.mapAttrsToList (name: value: "${name}=${value}") connectEnvironment) ++ [
              "T3CODE_DISABLE_PROVIDER_UPDATE_NOTIFICATIONS=1"
            ];
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
  };
}
