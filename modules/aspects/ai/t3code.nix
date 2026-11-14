{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.ai.provides.t3code = {
    # The Stylix theme is a style concern, but it follows this application.
    includes = [ den.aspects.style.provides.t3code-theme ];

    provides.to-hosts.nixos = {
      # T3 launches the chrome-headless-shell it downloads at runtime. That is
      # a generic Linux ELF, so NixOS needs the nix-ld interpreter stub before
      # it can run at all; the browser libraries ride on the pin
      # (NixOS/nixpkgs#575675, watcher t3code-browser-libs).
      programs.nix-ld.enable = true;
    };

    homeManager =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      {
        programs.t3code = {
          enable = true;
          package = lib.mkDefault (if pkgs ? t3code-desktop then pkgs.t3code-desktop else pkgs.t3code);

          userSettings = {
            providerInstances.antigravity = {
              driver = "antigravity";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "${pkgs.antigravity-acp}/bin/agy_acp_server.par";
              };
            };

            providerInstances.opencode = {
              driver = "opencode";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "${config.programs.opencode.package}/bin/opencode";
                serverUrl = "";
              };
            };
          };

          server = {
            enable = true;
            extraArgs = [
              "--mode"
              "web"
            ];
            environmentFile = pkgs.writeText "t3code-environment" ''
              CODEX_HOME=${config.xdg.configHome}/codex
            '';
          };
        };
      };
  };
}
