{
  den,
  lib,
  ...
}:
{
  # Persistent Sendspin client for the Music Assistant server on the Pi.
  # The daemon is a headless player: it registers with MA's Sendspin server,
  # outputs through the desktop's PipeWire setup, and exposes an MPRIS
  # interface (playerctl / media keys work out of the box). Playback lives
  # in the MA server, so closing any control frontend never interrupts it.
  den.aspects.sendspin-client = {
    nixos =
      { lib, ... }:
      {
        services.pipewire.alsa.enable = lib.mkDefault true;
      };

    homeManager =
      { config, pkgs, ... }:
      {
        home.packages = [ pkgs.python314Packages.sendspin ];

        systemd.user.services.sendspin-client = {
          Unit = {
            Description = "Sendspin client for the Music Assistant server";
            Wants = [ "network-online.target" ];
            After = [
              "network-online.target"
              "pipewire.service"
            ];
          };

          Service = {
            ExecStart =
              let
                # The Pi's address mirrors modules/hosts/entities.nix; the
                # /sendspin path is fixed by the Sendspin protocol.
                serverUrl = "ws://192.168.0.4:8927/sendspin";
              in
              lib.getExe pkgs.python314Packages.sendspin + " daemon --url ${serverUrl} --name \"Alpha Desktop\"";
            Restart = "on-failure";
            RestartSec = 5;
          };

          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}
