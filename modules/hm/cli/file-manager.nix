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
      enableZshIntegration = true;
      theme = {
        flavor = {
          use = "gruvbox-dark";
        };
      };
      flavors = {
        gruvbox-dark = fetchTarball {
          url = "https://github.com/bennyyip/gruvbox-dark.yazi/archive/refs/heads/main.zip";
          sha256 = "0yyw1wsljl1vr2cdd5y9fjd3vwnf2h31y5jnjc4j0dq88gbjh5rl";
        };
      };
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
        ];
      };
    };
    zsh.initContent = ''
      function launch-yazi() {
        if [ "$1" != "" ]; then
      	if [ -d "$1" ]; then
      	  yazi "$1"
      	else
      	  yazi "$(zoxide query $1)"
      	fi
        else
      	yazi
        fi
        zle reset-prompt
        return $?
      }

      # Create the widget from the function
      zle -N launch-yazi

      # Bind the widget after vi-mode initialization
      zvm_after_init_commands+=('bindkey "^e" launch-yazi')

      alias y='launch-yazi'
    '';
  };
}
