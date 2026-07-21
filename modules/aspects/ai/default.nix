{
  den,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  flake-file.inputs.codex-desktop-linux = {
    url = "github:ilysenko/codex-desktop-linux";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
    };
  };

  den.aspects.ai = {
    includes = with den.aspects.ai._; [
      dictation
      speech
    ];

    nixos =
      { config, ... }:
      {
        hardware.uinput.enable = true;

        programs.ydotool = {
          enable = true;
          group = "uinput";
        };

        users.groups.uinput.members = [ config.users.users.repparw.name ];
      };

    homeManager =
      {
        config,
        pkgs,
        ...
      }:
      let
        mprisPlayback = pkgs.callPackage ../../_packages/mpris-playback.nix { };
        codexDesktop =
          inputs.codex-desktop-linux.packages.${pkgs.stdenv.hostPlatform.system}.codex-desktop-computer-use-ui-remote-mobile-control;
        codexDesktopLauncher = pkgs.writeShellScriptBin "codex-desktop" ''
          exec ${pkgs.systemd}/bin/systemctl --user restart codex-desktop.service
        '';
        singletonCodexDesktop = pkgs.symlinkJoin {
          name = "${codexDesktop.name}-single-instance";
          paths = [ codexDesktop ];
          postBuild = ''
            rm -f "$out/bin/codex-desktop"
            ln -s ${codexDesktopLauncher}/bin/codex-desktop "$out/bin/codex-desktop"

            desktopFile="$out/share/applications/codex-desktop.desktop"
            desktopTarget="$(readlink -f "$desktopFile")"
            rm -f "$desktopFile"
            substitute "$desktopTarget" "$desktopFile" \
              --replace-fail "${codexDesktop}/bin/codex-desktop" "$out/bin/codex-desktop"
          '';
          meta = codexDesktop.meta;
        };

      in
      {
        _module.args = { inherit mprisPlayback; };

        imports = [ inputs.codex-desktop-linux.homeManagerModules.default ];

        # TODO: Add custom OpenCode models to the desktop picker once upstream stops
        # filtering model_catalog_json entries: https://github.com/openai/codex/issues/19694
        home = {
          packages = [
            pkgs.codex
            pkgs.mcp-nixos
            pkgs.nh
          ];
          file.".codex/ds4-flash-free.config.toml".text = ''
            model = "deepseek-v4-flash-free"
            model_provider = "opencode"
            model_reasoning_effort = "minimal"
          '';
        };

        programs = {
          codexDesktopLinux = {
            enable = true;
            package = singletonCodexDesktop;
            cliPackage = pkgs.codex;
            remoteControl = {
              enable = true;
              codexHome = "${config.xdg.configHome}/codex";
            };
          };

          mcp = {
            enable = true;
            servers = {
              nixos = {
                command = "${lib.getExe pkgs.mcp-nixos}";
                args = [ ];
              };
            };
          };

          codex = {
            enable = true;
            skills = { };
          };

          opencode = {
            enable = true;
            enableMcpIntegration = true;
            skills = { };
            settings = {
              permission = {
                "*" = {
                  "*" = "allow";
                };
              };
              formatter = false;
              provider = {
                oc-galo = {
                  npm = "@ai-sdk/openai-compatible";
                  name = "oc-galo";
                  options = {
                    baseURL = "https://opencode.ai/zen/go/v1";
                  };
                  models = {
                    deepseek-v4-flash = {
                      name = "DeepSeek V4 Flash";
                    };
                    deepseek-v4-pro = {
                      name = "DeepSeek V4 Pro";
                    };
                    "kimi-k2.6" = {
                      name = "Kimi K2.6";
                    };
                  };
                };
              };
            };
          };

          t3code.enable = true;
        };

        systemd.user.services.t3code-web = {
          Unit = {
            Description = "T3 Code Web Service";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${pkgs.t3code}/bin/t3 serve --host 0.0.0.0 --port 4097 --mode web";
            Restart = "always";
            RestartSec = 5;
            Environment = [
              "T3CODE_DISABLE_PROVIDER_UPDATE_NOTIFICATIONS=1"
            ];
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };

        systemd.user.services.codex-desktop = {
          Unit = {
            Description = "Codex Desktop (single instance)";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Environment = [
              "CODEX_CLI_PATH=${lib.getExe pkgs.codex}"
              "CODEX_HOME=${config.xdg.configHome}/codex"
            ];
            ExecStart = lib.getExe codexDesktop;
            # Electron moves itself into a transient scope; stop it explicitly
            # so a service restart cannot reuse a stale singleton process.
            ExecStop = "-${pkgs.systemd}/bin/systemctl --user stop app-codex-desktop-*.scope";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # systemd.user.services.opencode-web = {
        #   Unit = {
        #     After = [ "graphical-session.target" ];
        #     Wants = [ "graphical-session.target" ];
        #   };
        #   Service.Environment = [
        #     "PATH=/run/wrappers/bin:${config.home.homeDirectory}/.nix-profile/bin:/nix/profile/bin:${config.home.homeDirectory}/.local/state/nix/profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        #     "SUDO_ASKPASS=${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass"
        #   ];
        # };
      };
  };
}
