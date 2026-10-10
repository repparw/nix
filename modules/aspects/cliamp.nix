{ den, lib, ... }:
let
  # Temporary until nix-community/home-manager#9842 merges and HM input bumps past it
  hmCliampModule = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/rachitvrma/home-manager/d1faef32f5e6ab3cb34ada5e030cbceb52307775/modules/programs/cliamp.nix";
    sha256 = "sha256-gtDq3a/wH7LQTGb5NuFTVQyrHURyaDv8+57MGYoRT6w=";
  };
in
{
  den.aspects.cliamp = {
    nixos = { ... }: {
      nixpkgs.overlays = [
        (final: prev: {
          # Temporary until bjarneo/cliamp#453 merges and nixpkgs bumps past it
          cliamp = prev.cliamp.overrideAttrs (old: {
            version = "2.0.1-session-attach-55ecd36";
            src = final.fetchFromGitHub {
              owner = "ryanrpj";
              repo = "cliamp";
              rev = "55ecd36798bca8dd51a942d85503f91e37ab96f7";
              hash = "sha256-87nEQ3Ay0u4stGoc3ShPX+z0zVhaTUCuQo72oZTVNT4=";
            };
            vendorHash = "sha256-cKMGAVLRs6FwX9Gqq6wj11OPwK1TsTuVMR7uwI6Mwfg=";
          });
        })
      ];

      services.pipewire.alsa.enable = lib.mkDefault true;

      home-manager.sharedModules = [ hmCliampModule ];
    };

    homeManager =
      { config, pkgs, ... }:
      {
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

        systemd.user.services.cliamp = {
          Unit = {
            Wants = [ "network-online.target" ];
            After = [ "network-online.target" ];
          };

          # The daemon skips stale-socket cleanup whenever the PID file names
          # a live process, and PIDs get reused across boots, so a PID file
          # left behind in the persisted config dir can stop the daemon from
          # binding its IPC socket at all. Clearing both files at unit start
          # is idempotent, and systemd already guarantees a single instance.
          Service.ExecStartPre = "-${lib.getExe' pkgs.coreutils "rm"} ${
            lib.escapeShellArgs [
              "-f"
              "${config.xdg.configHome}/cliamp/cliamp.sock"
              "${config.xdg.configHome}/cliamp/cliamp.sock.pid"
            ]
          }";
        };
      };
  };
}
