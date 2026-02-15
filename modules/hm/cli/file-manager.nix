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
            desc = "Enter the child directory, or open the file";
          }
          {
            on = [ "f" ];
            run = "plugin jump-to-char";
            desc = "Jump to char";
          }
          {
            on = [ "<C-p>" ];
            run = "plugin fzf";
            desc = "Navigate with fzf";
          }
          {
            on = [ "!" ];
            run = "shell '$SHELL' --block";
            desc = "Open shell";
          }
          {
            on = [
              "z"
              "m"
            ];
            run = "sort mtime --reverse=no linemode mtime";
            desc = "Sort by modified time";
          }
          {
            on = [
              "z"
              "M"
            ];
            run = "sort mtime --reverse linemode mtime";
            desc = "Sort by modified time (reverse)";
          }
          {
            on = [
              "z"
              "b"
            ];
            run = "sort btime --reverse=no linemode btime";
            desc = "Sort by birth time";
          }
          {
            on = [
              "z"
              "B"
            ];
            run = "sort btime --reverse linemode btime";
            desc = "Sort by birth time (reverse)";
          }
          {
            on = [
              "z"
              "e"
            ];
            run = "sort extension --reverse=no";
            desc = "Sort by extension";
          }
          {
            on = [
              "z"
              "E"
            ];
            run = "sort extension --reverse";
            desc = "Sort by extension (reverse)";
          }
          {
            on = [
              "z"
              "a"
            ];
            run = "sort alphabetical --reverse=no";
            desc = "Sort alphabetically";
          }
          {
            on = [
              "z"
              "A"
            ];
            run = "sort alphabetical --reverse";
            desc = "Sort alphabetically (reverse)";
          }
          {
            on = [
              "z"
              "n"
            ];
            run = "sort natural --reverse=no";
            desc = "Sort naturally";
          }
          {
            on = [
              "z"
              "N"
            ];
            run = "sort natural --reverse";
            desc = "Sort naturally (reverse)";
          }
          {
            on = [
              "z"
              "s"
            ];
            run = "sort size --reverse=no linemode size";
            desc = "Sort by size";
          }
          {
            on = [
              "z"
              "S"
            ];
            run = "sort size --reverse linemode size";
            desc = "Sort by size (reverse)";
          }
          {
            on = [
              "z"
              "r"
            ];
            run = "sort random --reverse=no";
            desc = "Sort randomly";
          }
        ];
      };
    };
  };
}
