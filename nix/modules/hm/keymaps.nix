{ ... }:
{

local api = vim.api
local fn = vim.fn
local keymap = vim.keymap
local diagnostic = vim.diagnostic

programs.nixvim.keymaps = [
  {
	action = "y$";
	key = "Y";
	options = { desc = "[Y]ank to end of line"; silent = true; };
  }
  {
  action = "bprevious";
  key = "[b";
  options = { desc = "previous [b]uffer"; silent = true; };
  	}
  {
  action = "bnext";
  key = "]b";
  options = { desc = "next [b]uffer"; silent = true; };
  		}
  	{
	action = "bfirst";
	key = "[B";
	options = { desc = "first [B]uffer"; silent = true; };
		}
		{
		action = "blast";
		key = "]B";
		options = { desc = "last [B]uffer"; silent = true; };
			}
			{
			action = "cleft";
			key = "[c";
			options = { desc = "[c]ycle quickfix left"; silent = true; };
				}
				{
				action = "cright";
				key = "]c";
				options = { desc = "[c]ycle quickfix right"; silent = true; };
					}
					{
					action = "cfirst";
					key = "[C";
					options = { desc = "first quickfix entry"; silent = true; };
				}
				{
				action = "clast";
				key = "]C";
				options = { desc = "last quickfix entry"; silent = true; };
					}
					{
					action = "toggle_qf_list";
					key = "<C-c>";
					options = { desc = "toggle quickfix list"; };
						}
];


-- Toggle the quickfix list (only opens if it is populated)
local function toggle_qf_list()
  local qf_exists = false
  for _, win in pairs(fn.getwininfo() or {}) do
    if win['quickfix'] == 1 then
      qf_exists = true
    end
  end
  if qf_exists == true then
    vim.cmd.cclose()
    return
  end
  if not vim.tbl_isempty(vim.fn.getqflist()) then
    vim.cmd.copen()
  end
end

keymap.set('n', '<C-c>', toggle_qf_list, { desc = 'toggle quickfix list' })

local function try_fallback_notify(opts)
  local success, _ = pcall(opts.try)
  if success then
    return
  end
  success, _ = pcall(opts.fallback)
  if success then
    return
  end
  vim.notify(opts.notify, vim.log.levels.INFO)
end

-- Cycle the quickfix and location lists
local function cleft()
  try_fallback_notify {
    try = vim.cmd.cprev,
    fallback = vim.cmd.clast,
    notify = 'Quickfix list is empty!',
  }
end

local function cright()
  try_fallback_notify {
    try = vim.cmd.cnext,
    fallback = vim.cmd.cfirst,
    notify = 'Quickfix list is empty!',
  }
end

-- Visual line wraps
keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true })
keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true })

-- set void registers for operations
keymap.set('n', 'x', '"_x')
keymap.set('n', 'X', '"_X')
keymap.set('n', 's', '"_s')
keymap.set('n', 'c', '"_c')
keymap.set('n', '<leader>p', '"_dP')

-- move visual selection
keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { silent = true })
keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { silent = true })

-- move between splits
keymap.set('n', '<C-h>', '<C-w>h')
keymap.set('n', '<C-j>', '<C-w>j')
keymap.set('n', '<C-k>', '<C-w>k')
keymap.set('n', '<C-l>', '<C-w>l')

-- clipboard operations
keymap.set('n', '<leader>y', '"+y', { desc = 'Yank to clipboard' })
keymap.set('v', '<leader>y', '"+y', { desc = 'Yank to clipboard' })
keymap.set('n', '<leader>Y', '"+Y', { desc = 'Yank lines to clipboard' })

-- Disable Ex mode and add save shortcut
keymap.set('n', 'Q', '<Nop>')
keymap.set({ 'n', 'v' }, '<leader>s', ':update<CR>', { silent = true, desc = '[S]ave' })

local function lleft()
  try_fallback_notify {
    try = vim.cmd.lprev,
    fallback = vim.cmd.llast,
    notify = 'Location list is empty!',
  }
end

local function lright()
  try_fallback_notify {
    try = vim.cmd.lnext,
    fallback = vim.cmd.lfirst,
    notify = 'Location list is empty!',
  }
end

keymap.set('n', '[l', lleft, { silent = true, desc = 'cycle [l]oclist left' })
keymap.set('n', ']l', lright, { silent = true, desc = 'cycle [l]oclist right' })
keymap.set('n', '[L', vim.cmd.lfirst, { silent = true, desc = 'first [L]oclist entry' })
keymap.set('n', ']L', vim.cmd.llast, { silent = true, desc = 'last [L]oclist entry' })

-- Resize vertical splits
local toIntegral = math.ceil
keymap.set('n', '<leader>w+', function()
  local curWinWidth = api.nvim_win_get_width(0)
  api.nvim_win_set_width(0, toIntegral(curWinWidth * 3 / 2))
end, { silent = true, desc = 'inc window [w]idth' })
keymap.set('n', '<leader>w-', function()
  local curWinWidth = api.nvim_win_get_width(0)
  api.nvim_win_set_width(0, toIntegral(curWinWidth * 2 / 3))
end, { silent = true, desc = 'dec window [w]idth' })
keymap.set('n', '<leader>h+', function()
  local curWinHeight = api.nvim_win_get_height(0)
  api.nvim_win_set_height(0, toIntegral(curWinHeight * 3 / 2))
end, { silent = true, desc = 'inc window [h]eight' })
keymap.set('n', '<leader>h-', function()
  local curWinHeight = api.nvim_win_get_height(0)
  api.nvim_win_set_height(0, toIntegral(curWinHeight * 2 / 3))
end, { silent = true, desc = 'dec window [h]eight' })

-- Close floating windows [Neovim 0.10 and above]
keymap.set('n', '<leader>fq', function()
  vim.cmd('fclose!')
end, { silent = true, desc = '[f]loating windows: [q]uit/close all' })

-- Shortcut for expanding to current buffer's directory in command mode
keymap.set('c', '%%', function()
  if fn.getcmdtype() == ':' then
    return fn.expand('%:h') .. '/'
  else
    return '%%'
  end
end, { expr = true, desc = "expand to current buffer's directory" })

keymap.set('n', '<space>tn', vim.cmd.tabnew, { desc = '[t]ab: [n]ew' })
keymap.set('n', '<space>tq', vim.cmd.tabclose, { desc = '[t]ab: [q]uit/close' })

local severity = diagnostic.severity

keymap.set('n', '<space>e', function()
  local _, winid = diagnostic.open_float(nil, { scope = 'line' })
  if not winid then
    vim.notify('no diagnostics found', vim.log.levels.INFO)
    return
  end
  vim.api.nvim_win_set_config(winid or 0, { focusable = true })
end, { noremap = true, silent = true, desc = 'diagnostics floating window' })
keymap.set('n', '[d', diagnostic.goto_prev, { noremap = true, silent = true, desc = 'previous [d]iagnostic' })
keymap.set('n', ']d', diagnostic.goto_next, { noremap = true, silent = true, desc = 'next [d]iagnostic' })
keymap.set('n', '[e', function()
  diagnostic.goto_prev {
    severity = severity.ERROR,
  }
end, { noremap = true, silent = true, desc = 'previous [e]rror diagnostic' })
keymap.set('n', ']e', function()
  diagnostic.goto_next {
    severity = severity.ERROR,
  }
end, { noremap = true, silent = true, desc = 'next [e]rror diagnostic' })
keymap.set('n', '[w', function()
  diagnostic.goto_prev {
    severity = severity.WARN,
  }
end, { noremap = true, silent = true, desc = 'previous [w]arning diagnostic' })
keymap.set('n', ']w', function()
  diagnostic.goto_next {
    severity = severity.WARN,
  }
end, { noremap = true, silent = true, desc = 'next [w]arning diagnostic' })
keymap.set('n', '[h', function()
  diagnostic.goto_prev {
    severity = severity.HINT,
  }
end, { noremap = true, silent = true, desc = 'previous [h]int diagnostic' })
keymap.set('n', ']h', function()
  diagnostic.goto_next {
    severity = severity.HINT,
  }
end, { noremap = true, silent = true, desc = 'next [h]int diagnostic' })

keymap.set('n', '<C-d>', '<C-d>zz', { desc = 'move [d]own half-page and center' })
keymap.set('n', '<C-u>', '<C-u>zz', { desc = 'move [u]p half-page and center' })
keymap.set('n', '<C-f>', '<C-f>zz', { desc = 'move DOWN [f]ull-page and center' })
keymap.set('n', '<C-b>', '<C-b>zz', { desc = 'move UP full-page and center' })

-- Location list and jumplist operations
keymap.set('n', '<leader>l', function()
  require('utils').toggle_ll()
end, { silent = true, desc = 'Toggle location list' })

keymap.set('n', '<leader><C-o>', function()
  require('utils').jumps_to_qf()
end, { silent = true, desc = 'Send jumplist to quickfix' })
};
