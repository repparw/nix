vim.opt.conceallevel = 1

vim.keymap.set('n', '<leader>o', function() vim.cmd('ObsidianOpen') end, { noremap = true, silent = true, desc = 'Open Obsidian' })

