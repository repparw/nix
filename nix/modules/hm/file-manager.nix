{ ... }:
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
        smart-enter = fetchTarball {
          url = "https://github.com/yazi-rs/plugins/tree/main/smart-enter.yazi";
          sha256 = "0bac6gcdqbl8hvqv3ylykz3nhbc6103p8sll7457mky7pavrwali";
        };
      };
      zsh.initExtra = ''
        zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
      '';
    };
  };
}
