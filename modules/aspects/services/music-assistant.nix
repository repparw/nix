{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.music-assistant = {
    service-registry = {
      name = "music-assistant";
      definition = {
        hostname = "music";
        port = 8095;
        # Music Assistant ships its own authentication; the edge must not
        # wrap it in authelia sessions or the frontend's websocket API
        # (which uses MA tokens) breaks.
        auth = "bypass";
        container = false;
        monitor = true;
        lanEdge = true;
      };
    };

    nixos =
      { config, lib, ... }:
      {
        services.music-assistant = {
          enable = true;
          # Covers the stream server port (8097) plus per-provider ports:
          # squeezelite (3483/9000/9090 for the future ESP32 endpoints) and
          # the ephemeral TCP range go-librespot needs for Spotify Connect
          # advertisement.
          openFirewall = true;
          providers = [
            "chromecast"
            "dlna"
            "airplay"
            "hass_players"
            "hass"
            "spotify"
            "spotify_connect"
            "sendspin"
            "sendspin_source"
            "squeezelite"
            "ytmusic"
          ];
        };

        # The web UI port itself is not covered by the module's openFirewall
        # (which only handles the stream server and provider ports).
        networking.firewall.interfaces.eth0.allowedTCPPorts = [ 8095 ];

        # Spotify's OAuth client id is a public identifier (PKCE flow, no
        # secret), but it is kept in sops to keep credentials out of the
        # tree per repo policy.
        sops.secrets.musicAssistantSpotifyClientId = {
          sopsFile = ../../../secrets/music-assistant.sops.yaml;
          key = "spotifyClientId";
          # The service runs as a DynamicUser; a world-readable mode is safe
          # for a public client id and keeps the unit definition simple.
          mode = "0444";
        };
        systemd.services.music-assistant.environment.MASS_APP_VAR_SPOTIFY_CLIENT_ID =
          config.sops.secrets.musicAssistantSpotifyClientId.path;

        # Native (non-container) service: an independent lifecycle from the
        # Home Assistant nspawn container, so restarting HA never interrupts
        # music playback.
        systemd.services.music-assistant = {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
        };
      };
  };
}
