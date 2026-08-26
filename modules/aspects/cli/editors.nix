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
