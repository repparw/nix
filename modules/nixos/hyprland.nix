{ pkgs, ... }:

{

  programs.hyprland = {
    enable = true;
  };

  services.greetd = {
    enable = true;
    vt = 1;
    settings = rec {
      initial_session = {
        command = "${pkgs.hyprland}/bin/Hyprland";
        user = "repparw";
      };
      default_session = initial_session;
    };
  };

}
