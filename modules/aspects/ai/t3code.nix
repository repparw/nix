{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.ai.provides.t3code = {
    # The Stylix theme is a style concern, but it follows this application.
    includes = [
      (den.lib.policy.when (
        { user, ... }: user.hasAspect den.aspects.style
      ) den.aspects.style.provides.t3code-theme)
    ];

    provides.to-hosts.nixos = {
      programs.nix-ld.enable = true;
    };

    homeManager =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      let
        antigravityRuntime = pkgs.callPackage ../../_packages/antigravity-cli-runtime.nix { };
        providerState = import ../../_packages/t3code-provider-state.nix { inherit pkgs; };

        providerInstances = {
          antigravity = {
            driver = "antigravity";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "${antigravityRuntime.runtime}/bin/agy";
            };
          };

          antigravity_2 = {
            driver = "antigravity";
            displayName = "Antigravity 2";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "${antigravityRuntime.runtime}/bin/agy";
            };
          };

          # Both Codex instances share one CODEX_HOME for settings and
          # models; the second account keeps its auth in the shadow home.
          codex = {
            driver = "codex";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "codex";
              homePath = "${config.xdg.configHome}/codex";
            };
          };

          codex_2 = {
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

          opencode = {
            driver = "opencode";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "${config.programs.opencode.package}/bin/opencode";
            };
          };
        };
      in
      {
        programs.t3code = {
          enable = true;
          package = lib.mkDefault (if pkgs ? t3code-desktop then pkgs.t3code-desktop else pkgs.t3code);

          userSettings.providerInstances = providerInstances;

          server = {
            enable = true;
            environmentFile = pkgs.writeText "t3code-environment" ''
              CODEX_HOME=${config.xdg.configHome}/codex
            '';
          };
        };

        # Home Manager merges mutable settings instead of replacing them, so
        # omitted provider instances would otherwise survive in the live file.
        home.activation.t3codeProviderStateActivation =
          lib.hm.dag.entryAfter
            [
              "t3codeSettingsActivation"
            ]
            ''
              if [[ -v DRY_RUN ]]; then
                echo 'Would reconcile T3 Code provider instances and stale caches.'
              else
                provider_state=$(
                  ${providerState.cleanupScript} \
                    ${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata/settings.json"} \
                    ${lib.escapeShellArg "${config.home.homeDirectory}/.t3/caches"} \
                    ${lib.escapeShellArg (builtins.toJSON (lib.attrNames providerInstances))} \
                    ${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata/provider-instances.sha256"}
                )
                if [ "$provider_state" = changed ]; then
                  # Home Manager's system activation runs with a minimal PATH;
                  # a bare systemctl is not found there (NixOS/nixpkgs pattern:
                  # use the store path, like fleet-controller's scripts).
                  if ! ${lib.getExe' pkgs.systemd "systemctl"} --user restart t3code.service; then
                    rm -f ${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata/provider-instances.sha256"}
                    exit 1
                  fi
                fi
              fi
            '';
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
