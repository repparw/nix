-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

-- Visual line wraps
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })

-- Set void registers for x, s and c operations
-- This is useful to prevent overriding the system clipboard
vim.keymap.set("n", "x", '"_x')
vim.keymap.set("n", "X", '"_X')

-- move visual selection with JK
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true })

-- quickfix and location list
vim.keymap.set("n", "<C-q>", ':lua require("utils").toggle_qf()<CR>', { desc = "Toggle quickfix" })
vim.keymap.set("n", "s", '"_s')
vim.keymap.set("n", "c", '"_c')

-- avante
vim.keymap.set("n", "<leader>ac", ":AvanteChat<CR>", { desc = "Create a new Avante component" })

-- move between splits with Ctrl + hjkl
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

vim.keymap.set("n", "<leader>l", ':lua require("utils").toggle_ll()<CR>', { desc = "Toggle location list" })
vim.keymap.set("n", "<leader><C-o>", ':lua require("utils").jumps_to_qf()<CR>', { desc = "Send jumplist to quickfix" })

vim.keymap.set("n", "[q", ":cprevious<CR>", { desc = "Previous quickfix" })
vim.keymap.set("n", "]q", ":cnext<CR>", { desc = "Next quickfix" })

vim.keymap.set("n", "<leader>y", '"+y', { desc = "Yank to clipboard" }) -- Copy to clipboard
vim.keymap.set("v", "<leader>y", '"+y', { desc = "Yank to clipboard" }) -- Copy to clipboard
vim.keymap.set("n", "<leader>Y", '"+Y', { desc = "Yank lines to clipboard" }) -- Copy to clipboard

vim.keymap.set("n", "Q", "<Nop>") -- Disable Ex mode

vim.keymap.set({ "n", "v" }, "<leader>s", ":update<CR>", { silent = true, desc = "[S]ave" }) -- Save
