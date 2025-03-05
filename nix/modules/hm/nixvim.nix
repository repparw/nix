{ ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
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
    plugins = {
      treesitter.settings = {
        highlight = {
          enable = true;
          disable = "function(lang, buf)
      local max_filesize = 100 * 1024 -- 100 KB
      local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
      if ok and stats and stats.size > max_filesize then
        return true
      end
    end,
";
        };
      };
      telescope = {
        enable = true;

        settings = {
        };
      };
    };

  };
}
