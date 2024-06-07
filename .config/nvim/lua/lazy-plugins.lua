require("lazy").setup({
  require 'plugins/gruvbox',
  require 'plugins/autopairs',
  require 'plugins/nvim-surround',
  require 'plugins/undotree',
  require 'plugins/lualine',
  require 'plugins/whichkey',
  require 'plugins/cmp',
  require 'plugins/lspconfig',
  require 'plugins/gitsigns',
  require 'plugins/telescope',
  require 'plugins/copilot',
  require 'plugins/copilot-cmp',
  require 'plugins/obsidian',
  require 'plugins/fugitive',
  require 'plugins/noice',
--  require 'plugins/codeium',
  }, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})
