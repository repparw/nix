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
            # T3's built-in Antigravity provider needs the standalone ACP
            # runtime, not the Antigravity IDE or CLI. nixpkgs keeps its
            # localharness_external helper next to this executable.
            # Each instance ID gets its own Antigravity profile, so the
            # second instance signs in to a different Google account while
            # sharing the executable.
            providerInstances.antigravity = {
              driver = "antigravity";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "${pkgs.antigravity-acp}/bin/agy_acp_server.par";
              };
            };

            providerInstances.antigravity_2 = {
              driver = "antigravity";
              displayName = "Antigravity 2";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "${pkgs.antigravity-acp}/bin/agy_acp_server.par";
              };
            };

            # Both Codex instances share one CODEX_HOME for settings and
            # models; the second account keeps its auth in the shadow home.
            providerInstances.codex = {
              driver = "codex";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "codex";
                homePath = "${config.xdg.configHome}/codex";
              };
            };

            providerInstances.codex_2 = {
              driver = "codex";
              displayName = "2";
              enabled = true;
              config = {
                enabled = true;
                setupMode = "existing";
                binaryPath = "codex";
                homePath = "${config.xdg.configHome}/codex";
                shadowHomePath = "${config.xdg.configHome}/codex-ubritos1";
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

  # Desktop-session half of Connect: the launcher and the t3code:// handler
  # only matter where a graphical browser runs. Hosts pick this up through
  # aspect composition (den.aspects.desktop) instead of a capability flag.
  den.aspects.ai.provides.t3code-connect-desktop.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      launcher = pkgs.writeShellScriptBin "t3code-desktop-connect" ''
        export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}
        exec ${lib.getExe' config.programs.t3code.package "t3code-desktop"} "$@"
      '';
    in
    {
      home.packages = [ launcher ];

      # Browsers resolve URL schemes through GIO, which only consults
      # `mimeinfo.cache` associations when `mimeapps.list` names a default.
      # The app's own `xdg-mime default` call is skipped while Electron runs
      # unpackaged, so declare the handler instead of relying on runtime
      # registration.
      xdg.mimeApps = {
        enable = true;
        defaultApplications."x-scheme-handler/t3code" = "t3code.desktop";
      };

      xdg.desktopEntries.t3code = {
        name = "T3 Code (Alpha)";
        exec = "t3code-desktop-connect %U";
        icon = "t3code";
        settings.StartupWMClass = "t3code";
        categories = [ "Development" ];
        mimeType = [ "x-scheme-handler/t3code" ];
      };
    };
}
