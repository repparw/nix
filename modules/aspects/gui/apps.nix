{
  den,
  inputs,
  ...
}:
let
  # TODO: Remove this patch and use pkgs.tasks-org once
  # https://github.com/NixOS/nixpkgs/pull/518221 lands in our pin.
  tasksOrgNixpkgs =
    pkgs:
    pkgs.applyPatches {
      name = "nixpkgs-tasks-org-patched";
      src = inputs.nixpkgs;
      patches = [
        (pkgs.fetchpatch {
          url = "https://github.com/NixOS/nixpkgs/pull/518221.diff";
          hash = "sha256-QURHYohiLherL4P4qp9WbZQ34EiilCEsxR+qQMNiGU8=";
        })
      ];
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
          (final: prev: {
            tasks-org =
              (final.callPackage (tasksOrgNixpkgs final + "/pkgs/by-name/ta/tasks-org/package.nix") { })
              .overrideAttrs
                (_: {
                  postFixup = ''
                    wrapProgram $out/bin/tasks-org \
                      --prefix LD_LIBRARY_PATH : "$out/lib/runtime/lib:$out/lib/runtime/lib/server:${
                        final.lib.makeLibraryPath [ final.dbus ]
                      }"
                  '';
                });
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
