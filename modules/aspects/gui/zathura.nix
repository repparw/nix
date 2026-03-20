{
  den,
  ...
}:
{
  den.aspects.zathura = {
    includes = [ ];

    homeManager =
      { ... }:
      {
        programs.zathura = {
          enable = true;
          options = {
            recolor = true;
            guioptions = "none";
            sandbox = "none";
            selection-clipboard = "clipboard";
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
  };
}
