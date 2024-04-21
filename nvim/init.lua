local options = {
  splitbelow = true,
  splitright = true,
  termguicolors = true,
  ignorecase = true,
  smartcase = true,
  tabstop = 4,
  shiftwidth = 2,
  number = true,
  relativenumber = true,
  list = true,
  listchars = { tab = '» ', trail = '·', nbsp = '␣' },
  scrolloff = 10,
  inccommand = "split",
  background = "dark",
  showmode = false,
}

for k,v in pairs(options) do
  vim.opt[k] = v
end

vim.g.python_host_prog = '/usr/bin/python2'
vim.g.python3_host_prog = '/usr/bin/python3'

-- vim.cmd [[colorscheme gruvbox]]

vim.g.mapleader = ' '

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Enable alignment
vim.g.neoformat_basic_format_align = 1
-- Enable tab to space conversion
vim.g.neoformat_basic_format_retab = 1
-- Enable trimming of trailing whitespace
vim.g.neoformat_basic_format_trim = 1

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

require("lazy").setup("plugins")

require("nvim-surround").setup()
require('mason').setup()
require('lualine').setup {
  options = {
--  otheroption = '',
	theme = 'gruvbox'
  }
}

vim.cmd [[colorscheme gruvbox]]

-- Mappings

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    -- Enable completion triggered by <c-x><c-o>
    vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

    -- Buffer local mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
    vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<leader>f', function()
      vim.lsp.buf.format { async = true }
    end, opts)
  end,
})

-- Visual line wraps
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true })
vim.keymap.set({'n', 'v'}, '<leader>s', ':update<CR>') -- Save
vim.cmd [[inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"]]
vim.cmd [[inoremap <expr><s-tab> pumvisible() ? "\<c-p>" : "<s-tab>"]]
-- NERDTree
vim.keymap.set('n', '<leader>n', ':NERDTreeToggle<CR>', { silent = true }) -- Open fzf file picker
-- fzf
vim.keymap.set('n', '<leader>o', ':Files<CR>', { silent = true }) -- Open fzf file picker
vim.keymap.set('n', '<leader>O', ':Files!<CR>', { silent = true }) -- Same but with fullscreen
vim.keymap.set('n', '<F1>', ':Helptags<CR>', { silent = true }) -- Open help tags in fzf
