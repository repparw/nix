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

  den.aspects.ai.provides.codex = {
    homeManager =
      {
        config,
        pkgs,
        ...
      }:
      let
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
        imports = [ inputs.codex-desktop-linux.homeManagerModules.default ];

        # TODO: Add custom OpenCode models to the desktop picker once upstream stops
        # filtering model_catalog_json entries: https://github.com/openai/codex/issues/19694
        home = {
          packages = [ pkgs.codex ];
          file.".codex/ds4-flash-free.config.toml".text = ''
            model = "deepseek-v4-flash-free"
            model_provider = "opencode"
            model_reasoning_effort = "minimal"
          '';
        };

        programs.codexDesktopLinux = {
          enable = true;
          package = singletonCodexDesktop;
          cliPackage = pkgs.codex;
          remoteControl = {
            enable = true;
            codexHome = "${config.xdg.configHome}/codex";
          };
        };

        programs.codex = {
          enable = true;
          skills = { };
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
      };
  };
}
