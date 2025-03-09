{ ... }:

{
  imports = [
    ../../modules/hm/cli
    ../../modules/hm/gui
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  services.udiskie.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.stateVersion = "23.11";
}
