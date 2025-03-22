{pkgs, ...}: {
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  environment.systemPackages = with pkgs; [
    nautilus
  ];

  services.displayManager.autoLogin = {
    enable = true;
    user = "repparw";
  };

  services.greetd = {
    enable = true;
    vt = 1;
    settings = let
      session = {
        command = "${pkgs.uwsm}/bin/uwsm start hyprland";
        user = "repparw";
      };
    in {
      initial_session = session;
      default_session = session;
    };
  };
}
