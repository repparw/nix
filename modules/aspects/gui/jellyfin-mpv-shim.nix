{
  den,
  lib,
  ...
}:
{
  den.aspects.jellyfin-mpv-shim = {
    includes = [ ];

    homeManager =
      { config, ... }:
      {
        services.jellyfin-mpv-shim = {
          enable = lib.mkDefault false;
          settings = {
            player_name = "alpha";
            screenshot_dir = "/home/repparw/Pictures/mpvss";
            check_updates = false;
            client_uuid = "c88bd496-04fd-441a-a9f7-e5dbb91dd72c";
            enable_osc = false;
          };

          mpvConfig = config.programs.mpv.config;

          mpvBindings = config.programs.mpv.bindings;
        };
      };
  };
}
