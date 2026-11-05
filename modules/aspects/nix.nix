_: {
  den.aspects.nix.nixos = {
    programs.nh.enable = true;

    # Nix's default build-dir is /tmp, which is a tmpfs on this fleet
    # (boot.tmp.useTmpfs). Build trees are then bounded by half of RAM
    # instead of disk, and their pages count against RAM: pi could not
    # extract t3code's vendor tree (No space left on device on a 3.9 GiB
    # tmpfs), and tmpfs pressure contributed to earlyoom killing a
    # torchaudio test build on epsilon. Keep build trees on the store
    # filesystem instead.
    systemd.tmpfiles.rules = [ "d /nix/tmp 0755 root root -" ];

    nix = {
      settings = {
        build-dir = "/nix/tmp";
        extra-substituters = [
          "https://cachix.cachix.org"
          "https://devenv.cachix.org"
          "https://helium-nix.cachix.org"
          "https://hermes-agent.cachix.org"
          "https://nix-community.cachix.org"
          "https://repparw.cachix.org"
        ];
        extra-trusted-public-keys = [
          "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw="
          "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "repparw.cachix.org-1:QMnZnrTTNgO9m8cewBLWaPK9bLyvSI2GrLpzOpbJVrw="
        ];
        use-xdg-base-directories = true;
        trusted-users = [ "root" ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        commit-lock-file-summary = "flake.lock: Update";
      };

      optimise.automatic = true;
    };
  };
}
