{pkgs, ...}: {
  modules.kanshi.enable = true;

  home.packages = with pkgs; [
    brightnessctl # backlight
  ];
}
