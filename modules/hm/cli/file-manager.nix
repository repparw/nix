{pkgs, ...}: let
  plugins-repo = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "a1738e8";
    hash = "sha256-eiLkIWviGzG9R0XP1Cik3Bg0s6lgk3nibN6bZvo8e9o=";
  };
in {
  programs = {
    yazi = {
      enable = true;
      plugins = {
        smart-enter = "${plugins-repo}/smart-enter.yazi";
        jump-to-char = "${plugins-repo}/jump-to-char.yazi";
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
        manager.prepend_keymap = [
          {
            on = ["l"];
            run = "plugin smart-enter";
            desc = "Enter the child directory, or open the file";
          }
          {
            on = ["f"];
            run = "plugin jump-to-char";
            desc = "Jump to char";
          }
          {
            on = ["<C-p>"];
            run = "plugin zoxide";
            desc = "Jump to a directory via zoxide";
          }
          {
            on = ["!"];
            run = "shell '$SHELL' --block";
            desc = "Open shell";
          }
        ];
      };
    };
  };
}
