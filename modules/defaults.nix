{ den, ... }:
{
  den.ctx.user.includes = [ den._."mutual-provider" ];

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
