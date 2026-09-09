{ den, lib, ... }:
{
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

      services.pipewire.alsa.enable = lib.mkDefault true;
    };

    homeManager = { ... }: {
      programs.cliamp = {
        enable = true;
        settings = {
          theme = "";
          repeat = "Off";
          shuffle = true;
          provider = "spotify";
          spotify = {
            client_id = "e79bc2a7d7f44a9e9153c0a5121ee0ce";
            bitrate = 320;
          };
        };
        systemd.enable = true;
      };

      systemd.user.services.cliamp.Unit = {
        Wants = [ "network-online.target" ];
        After = [ "network-online.target" ];
      };
    };
  };
}
