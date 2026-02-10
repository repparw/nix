{
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.gui.enable {
    programs.zathura = {
      enable = true;
      options = {
        render-loading = "true";

        recolor = "true";
        # set recolor-keephue             true      # keep original color

        guioptions = "";

        sandbox = "none";
        statusbar-h-padding = 0;
        statusbar-v-padding = 0;
        page-padding = 1;
        selection-clipboard = "primary";
      };
      mappings = {
        u = "scroll half-up";
        d = "scroll half-down";
        D = "toggle_page_mode";
        r = "reload";
        R = "rotate";
        K = "zoom in";
        J = "zoom out";
        i = "recolor";
      };
    };
  };
}
