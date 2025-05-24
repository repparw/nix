{
  lib,
  config,
  ...
}: {
  config = lib.mkIf config.modules.gui.enable {
    services.spotifyd = {
      settings = {
        global = {
          username = "2ksy00sfypgevoabx2128ia4g";
          use_mpris = true;

          dbus_type = "session";
          backend = "pulseaudio";
          audio_format = "S16";

          device_name = "spotifyd";

          bitrate = 320;

          cache_path = "/home/repparw/.cache/spotifyd";

          max_cache_size = 5000000000;

          initial_volume = 45;

          volume_normalisation = false;

          normalisation_pregain = 3;

          autoplay = true;

          zeroconf_port = 1234;

          device_type = "speaker";
        };
      };
    };
  };
}
