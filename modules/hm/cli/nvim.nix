{
  inputs,
  pkgs,
  ...
}: {
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

    inputs.nixvim-config.packages.${system}.default
  ];
}
