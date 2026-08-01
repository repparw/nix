{
  den,
  inputs,
  lib,
  ...
}:
{
  # TODO: Replace the upstream package after the Nixpkgs update reaches the
  # currently used 0.14.1 and lands in our pin:
  # https://github.com/NixOS/nixpkgs/pull/546531
  flake-file.inputs.moonshine = {
    url = "github:hgaiser/moonshine";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.streaming.nixos =
    {
      config,
      pkgs,
      ...
    }:
    let
      user = "repparw";

      moonshine-boxart = pkgs.runCommand "moonshine-boxart" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
        mkdir -p $out
        rsvg-convert \
          --width 512 \
          --height 512 \
          ${pkgs.niri.src}/docs/wiki/logo/niri-icon.svg \
          > $out/desktop.png
        cp ${pkgs.steam-unwrapped}/share/icons/hicolor/256x256/apps/steam.png $out/steam.png
        rsvg-convert \
          --width 512 \
          --height 512 \
          ${pkgs.heroic}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg \
          > $out/heroic.png
      '';

      moonshine-desktop = pkgs.writeShellApplication {
        name = "moonshine-desktop";
        runtimeInputs = [ pkgs.niri ];
        text = ''
          # Run a nested, isolated Niri desktop on Moonshine's Wayland output.
          # Do not use --session: this is not the user's primary compositor.
          exec niri
        '';
      };

      moonshine-steam = pkgs.writeShellApplication {
        name = "moonshine-steam";
        runtimeInputs = [
          pkgs.bubblewrap
          pkgs.procps
          # Use the NixOS-configured wrapper so extraCompatPackages (GE-Proton)
          # is exported to Steam inside Moonshine's transient session too.
          config.programs.steam.package
        ];
        text = ''
          # Steam is single-instance per user. Stop the desktop instance so it
          # cannot steal Big Picture from Moonshine's private compositor.
          if pgrep -x steam >/dev/null; then
            steam -shutdown >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do
              pgrep -x steam >/dev/null || break
              sleep 1
            done
          fi

          # Moonshine's upstream health check assumes /usr/share. On NixOS the
          # implicit Vulkan layer lives in the package output, so make it
          # discoverable to Steam, Proton, and their Vulkan loaders.
          export XDG_DATA_DIRS="${config.services.moonshine.package}/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

          # Keep Steam from probing these automount paths and waking the disks.
          exec bwrap \
            --dev-bind / / \
            --tmpfs /mnt/seagate \
            --tmpfs /home/containers/media/seagate \
            -- steam steam://open/bigpicture
        '';
      };

      moonshine-heroic = pkgs.writeShellApplication {
        name = "moonshine-heroic";
        runtimeInputs = [ pkgs.heroic ];
        text = ''
          exec heroic --console
        '';
      };
    in
    {
      # TODO: Drop this flake import and use the Nixpkgs module once the draft
      # PR lands in our pin: https://github.com/NixOS/nixpkgs/pull/544393
      imports = [ inputs.moonshine.nixosModules.default ];

      options.modules.streaming.shellApplications = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = { };
        description = "Shell applications generated for the streaming service.";
      };

      config = {
        modules.streaming.shellApplications = {
          inherit moonshine-desktop moonshine-steam moonshine-heroic;
        };

        services.moonshine = {
          enable = true;
          inherit user;
          uid = 1000;
          openFirewall = true;

          settings = {
            name = config.networking.hostName;
            application = [
              {
                title = "Desktop";
                boxart = "${moonshine-boxart}/desktop.png";
                command = [ "${moonshine-desktop}/bin/moonshine-desktop" ];
                stdout = "journal";
                stderr = "journal";
              }
              {
                title = "Steam Big Picture";
                boxart = "${moonshine-boxart}/steam.png";
                command = [ "${moonshine-steam}/bin/moonshine-steam" ];
                stdout = "journal";
                stderr = "journal";
              }
              {
                title = "Heroic Games Launcher";
                boxart = "${moonshine-boxart}/heroic.png";
                command = [ "${moonshine-heroic}/bin/moonshine-heroic" ];
                stdout = "journal";
                stderr = "journal";
              }
            ];
          };
        };

        # Required by Moonshine's sleep-inhibitor polkit rule.
        users.groups.moonshine.members = [ user ];
      };
    };
}
