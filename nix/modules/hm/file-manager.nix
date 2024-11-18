{ ... }:
{
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;
      settings = {
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
    };
    zsh.initExtra = ''
      zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
    '';
  };
}
