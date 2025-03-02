{ inputs, ... }:

{
  imports = [
    ../modules/nixos/common.nix
    ../modules/nixos/hyprland.nix
    ../modules/nixos/autoUpgrade.nix
  ];

  networking.networkmanager.enable = true;

  services.gvfs.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/repparw/.dotfiles/nix";
    clean = {
      enable = true;
      extraArgs = "--keep 3 --keep-since 7d";
    };
  };

  programs.localsend.enable = true;

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  age.secrets.github = {
    type = "age";
  };

  nix.settings = {
    access-tokens = config.age.secrets.github;
    trusted-users = [
      "root"
      "repparw"
    ];

    substituters = [
      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

  };

  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  hardware.keyboard.qmk.enable = true;

}
