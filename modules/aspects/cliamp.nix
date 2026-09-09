{ den, lib, ... }:
let
  # programs.cliamp from nix-community/home-manager#9842 (rachitvrma,
  # branch module/cliamp @ d1faef3, still open as of 2026-09-09).
  # Single-file fetch in the style of gui/apps.nix's tasks-org pin: pure,
  # arch-independent, no extra flake input. Drop the fetchurl and the
  # sharedModules line once the module reaches our home-manager pin; keep
  # the overlay until nixpkgs ships a cliamp containing attach/quit.
  hmCliampModule = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/rachitvrma/home-manager/d1faef32f5e6ab3cb34ada5e030cbceb52307775/modules/programs/cliamp.nix";
    sha256 = "sha256-gtDq3a/wH7LQTGb5NuFTVQyrHURyaDv8+57MGYoRT6w=";
  };
in
{
  # Trial of cliamp as a spotify-player/spotifyd alternative: detached
  # session (--daemon) plus `cliamp attach` for the full TUI, built from
  # bjarneo/cliamp#453 (ryanrpj feat/session-attach) and configured
  # through the upstream home-manager module above. Spotify auth stays
  # interactive (`cliamp attach`, select Spotify, browser sign-in, Premium
  # required); credentials land in ~/.config/cliamp/spotify_credentials.json
  # and are deliberately not managed here.
  den.aspects.cliamp = {
    nixos = { ... }: {
      nixpkgs.overlays = [
        (final: prev: {
          cliamp = prev.cliamp.overrideAttrs (old: {
            version = "2.0.1-session-attach-b9aa7d9";
            src = final.fetchFromGitHub {
              owner = "ryanrpj";
              repo = "cliamp";
              rev = "b9aa7d94a9eb3f8c9439708f531ac6df756bdbff";
              hash = "sha256-C1WQQi7Bif3SsZwkDx+EVdOkE5OygXJG7q/rUiBtKBo=";
            };
            vendorHash = "sha256-d/ENFm9b1DkIir1lz50VVX1pvuQpwPUVlA5XOC7Jj5o=";
          });
        })
      ];

      # cliamp plays through its ALSA backend, which needs the PipeWire
      # ALSA bridge on a PipeWire host (same as upstream troubleshooting).
      services.pipewire.alsa.enable = lib.mkDefault true;

      home-manager.sharedModules = [ hmCliampModule ];
    };

    homeManager = { ... }: {
      programs.cliamp = {
        enable = true;
        # package defaults to pkgs.cliamp, i.e. the overlay build above.
        settings = {
          # Mirrors the previously hand-maintained ~/.config/cliamp/config.toml
          # (backed up to *.hm-backup on first switch) so the managed file
          # doesn't clobber working values. client_id is a public app
          # identifier, not a secret — same precedent as spotifyd's username.
          theme = "";
          repeat = "Off";
          shuffle = true;
          # Start every session on Spotify: a restart otherwise forgets
          # the last provider and lands back on radio (upstream behavior).
          provider = "spotify";
          spotify = {
            client_id = "e79bc2a7d7f44a9e9153c0a5121ee0ce";
            bitrate = 320;
          };
        };
        systemd.enable = true;
      };

      # Spotify + streams need real network; the module's unit doesn't
      # order after it (mirrors the old spotifyd After=network-online).
      systemd.user.services.cliamp.Unit = {
        Wants = [ "network-online.target" ];
        After = [ "network-online.target" ];
      };
    };
  };
}
