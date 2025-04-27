{
  pkgs,
  config,
  ...
}: let
  neovim = pkgs.neovim.extend config.lib.stylix.nixvim.config;
in {
  home.packages = with pkgs; [
    stylua
    lua-language-server

    biome
    nodePackages.prettier

    beautysh

    marksman

    nixd
    alejandra

    typescript-language-server
    neovim
  ];
}
