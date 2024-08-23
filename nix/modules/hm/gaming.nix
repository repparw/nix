{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Gaming
    legendary-gl
    lutris
    mangohud
  ];
}
