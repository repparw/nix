_: {
  den.aspects.nix = {
    nixos =
      { config, pkgs, ... }:
      let
        # The store copy of sudo is intentionally not setuid; NixOS exposes
        # the privileged wrapper separately, so prepend /run/wrappers/bin to
        # let nh find the setuid sudo.
        nhWithSudoWrapper = pkgs.writeShellApplication {
          name = "nh";
          runtimeInputs = [ pkgs.nh ];
          text = ''
            export PATH="/run/wrappers/bin:$PATH"
            exec ${pkgs.nh}/bin/nh "$@"
          '';
        };
      in
      {
        programs.nh = {
          enable = true;
          package = nhWithSudoWrapper;
          flake = "${config.home-manager.users.repparw.xdg.userDirs.projects}/nix";
          clean = {
            enable = true;
            extraArgs = "--keep 3 --keep-since 7d --keep-one";
          };
        };

        sops.secrets.accessTokens = {
          sopsFile = ../../secrets/nix.sops.yaml;
          mode = "0440";
          owner = config.users.users.repparw.name;
        };

        nix = {
          settings = {
            extra-substituters = [
              "https://cachix.cachix.org"
              "https://devenv.cachix.org"
              "https://helium-nix.cachix.org"
              "https://hermes-agent.cachix.org"
              "https://nix-community.cachix.org"
            ];
            extra-trusted-public-keys = [
              "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
              "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
              "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw="
              "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
            use-xdg-base-directories = true;
            trusted-users = [ "root" ];
            allowed-users = [ config.users.users.repparw.name ];
            experimental-features = "nix-command flakes";
            commit-lock-file-summary = "flake.lock: Update";
          };

          extraOptions = ''
            !include ${config.sops.secrets.accessTokens.path}
          '';

          optimise.automatic = true;
        };
      };
  };
}
