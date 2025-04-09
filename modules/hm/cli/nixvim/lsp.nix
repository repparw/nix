{...}: {
  programs.nixvim.plugins.lsp = {
    enable = true;
    inlayHints = true;
    servers = {
      lua_ls.enable = true;
      nixd.enable = true;
      ts_ls.enable = true;
      marksman.enable = true;
      pyright.enable = true;
      jsonls.enable = true;
    };
    keymaps = {
      silent = true;
      lspBuf = {
        # using defaults from neovim 0.11
        # TODO toggle inlayHints?
        gd = {
          action = "definition";
          desc = "Goto Definition";
        };
        gD = {
          action = "declaration";
          desc = "Goto Declaration";
        };
        gT = {
          action = "type_definition";
          desc = "Type Definition";
        };
        K = {
          action = "hover";
          desc = "Hover";
        };
      };
      diagnostic = {
        "<leader>cd" = {
          action = "open_float";
          desc = "Line Diagnostics";
        };
        "[d" = {
          action = "goto_next";
          desc = "Next Diagnostic";
        };
        "]d" = {
          action = "goto_prev";
          desc = "Previous Diagnostic";
        };
      };
    };
  };
}
