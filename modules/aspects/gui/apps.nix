{
  den,
  ...
}:
let
  tasksOrgPackage = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/68e19592a6d35b03cb050e499d051cff6f8c9539/pkgs/by-name/ta/tasks-org/package.nix";
    sha256 = "sha256-ROHXY5AJiH9B1iarpvCKinvIpAr4HuXXdIcjIwnHq1I=";
  };
in
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
            tasks-org = final.callPackage tasksOrgPackage { };
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
          zapzap
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
