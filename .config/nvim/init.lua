vim.g.have_nerd_font = true

vim.g.mapleader = ' '


require 'options'

require 'utils'

require 'keymaps'

require 'lazycfg'

vim.cmd [[ colorscheme gruvbox ]]

require('lualine').setup { options = { theme = 'gruvbox-material' } }
