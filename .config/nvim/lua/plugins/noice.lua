return {
  "folke/noice.nvim",
  event = "VeryLazy",
  opts = {
    -- add any options here
  },
  dependencies = {
    -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
    "MunifTanjim/nui.nvim",
    -- OPTIONAL:
    --   `nvim-notify` is only needed, if you want to use the notification view.
    -- "rcarriga/nvim-notify",
  },
  config = {
	lsp = {
	  -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
	  override = {
		["vim.lsp.util.convert_input_to_markdown_lines"] = true,
		["vim.lsp.util.stylize_markdown"] = true,
		["cmp.entry.get_documentation"] = true, -- requires hrsh7th/nvim-cmp
	  },
	},
	views = {
          cmdline_popup = {
            backend = 'popup',
            relative = 'editor',
            zindex = 200,
            position = {
              row = '40%', -- 40% from top of the screen. This will position it almost at the center.
              col = '50%',
            },
            size = {
              width = 120,
              height = 'auto',
            },
            win_options = {
              winhighlight = {
                Normal = 'NoiceCmdlinePopup',
                FloatTitle = 'NoiceCmdlinePopupTitle',
                FloatBorder = 'NoiceCmdlinePopupBorder',
                IncSearch = '',
                CurSearch = '',
                Search = '',
              },
              winbar = '',
              foldenable = false,
              cursorline = false,
            },
          },
        },
        cmdline = {
          view = 'cmdline_popup', -- cmdline_popup, cmdline
		},
	-- you can enable a preset for easier configuration
	presets = {
	  bottom_search = true, -- use a classic bottom cmdline for search
	  command_palette = true, -- position the cmdline and popupmenu together
	  long_message_to_split = true, -- long messages will be sent to a split
  --	inc_rename = false, -- enables an input dialog for inc-rename.nvim
	  lsp_doc_border = false, -- add a border to hover docs and signature help
	},
  }
}
