{ config, pkgs, ... }:
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
      display-drun = "";
      display-window = "";
      terminal = "kitty";
      drun-display-format = "{name}";
      me-select-entry = "";
      me-accept-entry = "MousePrimary";
      kb-cancel = "Escape,MouseMiddle";
    };
    theme =
      let
        # Use `mkLiteral` for string-like values that should show without
        # quotes, e.g.:
        # {
        #   foo = "abc"; => foo: "abc";
        #   bar = mkLiteral "abc"; => bar: abc;
        # };
        inherit (config.lib.formats.rasi) mkLiteral;
      in
      {
        "*" = {
          margin = mkLiteral "0px";
          padding = mkLiteral "0px";
          spacing = mkLiteral "0px";
        };

        "window" = {
          location = mkLiteral "north";
          y-offset = mkLiteral "calc(50% - 176px)";
          width = mkLiteral "480px";
          border-radius = mkLiteral "24px";
        };

        "mainbox" = {
          padding = mkLiteral "12px";
        };

        "inputbar" = {
          border = mkLiteral "2px";
          border-radius = mkLiteral "16px";
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "8px";
          children = map mkLiteral [
            "prompt"
            "entry"
          ];
        };

        "entry" = {
          placeholder = "Search";
        };

        "message" = {
          margin = mkLiteral "12px 0 0";
          border-radius = mkLiteral "16px";
        };

        "textbox" = {
          padding = mkLiteral "8px 24px";
        };

        "listview" = {
          margin = mkLiteral "12px 0 0";
          lines = mkLiteral "8";
          columns = mkLiteral "1";
          fixed-height = mkLiteral "false";
        };

        "element" = {
          border-radius = mkLiteral "16px";
        };

        "element-icon" = {
          size = mkLiteral "1em";
          vertical-align = mkLiteral "0.5";
        };
      };
  };
}
