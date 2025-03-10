{ pkgs, ... }:
let
  git-autocommit =
    with pkgs;
    writeShellApplication {
      name = "git-autocommit";
      runtimeInputs = [ git ];
      text = ''
        DIR=''${1:-/home/repparw/nix}
        git -C "$DIR" add -A
        git -C "$DIR" commit -m "Autocommit"
        git -C "$DIR" pull --rebase
        git -C "$DIR" push
      '';
    };
in
{
  imports = [
    ../../modules/hm/gaming.nix
    ../../modules/hm/gui/obs.nix
  ];

  services.spotifyd.enable = true;

  services.jellyfin-mpv-shim.enable = true;

  home.packages = with pkgs; [
  ];

  systemd.user.services.git-autocommit = {
    Service = {
      Type = "oneshot";
      ExecStart = [ "${git-autocommit}/bin/git-autocommit" ];
    };

  };

  systemd.user.timers.git-autocommit = {
    Install = {
      WantedBy = [ "timers.target" ];
    };
    Timer = {
      OnCalendar = "*:0/4";
      Persistent = true;
    };
  };

}
