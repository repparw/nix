{ ... }:
{
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        flavor = "gruvbox-dark";
      };
    };
    zsh.initExtra = ''
      zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
    '';
  };
}
