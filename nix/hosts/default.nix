{ hostName, ... }:

{
  imports = [
    ../modules/nixos/cachix.nix
    ../modules/nixos/common.nix
    ../modules/nixos/hyprland.nix
    ./${hostName}
  ];

  services.udisks2.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/repparw/.dotfiles/nix";
    clean = {
      enable = true;
      extraArgs = "--keep 3 -keep-since 7d";
    };
  };

  nix.settings = {
    access-tokens = "github.com=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";
    trusted-users = [
      "root"
      "repparw"
    ];
  };

  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  hardware.xpadneo.enable = true;

}
