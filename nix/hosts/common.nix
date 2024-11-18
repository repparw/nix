{ inputs, ... }:

{
  imports = [
    ../modules/nixos/common.nix
    ../modules/nixos/hyprland.nix
  ];

  services.gvfs.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/repparw/.dotfiles/nix";
    clean = {
      enable = true;
      extraArgs = "--keep 3 --keep-since 7d";
    };
  };

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  nix.settings = {
    access-tokens = "github.com=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";
    trusted-users = [
      "root"
      "repparw"
    ];

    substituters = [
      "nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

  };

  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  hardware.keyboard.qmk.enable = true;

}
