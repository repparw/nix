{ pkgs, unstable, ... }:
{
  imports = [
    ../../modules/hm/cli.nix
    ../../modules/hm/nix.nix
    ../../modules/hm/gui.nix
    ../../modules/hm/hypr/hyprland.nix
    ../../modules/hm/kanshi.nix # Dynamic display
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.packages =
    with pkgs;
    [
      brightnessctl # backlight
    ]
    ++ [ unstable.obsidian ];

  home.stateVersion = "23.11";

}
