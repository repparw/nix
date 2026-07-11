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
            nvim = pkgs.repparw-neovim.extend config.stylix.targets.nixvim.exportedModule;
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

            android-tools
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
          ];
      };
  };
}
