{ ... }:
{
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;

    };
    zsh.initExtra = ''
      zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
    '';
  };
}
