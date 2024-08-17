{ ... }:
{
  services.spotifyd = {
    enable = true;
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

        # NOTE: This variable's type will change in v0.4, to a number (instead of string)
        initial_volume = "45";

        volume_normalisation = true;

        normalisation_pregain = 3;

        autoplay = true;

        zeroconf_port = 1234;

        device_type = "speaker";
      };
    };
  };
}
