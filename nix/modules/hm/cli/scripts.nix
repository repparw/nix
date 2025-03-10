{ pkgs, ... }:
{

  home.packages = [
    obsinvim =
      with pkgs;
      writeShellApplication {
        name = "obsinvim";
        runtimeInputs = [ nvim ];
        text = ''
          cd /home/repparw/Documents/obsidian; nvim .
        '';
      };

    git-autocommit =
      with pkgs;
      writeShellApplication {
        name = "git-autocommit";
        runtimeInputs = [ git ];
        text = ''
          DIR=${"1:-/home/repparw/.dotfiles"}
          cd "$DIR" || exit 1
          git add -A
          git commit -m "Autocommit"
          git pull --rebase
          git push
        '';
      };
  ];

}
