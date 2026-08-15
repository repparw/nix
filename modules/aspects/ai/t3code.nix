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
    nixos =
      { pkgs, ... }:
      {
        # Upstream t3code >= 0.0.31 delegates OpenCode session titles to the
        # provider, but opencode auto-names sessions "New session - <ts>",
        # which then clobbers the thread title and blocks the real generated
        # title. Mirror the upstream PR (pingdotgg/t3code#5941): only mirror a
        # provider title while the thread still has its default title, and
        # filter opencode's placeholder title so it never propagates. Revisit
        # once the fix is merged upstream and reaches our nixpkgs pin.
        nixpkgs.overlays = [
          (final: prev: {
            t3code = prev.t3code.override {
              t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [ ./t3code-title-fix.patch ];
              });
            };
          })
        ];
      };

    homeManager =
      { pkgs, ... }:
      {
        home.sessionVariables = connectEnvironment;

        programs.t3code.enable = true;

        # Point the opencode provider at the opencode-web.service server
        # (programs.opencode.web, port 4096) instead of spawning its own
        # per-session `opencode serve`. With serverUrl set, t3code treats the
        # server as external and never starts a child process.
        programs.t3code.userSettings = {
          providerInstances.opencode = {
            driver = "opencode";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "";
              serverUrl = "http://127.0.0.1:4096";
            };
          };
        };

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
