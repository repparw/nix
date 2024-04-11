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
}

for k,v in pairs(options) do
  vim.opt[k] = v
end

vim.g.python_host_prog = '/usr/bin/python2'
vim.g.python3_host_prog = '/usr/bin/python3'

vim.cmd [[colorscheme gruvbox]]

vim.g.mapleader = ' '



-- Enable alignment
vim.g.neoformat_basic_format_align = 1
-- Enable tab to space conversion
vim.g.neoformat_basic_format_retab = 1
-- Enable trimming of trailing whitespace
vim.g.neoformat_basic_format_trim = 1

-- vim.plug
local vim = vim
local Plug = vim.fn['plug#']
local Path = '~/.config/nvim/plugged'
vim.call('plug#begin', Path)

Plug('junegunn/fzf')
Plug('junegunn/fzf.vim')
Plug('sbdchd/neoformat')
Plug('vim-airline/vim-airline')
-- Autocomplete engine, tabnine and python plugin
Plug('Shougo/deoplete.nvim', {['do'] = ':UpdateRemotePlugins'})
Plug('zchee/deoplete-jedi')
-- Auto-pair for brackets and quotes
Plug('jiangmiao/auto-pairs')
-- Tree file explorer
Plug('preservim/nerdtree')
-- Rainbow CSV
Plug('mechatroner/rainbow_csv')

vim.call('plug#end')

vim.g.airline_powerline_fonts = 1
vim.g['deoplete#enable_at_startup'] = 1
-- vim.plug end


-- Transparent bg
vim.cmd [[hi Normal ctermbg=NONE guibg=NONE]]
vim.cmd [[hi LineNr ctermbg=NONE guibg=NONE]]
vim.cmd [[hi SignColumn ctermbg=NONE guibg=NONE]]

-- Mappings
vim.keymap.set({'n', 'v'}, '<leader>s', ':update<CR>') -- Save
vim.cmd [[inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"]]
vim.cmd [[inoremap <expr><s-tab> pumvisible() ? "\<c-p>" : "<s-tab>"]]
-- fzf
vim.keymap.set('n', '<leader>o', ':Files<CR>', { silent = true }) -- Open fzf file picker
vim.keymap.set('n', '<leader>O', ':Files!<CR>', { silent = true }) -- Same but with fullscreen
vim.keymap.set('n', '<F1>', ':Helptags<CR>', { silent = true }) -- Open help tags in fzf
