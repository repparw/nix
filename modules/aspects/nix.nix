_: {
  den.aspects.nix = {
    nixos = { config, ... }: {
      nix = {
        settings = {
          extra-substituters = [
            "https://cachix.cachix.org"
            "https://devenv.cachix.org"
            "https://helium-nix.cachix.org"
            "https://nix-community.cachix.org"
          ];
          extra-trusted-public-keys = [
            "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw="
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
