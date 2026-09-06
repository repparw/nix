{
  den,
  ...
}:
let
  # TODO: Remove this patch and use pkgs.tasks-org once
  # https://github.com/NixOS/nixpkgs/pull/518221 lands in our pin.
  # Fetch the single upstream package expression in the evaluator. Patching a
  # whole x86 nixpkgs tree made mixed-architecture deploy evaluation attempt an
  # x86 import-from-derivation on the aarch64 controller.
  tasksOrgPackage = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/4f9c47a6966e40144bcff663b19d8907448da1e3/pkgs/by-name/ta/tasks-org/package.nix";
    sha256 = "sha256-vjz+y0o/PrD9LteEgl7fizaPgAV5lcvAs5CJdf0l5wA=";
  };
in
{
  flake-file.inputs.nixcord = {
    url = "github:FlameFlag/nixcord";
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
        pkgs,
        ...
      }:
      {
        home.packages = with pkgs; [
          scrcpy
          godot
          tasks-org
          tradingview
          zapzap
        ];

        gtk.enable = true;

        xdg.mimeApps.enable = true;

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
