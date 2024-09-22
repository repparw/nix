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

  nix.trustedUsers = [
    "root"
    "repparw"
  ];

  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  hardware.xpadneo.enable = true;

}
