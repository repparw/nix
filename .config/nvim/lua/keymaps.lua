-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Visual line wraps
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Set void registers for x, s and c operations
-- This is useful to prevent overriding the system clipboard
vim.keymap.set('n', 'x', '"_x')
vim.keymap.set('n', 'X', '"_X')
vim.keymap.set('n', 's', '"_s')
vim.keymap.set('n', 'c', '"_c')

-- quickfix and location list
vim.keymap.set('n', '<C-q>', ':lua require("utils").toggle_qf()<CR>', { desc = 'Toggle quickfix' })
vim.keymap.set('n', '<C-l>', ':lua require("utils").toggle_ll()<CR>', { desc = 'Toggle location list' })
vim.keymap.set('n', '<leader><C-o>', ':lua require("utils").jumps_to_qf()<CR>', { desc = 'Send jumplist to quickfix' })

vim.keymap.set('n', '<leader>o', function() vim.cmd('ObsidianOpen') end, { noremap = true, silent = true, desc = 'Open Obsidian' })

vim.keymap.set('n', '<leader>y', '"+y', { desc = 'Yank to clipboard' }) -- Copy to clipboard
vim.keymap.set('v', '<leader>y', '"+y', { desc = 'Yank to clipboard' }) -- Copy to clipboard
vim.keymap.set('n', '<leader>Y', '"+Y', { desc = 'Yank lines to clipboard' }) -- Copy to clipboard

vim.keymap.set('n', 'Q', '<Nop>') -- Disable Ex mode

vim.keymap.set({'n', 'v'}, '<leader>s', ':update<CR>', { desc = '[S]ave'}) -- Save
