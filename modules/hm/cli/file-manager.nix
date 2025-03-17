{ pkgs, ... }:
let
  plugins-repo = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "38418dd";
    hash = "sha256-cdPeIhtTzSYhJZ3v3Xlq8J3cOmR7ZiOGl5q48Qgthyk=";
  };
in
{
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
            run = "z";
            desc = "zoxide";
          }
        ];
      };
    };
    zsh.initExtra = ''
      zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
    '';
  };
}
