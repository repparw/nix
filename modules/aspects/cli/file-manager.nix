{
  den,
  pkgs,
  ...
}:
{
  den.aspects.file-manager = {
    includes = [ ];

    homeManager =
      { pkgs, ... }:
      {
        programs = {
          yazi = {
            enable = true;
            shellWrapperName = "y";
            plugins = {
              smart-enter = pkgs.yaziPlugins.smart-enter;
              jump-to-char = pkgs.yaziPlugins.jump-to-char;
            };
            settings = {
              opener = {
                open = [
                  {
                    run = ''xdg-open "$1"'';
                    orphan = true;
                  }
                ];
              };
            };
            keymap = {
              mgr.prepend_keymap = [
                {
                  on = [ "l" ];
                  run = "plugin smart-enter";
                }
                {
                  on = [ "f" ];
                  run = "plugin jump-to-char";
                }
                {
                  on = [ "<C-p>" ];
                  run = "plugin fzf";
                }
                {
                  on = [ "!" ];
                  run = "shell '$SHELL' --block";
                }
                {
                  on = [
                    "z"
                    "m"
                  ];
                  run = "sort mtime --reverse=no linemode mtime";
                }
                {
                  on = [
                    "z"
                    "M"
                  ];
                  run = "sort mtime --reverse linemode mtime";
                }
                {
                  on = [
                    "z"
                    "b"
                  ];
                  run = "sort btime --reverse=no linemode btime";
                }
                {
                  on = [
                    "z"
                    "B"
                  ];
                  run = "sort btime --reverse linemode btime";
                }
                {
                  on = [
                    "z"
                    "e"
                  ];
                  run = "sort extension --reverse=no";
                }
                {
                  on = [
                    "z"
                    "E"
                  ];
                  run = "sort extension --reverse";
                }
                {
                  on = [
                    "z"
                    "a"
                  ];
                  run = "sort alphabetical --reverse=no";
                }
                {
                  on = [
                    "z"
                    "A"
                  ];
                  run = "sort alphabetical --reverse";
                }
                {
                  on = [
                    "z"
                    "n"
                  ];
                  run = "sort natural --reverse=no";
                }
                {
                  on = [
                    "z"
                    "N"
                  ];
                  run = "sort natural --reverse";
                }
                {
                  on = [
                    "z"
                    "s"
                  ];
                  run = "sort size --reverse=no linemode size";
                }
                {
                  on = [
                    "z"
                    "S"
                  ];
                  run = "sort size --reverse linemode size";
                }
                {
                  on = [
                    "z"
                    "r"
                  ];
                  run = "sort random --reverse=no";
                }
              ];
            };
          };
        };
      };
  };
}
