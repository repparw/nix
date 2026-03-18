{
  den,
  ...
}:
{
  den.aspects.userRepparw = {
    includes = [ ];

    homeManager = { pkgs, ... }: {
      imports = [
        ../../lib/hm-modules
      ];

      home.username = "repparw";
      home.homeDirectory = "/home/repparw";
      home.stateVersion = "25.05";

      programs.fish = {
        enable = true;
      };

      programs.starship = {
        enable = true;
      };

      programs.git = {
        enable = true;
        userName = "repparw";
        userEmail = "ubritos@gmail.com";
      };

      programs.zsh.enable = false;
    };
  };
}
