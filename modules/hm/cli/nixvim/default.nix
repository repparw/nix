{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./keymaps.nix
    ./lsp.nix
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

    extraPlugins = with pkgs.vimPlugins; [telescope-zoxide];

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
      nvim-jdtls = {
        enable = true;
        data = "${config.xdg.cacheHome}/jdtls/workspace";
        configuration = "${config.xdg.cacheHome}/jdtls/config";
      };

      alpha = {
        enable = true;
        theme = "dashboard";
        layout = [
          {
            type = "padding";
            val = 2;
          }
          {
            opts = {
              hl = "Type";
              position = "center";
            };
            type = "text";
            val = [
              "███╗   ██╗██╗██╗  ██╗██╗   ██╗██╗███╗   ███╗"
              "████╗  ██║██║╚██╗██╔╝██║   ██║██║████╗ ████║"
              "██╔██╗ ██║██║ ╚███╔╝ ██║   ██║██║██╔████╔██║"
              "██║╚██╗██║██║ ██╔██╗ ╚██╗ ██╔╝██║██║╚██╔╝██║"
              "██║ ╚████║██║██╔╝ ██╗ ╚████╔╝ ██║██║ ╚═╝ ██║"
              "╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝     ╚═╝"
            ];
          }
          {
            type = "padding";
            val = 2;
          }
          {
            type = "group";
            val = [
              {
                on_press = {
                  __raw = "function() vim.cmd[[ene]] end";
                };
                opts = {
                  shortcut = "e";
                };
                type = "button";
                val = "󰈞  Find file";
              }
              {
                opts = {
                  shortcut = "SPC f .";
                };
                type = "button";
                val = "󰊄 Find recent";
              }
              {
                on_press = {
                  __raw = "function() vim.cmd[[ene]] end";
                };
                opts = {
                  shortcut = "e";
                };
                type = "button";
                val = "  New file";
              }
            ];
          }
          {
            type = "padding";
            val = 2;
          }
          {
            opts = {
              hl = "Keyword";
              position = "center";
            };
            type = "text";
            val = "Inspiring quote here.";
          }
        ];
      };
      which-key.enable = true;
      gitsigns.enable = true;
      colorizer.enable = true;
      todo-comments.enable = true;
      web-devicons.enable = true;

      nvim-surround.enable = true;

      trouble.enable = true;

      copilot-lua = {
        enable = true;
        settings.suggestion.enabled = false;
      };
      copilot-cmp.enable = true;

      copilot-chat = {
        enable = true;
        settings = {
          model = "claude-3.5-sonnet";
        };
      };

      notify = {
        enable = true;
        settings.background_colour = "#000000";
      };

      conform-nvim = {
        enable = true;
        settings = {
          notify_on_error = false;
          format_on_save = ''
            function(bufnr)
                -- Disable format_on_save lsp_fallback for languages that don't
                -- have a well standardized coding style. You can add additional
                -- languages here or re-enable it for the disabled ones.
                local disable_filetypes = { c = true, cpp = true }
                return {
                  timeout_ms = 500,
                  lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
                }
              end'';
          formatters_by_ft = {
            lua = ["stylua"];
            nix = ["alejandra"];
            #rb = [ "rufo" ];
            sh = ["beautysh"];
            typescript = [
              "biome"
              "prettier"
            ];
            json = ["biome"];
            css = ["prettier"];
            html = ["prettier"];
          };
        };
      };

      noice = {
        enable = true;
        settings = {
          cmdline.view = "cmdline_popup";
          presets = {
            bottom_search = true;
            command_palette = true;
            long_message_to_split = true;
            inc_rename = false;
            lsp_doc_border = false;
          };
          views.cmdline_popup = {
            view = "popupmenu";
            position = {
              row = "40%";
              col = "50%";
            };
            zindex = 200;
            size.width = 120;
          };
        };
      };
      obsidian = {
        enable = true;
        settings = {
          workspaces = [
            {
              name = "obsidian";
              path = "~/Documents/obsidian";
            }
          ];
          mappings = {
            "<cr>" = {
              action = "require('obsidian').util.smart_action";
              opts = {
                buffer = true;
                expr = true;
              };
            };
            gf = {
              action = "require('obsidian').util.gf_passthrough";
              opts = {
                buffer = true;
                expr = true;
                noremap = false;
              };
            };
          };
          ui.checkboxes = {
            " " = {
              char = "󰄱";
              hl_group = "ObsidianTodo";
            };
            x = {
              char = "";
              hl_group = "ObsidianDone";
            };
          };
        };
      };
      treesitter = {
        enable = true;
        settings = {
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
      };
      lualine = {
        enable = true;
        settings = {
          options.globalStatus = true;
          extensions = [
            "fzf"
            "toggleterm"
            "quickfix"
          ];
          #sections = { lualine_x = [ { "require('noice').api.statusline.mode.get" cond = "require('noice').api.statusline.mode.has"; "color = { fg = # ff9e64 }" }]; TODO noice in statusline
        };
      };
      lspkind = {
        enable = true;
        symbolMap = {
          Copilot = " ";
        };
        extraOptions = {
          maxwidth = 50;
          ellipsis_char = "...";
        };
      };
      cmp = {
        enable = true;
        settings = {
          snippet.expand = ''
            function(args)
                vim.snippet.expand(args.body)
              end
          '';
          mapping = {
            "<C-n>" = "cmp.mapping.select_next_item()";
            "<C-p>" = "cmp.mapping.select_prev_item()";
            "<C-b>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<C-y>" = "cmp.mapping.confirm { select = true }";
            "<C-Space>" = "cmp.mapping.complete {}";
            "<C-l>" = "cmp.mapping(function()
      if luasnip.expand_or_locally_jumpable() then
        luasnip.expand_or_jump()
      end
    end, { 'i', 's' })";
            "<C-h>" = "cmp.mapping(function()
      if luasnip.locally_jumpable(-1) then
        luasnip.jump(-1)
      end
    end, { 'i', 's' })";
          };
          sources = [
            {
              name = "nvim_lsp";
              group_index = 2;
            }
            {
              name = "emoji";
              group_index = 2;
            }
            {
              name = "copilot";
              group_index = 2;
            }
            {
              name = "luasnip";
              group_index = 2;
            }
            {
              name = "path";
              group_index = 2;
            }
            {
              name = "buffer";
              group_index = 3;
            }
            {
              name = "latex_symbols";
              group_index = 3;
            }
          ];
          window = {
            completion = {
              border = [
                "╭"
                "─"
                "╮"
                "│"
                "╯"
                "─"
                "╰"
                "│"
              ];
              winhighlight = "Normal:CmpNormal,FloatBorder:CmpBorder,CursorLine:CmpSelection,Search:None";
            };
            documentation = {
              border = [
                "╭"
                "─"
                "╮"
                "│"
                "╯"
                "─"
                "╰"
                "│"
              ];
              winhighlight = "Normal:CmpDocNormal,FloatBorder:CmpDocBorder";
            };
          };
          experimental = {
            ghost_text = true;
          };
        };
      };
      cmp-nvim-lsp.enable = true;
      cmp_luasnip.enable = true;
      cmp-buffer.enable = true;
      cmp-path.enable = true;
      vimtex = {
        enable = true;
        settings = {
          compiler_method = "latexmk";
          compiler_engine = "xelatex";
          bibtex_options = "--min-crossrefs=999";
          compiler_latexmk = {
            options = [
              "-synctex=1"
              "-interaction=nonstopmode"
              "-file-line-error"
            ];
          };
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
            action = "zoxide list";
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

        extensions = {
          ui-select.enable = true;
          frecency.enable = true;
          fzf-native.enable = true;
        };

        enabledExtensions = ["zoxide"];

        settings = {
          defaults = {
            mappings = {
              i = {
                "<C-q>" = {
                  __raw = "require('telescope.actions').send_to_qflist";
                };
                "<C-l>" = {
                  __raw = "require('telescope.actions').send_to_loclist";
                };
                "<C-s>" = {
                  __raw = "require('telescope.actions').cycle_previewers_next";
                };
                "<C-a>" = {
                  __raw = "require('telescope.actions').cycle_previewers_prev";
                };
              };
              n = {
                q = {
                  __raw = "require('telescope.actions').close";
                };
              };
            };

            preview = {
              treesitter = true;
            };

            color_devicons = true;
            set_env = {
              COLORTERM = "truecolor";
            };
            prompt_prefix = "   ";
            selection_caret = "  ";
            entry_prefix = "  ";
            initial_mode = "insert";

            extensions = {
              "ui-select" = {
                __raw = "require('telescope.themes').get_dropdown()";
              };
            };
          };
          pickers = {
            find_files = {
              hidden = true;
              follow = true;
            };
          };
        };
      };
    };
  };
}
