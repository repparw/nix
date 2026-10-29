{
  den,
  ...
}:
{
  flake-file.inputs.nixcord = {
    url = "github:FlameFlag/nixcord";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.gui.provides.guiApps = {
    nixos =
      { pkgs, ... }:
      {
        nixpkgs.overlays = [
          (final: _prev: {
            tasks-org = (import ../upstream/_overlays/tasks-org.nix) final;
          })
        ];

        programs = {
          gnome-disks.enable = true;
        };
        environment.systemPackages = [ pkgs.qalculate-gtk ];
      };

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        home.packages = with pkgs; [
          godot
          tasks-org
          tradingview
        ];

        gtk.enable = true;

        xdg.mimeApps.enable = true;
        xdg.terminal-exec = {
          enable = true;
          settings.default = [ "foot.desktop" ];
        };
        xdg.desktopEntries.foot = {
          name = "Foot";
          genericName = "Terminal";
          comment = "A wayland native terminal emulator";
          exec = lib.getExe config.programs.foot.package;
          icon = "foot";
          terminal = false;
          categories = [
            "System"
            "TerminalEmulator"
          ];
          settings = {
            Keywords = "shell;prompt;command;commandline;";
            X-TerminalArgExec = "-e";
            X-TerminalArgAppId = "--app-id";
            X-TerminalArgHold = "--hold";
            X-TerminalArgTitle = "--title";
            X-TerminalArgDir = "--working-directory";
          };
        };

        programs = {
          foot = {
            enable = true;
            settings = {
              colors-dark.blur = true;
            };
          };

          imv = {
            enable = true;
            settings = {
              binds = {
                "<comma>" = "prev";
                "<period>" = "next";
              };
            };
          };

          nixcord = {
            enable = true;
            discord.enable = false;
            vesktop.enable = true;
          };

          element-desktop = {
            enable = true;
          };
        };

      };

  };
}
