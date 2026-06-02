{
  lib,
  ...
}:
{
  den.aspects.timers = {
    nixos =
      { pkgs, ... }:
      {
        systemd = {
          services.paperless-export = {
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe pkgs.podman} exec paperless document_exporter --delete --no-archive --no-thumbnail --no-progress-bar ../export";
            };
          };

          timers.paperless-export = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*-*-7,14,21,28 03:45:00";
              Persistent = true;
            };
          };
        };
      };
  };
}
