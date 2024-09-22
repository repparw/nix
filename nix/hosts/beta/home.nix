{ pkgs, ... }:
{
  imports = [
    ../../modules/hm/kanshi.nix # Dynamic display
  ];

  # Let Home Manager install and manage itself.

  home.packages = with pkgs; [
    brightnessctl # backlight
  ];

}
