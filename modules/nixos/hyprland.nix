{pkgs, ...}: {
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  environment.systemPackages = with pkgs; [
    nautilus
  ];

  services.displayManager = {
    defaultSession = "hyprland-uwsm";
    autoLogin = {
      enable = true;
      user = "repparw";
    };
    sddm = {
      enable = true;
      wayland.enable = true;
    };
  };

  #services.greetd = {
  #  enable = true;
  #  vt = 1;
  #  settings = let
  #    session = {
  #      command = "${pkgs.uwsm}/bin/uwsm start hyprland";
  #      user = "repparw";
  #    };
  #  in {
  #    initial_session = session;
  #    default_session = session;
  #  };
  #};
}
