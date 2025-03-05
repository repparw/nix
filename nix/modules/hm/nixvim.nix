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
        keymaps = {
          "<C-p>" = {
            action = "git_files";
			options = { desc = "Find project files"};
          };
				"<leader>fh" = {
										action = "help_tags";
										options = { desc = "[F]ind [H]elp"};
        };
		"<leader>fk" = {
									action = "keymaps";
									options = { desc = "[F]ind [K]eymaps"};

        };
		"<leader>ff" = {
								action = "find_files";
								options = { desc = "[F]ind [F]iles"};
								};
								"<leader>fs" = {
									action = "builtin";
									options = { desc = "[F]ind [S]elect Telescope"};
								};
								"<leader>fw" = {
									action = "grep_string";
									options = { desc = "[F]ind current [W]ord"};
								};
								"<leader>fh" = {
									action = "help_tags";
									options = { desc = "[F]ind [H]elp"};
								};
        };

vim.keymap.set('n', '<leader>fw', builtin.grep_string, { desc = '[F]ind current [W]ord' })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = '[F]ind by [G]rep' })
vim.keymap.set('n', '<leader>fD', builtin.diagnostics, { desc = '[F]ind [D]iagnostics' })
vim.keymap.set('n', '<leader>fd', telescope.extensions.zoxide.list, { desc = '[F]ind by [D]irectory' })
vim.keymap.set('n', '<leader>fr', builtin.resume, { desc = '[F]ind [R]esume' })
vim.keymap.set('n', '<leader>f.', builtin.oldfiles, { desc = '[F]ind Recent Files ("." for repeat)' })
vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
vim.keymap.set('n', '<C-p>', project_files, { desc = 'Find project files' })


        settings = {

        };
      };
    };

  };
}
