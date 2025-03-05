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
    end
";
        };
      };
      telescope = {
        enable = true;
        keymaps = {
          "<C-p>" = {
            action = "git_files";
            options = {
              desc = "Find project files";
            };
          };
          "<leader>fh" = {
            action = "help_tags";
            options = {
              desc = "[F]ind [H]elp";
            };
          };
          "<leader>fk" = {
            action = "keymaps";
            options = {
              desc = "[F]ind [K]eymaps";
            };
          };
          "<leader>ff" = {
            action = "find_files";
            options = {
              desc = "[F]ind [F]iles";
            };
          };
          "<leader>fs" = {
            action = "builtin";
            options = {
              desc = "[F]ind [S]elect Telescope";
            };
          };
          "<leader>fw" = {
            action = "grep_string";
            options = {
              desc = "[F]ind current [W]ord";
            };
          };
          "<leader>fg" = {
            action = "live_grep";
            options = {
              desc = "[F]ind by [G]rep";
            };
          };
          "<leader>fD" = {
            action = "diagnostics";
            options = {
              desc = "[F]ind [D]iagnostics";
            };
          };
          "<leader>fd" = {
            action = "zoxide.list";
            options = {
              desc = "[F]ind by [D]irectory";
            };
          };
          "<leader>fr" = {
            action = "resume";
            options = {
              desc = "[F]ind [R]esume";
            };
          };
          "<leader>f." = {
            action = "oldfiles";
            options = {
              desc = "[F]ind Recent Files (\".\" for repeat)";
            };
          };
          "<leader><leader>" = {
            action = "buffers";
            options = {
              desc = "[F]ind [B]uffers";
            };
          };
        };

		extensions.ui-select.enable = true;
		extensions.fzf.enable = true;
		extensions.zoxide.enable = true;

        settings = {
		defaults = {
    path_display = {
      "truncate";
    };

    mappings = {
      i = {
        "<C-q>" = { __raw = "require('telescope.actions').send_to_qflist"; };
        "<C-l>" = { __raw = "require('telescope.actions').send_to_loclist"; };
        "<C-s>" = { __raw = "require('telescope.actions').cycle_previewers_next"; };
        "<C-a>" = { __raw = "require('telescope.actions').cycle_previewers_prev"; };
      };
      n = {
        q = { __raw = "require('telescope.actions').close"; };
      };
    };

    preview = {
      treesitter = true;
    };

    history = {
      path = "vim.fn.stdpath('data') .. '/telescope_history.sqlite3'";
      limit = 1000;
    };
    color_devicons = true;
    set_env = { COLORTERM = "truecolor";};
    prompt_prefix = "   ";
    selection_caret = "  ";
    entry_prefix = "  ";
	initial_mode = "insert";
	vimgrep_arguments = {
      "rg";
      "-L";
      "--color=never";
      "--no-heading";
      "--with-filename";
      "--line-number";
      "--column";
      "--smart-case";
    };
  pickers = {
    find_files = {
      hidden = true;
      follow = true;
    };
  };

  extensions = { "ui-select" = { __raw = "require('telescope.themes').get_dropdown()"; };};

        };
      };

    };

  };
  };
}
