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
          (final: prev: {
            wshowkeys = prev.wshowkeys.overrideAttrs (old: {
              src = prev.fetchFromGitHub {
                owner = "repparw";
                repo = "wshowkeys";
                rev = "52d1191cc250d3a24b83f77ce23f23d498c23bb3";
                hash = "sha256-BkmB+/oG0tsAbvAjkoEAJxObjvg+mCENhM4EHDDXQAI=";
              };
            });
          })
        ];

        programs = {
          gnome-disks.enable = true;
          wshowkeys.enable = true;
        };
        environment.systemPackages = [ pkgs.qalculate-gtk ];
        networking.firewall.interfaces.eth0 = {
          # rquickshare
          allowedTCPPorts = [
            32100
          ];
          allowedTCPPortRanges = [
            {
              from = 1714;
              to = 1764;
            }
          ];
          allowedUDPPorts = [
            5353 # mDNS
            32100
          ];
          allowedUDPPortRanges = [
            {
              from = 1714;
              to = 1764;
            }
          ];
        };
      };

    homeManager =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        kdeconnect = pkgs.kdePackages.kdeconnect-kde;
        sendClipboard = pkgs.writeShellScriptBin "kdeconnect-send-clipboard" ''
          set -eu

          device="$(${kdeconnect}/bin/kdeconnect-cli --list-available --id-only | head -n1)"
          if [ -z "$device" ]; then
            ${lib.getExe' pkgs.libnotify "notify-send"} \
              --urgency=critical \
              "KDE Connect" \
              "No paired Android device is available"
            exit 1
          fi

          exec ${kdeconnect}/bin/kdeconnect-cli \
            --device "$device" \
            --send-clipboard
        '';
      in
      {
        home.packages = with pkgs; [
          pwvucontrol
          scrcpy
          godot
          rquickshare
          kdeconnect
          sendClipboard
          tasks-org
          zapzap
        ];

        systemd.user.services.kdeconnect = {
          Unit = {
            Description = "KDE Connect daemon";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${kdeconnect}/bin/kdeconnectd --replace";
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

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

        xdg.dataFile."dev.mandre.rquickshare/.settings.json" = {
          text = builtins.toJSON {
            realclose = false;
            autostart = true;
            startminimized = true;
            download_path = config.xdg.userDirs.download;
            port = 32100;
          };
          force = true;
        };
      };

  };
}
