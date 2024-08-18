{ hostName, ... }:

{
  imports = [ ./${hostName} ];

  nixpkgs.config.allowUnfree = true;

  nix.optimise.automatic = true;

}
