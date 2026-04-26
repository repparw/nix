{ den, lib, ... }:
{
  den = {
    ctx.user.includes = [ den.provides."mutual-provider" ];

    schema.user.classes = lib.mkDefault [ "homeManager" ];

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
