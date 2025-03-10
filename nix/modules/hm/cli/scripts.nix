{ pkgs, ... }:
{

  obsinvim =
    with pkgs;
    writeShellApplication {
      name = "";
      runtimeInputs = [ ];
      text = ''
        cd /home/repparw/Documents/obsidian; nvim .
      '';
    };

  git-autocommit =
    with pkgs;
    writeShellApplication {
      name = "";
      runtimeInputs = [ ];
      text = '''';
    };

}
