{
  den,
  pkgs,
  config,
  ...
}:
{
  den.aspects.editors = {
    homeManager =
      {
        pkgs,
        config,
        ...
      }:
      {
        home.sessionVariables = {
          MANPAGER = "nvim +Man!";
          EDITOR = "nvim";
          VISUAL = "$EDITOR";
        };

        home.packages =
          let
            # Headless hosts (pi) carry no stylix: an unstyled nvim beats a
            # broken eval there, styled hosts extend with the real module.
            nvim = pkgs.repparw-neovim.extend (config.stylix.targets.nixvim.exportedModule or { });
          in
          with pkgs;
          [
            nvim
            devenv
            curl
            wget
            jq
            libnotify
            nodejs

            unzip
            trashy
            tree
            ffmpeg
            imagemagick
            less
            # yt-dlp

            fastfetch
            tlrc

            pdfgrep
            catdoc
          ]
          ++ [
            (pkgs.writeShellApplication {
              name = "hotswap";
              text = ''
                if [ $# -eq 0 ]; then
                  echo "Usage: hotswap <file>"
                  exit 1
                fi

                file="$1"

                if [ ! -e "$file" ]; then
                  echo "Error: File '$file' does not exist"
                  exit 1
                fi

                if [ ! -L "$file" ]; then
                  echo "File is not a symlink, nothing to do"
                  exit 1
                fi

                target="$(readlink -f "$file")"
                temp="$(mktemp)"

                cp "$target" "$temp"

                if nvim "$temp"; then
                  rm "$file"
                  mv "$temp" "$file"
                  echo "Saved."
                else
                  rm "$temp"
                  echo "Edit canceled."
                fi
              '';
            })
          ];
      };
  };
}
