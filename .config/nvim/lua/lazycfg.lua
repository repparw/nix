-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
	{
	  ui = {
		-- If you are using a Nerd Font: set icons to empty else define a unicode icons table
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
	}
})
