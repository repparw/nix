{ pkgs, ... }:
let
  plugins-repo = pkgs.fetchFromGitHub {
    owner = "yazi-rs";
    repo = "plugins";
    rev = "main";
    sha256 = "38418ddc9247de206645ed284c804b5e179452a1";
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
      };
      keymap = {
        manager.prepend_keymap = [
          {
            on = [ "l" ];
            run = "plugin --sync smart-enter";
            # For upcoming Yazi 0.4 (nightly version):
            # run  = "plugin smart-enter"
            desc = "Enter the child directory, or open the file";
          }
        ];
      };
    };
    zsh.initExtra = ''
      zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
    '';
  };
}
