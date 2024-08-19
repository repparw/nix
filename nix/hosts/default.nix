{ hostName, ... }:

{
  imports = [
    ../modules/nixos/cachix.nix
    ../modules/nixos/common.nix
    ../modules/nixos/hyprland.nix
    ./${hostName}
  ];

  programs.nh = {
    enable = true;
    flake = "/home/repparw/.dotfiles/nix";
    clean = {
      enable = true;
      extraArgs = "--keep 3 -keep-since 7d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  nix.optimise.automatic = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

}
