{pkgs, ...}: {
  services.kanshi.enable = true;

  # Let Home Manager install and manage itself.

  home.packages = with pkgs; [
    brightnessctl # backlight
  ];
}
