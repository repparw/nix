_: {
  imports = [
    ./cli
    ./gui
  ];
  modules.gui.enable = true;

  programs.home-manager.enable = true;

  services.udiskie.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  home = {
    username = "repparw";
    homeDirectory = "/home/repparw";

    stateVersion = "23.11";
  };
}
