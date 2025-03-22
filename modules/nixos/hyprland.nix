{pkgs, ...}: {
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  environment.systemPackages = with pkgs; [
    nautilus
  ];

  services.greetd = {
    enable = true;
    vt = 1;
    settings = rec {
      initial_session = {
        command = "${pkgs.uwsm}/bin/uwsm start hyprland";
        user = "repparw";
      };
      default_session = initial_session;
    };
  };
}
