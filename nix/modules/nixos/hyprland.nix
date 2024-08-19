{ pkgs, unstable, ... }:

{

  programs.hyprland = {
    enable = true;
    package = unstable.hyprland;
  };

  environment.systemPackages = [
    pkgs.kdePackages.polkit-kde-agent-1 # launch?
  ];

  services.greetd = {
    enable = true;
    vt = 1;
    settings = rec {
      initial_session = {
        command = "${unstable.hyprland}/bin/Hyprland";
        user = "repparw";
      };
      default_session = initial_session;
    };
  };

}
