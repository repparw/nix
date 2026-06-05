{
  den,
  inputs,
  pkgs,
  ...
}:
{
  den.aspects.ai = {
    includes = [ ];

    homeManager =
      {
        config,
        pkgs,
        ...
      }:
      {
        imports = [ inputs.codex-desktop-linux.homeManagerModules.default ];

        home = {
          packages = [ pkgs.codex ];
          sessionVariables.CODEX_CLI_PATH = "${pkgs.codex}/bin/codex";
        };

        programs = {
          codexDesktopLinux = {
            enable = true;
            computerUseUi.enable = true;
            remoteMobileControl.enable = true;
            remoteControl = {
              enable = true;
              codexHome = "${config.xdg.configHome}/codex";
              package = pkgs.codex;
            };
          };

          codex = {
            enable = true;
            settings = {
              model = "gpt-5.5";
              model_reasoning_effort = "low";
              sandbox_mode = "danger-full-access";
              approval_policy = "never";
              personality = "pragmatic";

              plugins = {
                "browser@openai-bundled".enabled = true;
                "computer-use@openai-bundled".enabled = true;
                "github@openai-curated".enabled = true;
              };

              desktop = {
                keepRemoteControlAwakeWhilePluggedIn = false;
                "codex-linux-system-tray-enabled" = false;
                "codex-linux-warm-start-enabled" = false;
                appearanceDarkCodeThemeId = "tokyo-night";
                sansFontSize = 15;
                codeFontSize = 13;
                appearanceDarkChromeTheme = {
                  accent = "#3d59a1";
                  contrast = 60;
                  ink = "#a9b1d6";
                  opaqueWindows = true;
                  surface = "#1a1b26";
                  semanticColors = {
                    diffAdded = "#449dab";
                    diffRemoved = "#914c54";
                    skill = "#9d7cd8";
                  };
                };
              };

              features = {
                js_repl = false;
                memories = true;
              };

              memories = {
                generate_memories = true;
                use_memories = true;
              };

              projects."/home/repparw/Projects/nix".trust_level = "trusted";
            };
          };

          opencode = {
            enable = true;
            web = {
              enable = true;
              extraArgs = [
                "--hostname"
                "0.0.0.0"
                "--port"
                "4096"
              ];
            };
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
