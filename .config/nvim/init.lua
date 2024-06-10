vim.g.have_nerd_font = true

vim.g.mapleader = ' '


require 'options'

require 'utils'

require 'keymaps'

require 'lazycfg'

vim.cmd [[ colorscheme gruvbox ]]

require('lualine').setup {
  options = { theme = 'gruvbox-material' },
  sections = {
	lualine_x = {
	  {
		require("noice").api.statusline.mode.get,
		cond = require("noice").api.statusline.mode.has,
		color = { fg = "#ff9e64" },
	  }
	},
  },
}

--local lsp_zero = require('lsp-zero')

--lsp_zero.on_attach(function(client, bufnr)
  -- see :help lsp-zero-keybindings
  -- to learn the available actions
--  lsp_zero.default_keymaps({buffer = bufnr})
--end)

--require('lspconfig').nil_ls.setup({})
