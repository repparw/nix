{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./keymaps.nix
    ./lsp.nix
    ./plugins.nix
  ];

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
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    files = {
      "ftplugin/lua.lua" = {};
    };

    colorscheme = "gruvbox";

    colorschemes.gruvbox = {
      enable = true;
      settings = {
        transparent_mode = true;
      };
    };
    colorschemes.rose-pine.enable = true;
    colorschemes.tokyonight.enable = true;

    globals = {
      have_nerd_font = true;
      mapleader = " ";
      maplocalleader = " ";
    };

    diagnostics = {
      virtual_lines = {
        current_line = true;
      };
    };

    opts = {
      splitright = true;
      splitbelow = true;
      termguicolors = true;
      ignorecase = true;
      smartcase = true;
      tabstop = 4;
      shiftwidth = 2;
      number = true;
      relativenumber = true;
      list = true;
      listchars = {
        # eol = '↲';
        tab = "» ";
        trail = "·";
        extends = "<";
        precedes = ">";
        conceal = "┊";
        nbsp = "␣";
      };
      scrolloff = 10;
      inccommand = "split";
      background = "dark";
      showmode = false;
      mouse = "a";
      updatetime = 250;
      timeoutlen = 300;
      cursorline = true;
      undofile = true;
      conceallevel = 1;
    };
  };
}
