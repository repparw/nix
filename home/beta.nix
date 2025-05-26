{ pkgs, ... }:
{
  modules.kanshi.enable = true;

  home.packages = with pkgs; [
    brightnessctl
  ]; # TODO fix brightness shortcuts / backlight
}
