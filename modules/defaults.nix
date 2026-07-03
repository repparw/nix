{ den, lib, ... }:
{
  den = {
    schema.user.classes = lib.mkDefault [ "homeManager" ];

    aspects.host-common = {
      includes = [
        den.batteries.hostname
        den.aspects.auto-upgrade
        den.aspects.cli
        den.aspects.networking
        den.aspects.secrets
        den.aspects.style
      ];
    };

    default = {
      includes = with den.aspects; [
        nix-index
        nixvim
        nixpkgs
        nix
        system
      ];

      nixos.system.stateVersion = "26.05";
      homeManager.home.stateVersion = "26.05";
    };
  };
}
