{ hostName, pkgs, ... }:

{
  imports = [
    ../modules/hm/cli.nix
    ../modules/hm/gui.nix
    ../modules/hm/hypr/hyprland.nix
    ./${hostName}/home.nix
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.packages = with pkgs; [
    # Essential packages
    jellyfin-mpv-shim
  ];

  home.stateVersion = "23.11";
}
