_:
{
  den.aspects.nix = {
    nixos =
      _:
      {
        nix = {
          settings = {
            extra-substituters = [
              "https://cachix.cachix.org"
              "https://devenv.cachix.org"
            ];
            extra-trusted-public-keys = [
              "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
              "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            ];
            use-xdg-base-directories = true;
            trusted-users = [ "root" ];
            allowed-users = [ "repparw" ];
            experimental-features = "nix-command flakes";
            commit-lock-file-summary = "flake.lock: Update";
          };

          optimise.automatic = true;
        };
      };
  };
}
