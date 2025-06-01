{ pkgs, ... }:
{
  modules = {
    gui.enable = true;
    kanshi.enable = true;
  };

  home.packages = with pkgs; [
    brightnessctl
  ]; # TODO fix brightness shortcuts / backlight
}
