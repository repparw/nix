{
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.gui.enable {
    services.spotifyd = {
      settings = {
        global = {
          username = "2ksy00sfypgevoabx2128ia4g";
          use_mpris = true;

          dbus_type = "session";
          backend = "pulseaudio";
          audio_format = "S24";

          device_name = "daemon";

          bitrate = 320;

          cache_path = "/home/repparw/.cache/spotifyd";

          max_cache_size = 5000000000;

          initial_volume = 45;

          volume_normalisation = false;

          device_type = "speaker";
        };
      };
    };
  };
}
