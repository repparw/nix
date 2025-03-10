{ pkgs, ... }:
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
      User = "repparw";
      Group = "users";
      ExecStart = [ "git-autocommit" ];
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
