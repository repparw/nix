{ pkgs, ... }:
{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    modes = [
      "drun"
      "run"
      "window"
      "combi"
      # {
      #   name = "whatnot";
      #   path = lib.getExe pkgs.rofi-whatnot;
      # }
    ];
    extraConfig = {
      combi-modes = "drun,window";
      show-icons = true;
      hover-select = true;
      bw = 0;
      display-combi = "";
      terminal = "kitty";
      drun-display-format = "{name}";
      me-select-entry = "";
      me-accept-entry = "MousePrimary";
      kb-cancel = "Escape,MouseMiddle";
    };
  };
}
