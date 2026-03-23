{ den, lib, ... }:
{
  den.ctx.user.includes = [ den.provides."mutual-provider" ];

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  den.default = {
    includes = [
      den.aspects.nix-index
      den.aspects.nixvim
      den.aspects.nixpkgs
      den.aspects.nix
      den.aspects.system
    ];

    nixos.system.stateVersion = "25.11";
    homeManager.home.stateVersion = "25.11";
  };
}
