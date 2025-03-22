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
}
