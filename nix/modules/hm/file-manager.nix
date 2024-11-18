{ ... }:
{
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        flavor = "gruvbox-dark";
      };
	  flavors = [
gruvbox-dark = fetchTarball {
 url = "https://github.com/bennyyip/gruvbox-dark.yazi/archive/refs/heads/main.zip";
 sha256 = "0g3syimbxcayn5l43gw9svaa3g2k8wj3iz6990qbpb7vb0xf5frh";
  ];
    };
    zsh.initExtra = ''
      zvm_after_init_commands+=("bindkey -s '^e' 'yazi\n'")
    '';
  };
}
