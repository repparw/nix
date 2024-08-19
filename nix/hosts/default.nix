{ hostName, ... }:

{
  imports = [
    ../../modules/nixos/cachix.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/hyprland.nix
    ./${hostName}
  ];

  nixpkgs.config.allowUnfree = true;

  nix.optimise.automatic = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

}
