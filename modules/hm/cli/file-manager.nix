{pkgs, ...}: {
  programs = {
    yazi = {
      enable = true;
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
