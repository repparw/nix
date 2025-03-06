{ ... }:
{

  programs.nixvim.keymaps = [
    {
      action = "y$";
      key = "Y";
      mode = "n";
      options = {
        desc = "[Y]ank to end of line";
        silent = true;
      };
    }
    {
      action = "<cmd>CopilotChat<CR>";
      key = "<leader>aa";
      mode = "n";
      options = {
        desc = "Toggle [a]i chat";
        silent = true;
      };
    }
    {
      action = "<cmd>bprevious<CR>";
      key = "[b";
      mode = "n";
      options = {
        desc = "previous [b]uffer";
        silent = true;
      };
    }
    {
      action = "<cmd>bnext<CR>";
      key = "]b";
      mode = "n";
      options = {
        desc = "next [b]uffer";
        silent = true;
      };
    }
    {
      action = "<cmd>bfirst<CR>";
      key = "[B";
      mode = "n";
      options = {
        desc = "first [B]uffer";
        silent = true;
      };
    }
    {
      action = "<cmd>blast<CR>";
      key = "]B";
      mode = "n";
      options = {
        desc = "last [B]uffer";
        silent = true;
      };
    }
    {
      action = "<cmd>cleft<CR>";
      key = "[c";
      mode = "n";
      options = {
        desc = "[c]ycle quickfix left";
        silent = true;
      };
    }
    {
      action = "<cmd>cright<CR>";
      key = "]c";
      mode = "n";
      options = {
        desc = "[c]ycle quickfix right";
        silent = true;
      };
    }
    {
      action = "<cmd>cfirst<CR>";
      key = "[C";
      mode = "n";
      options = {
        desc = "first quickfix entry";
        silent = true;
      };
    }
    {
      action = "<cmd>clast<CR>";
      key = "]C";
      mode = "n";
      options = {
        desc = "last quickfix entry";
        silent = true;
      };
    }
    {
      action = "<cmd>toggle_qf_list<CR>";
      key = "<C-c>";
      mode = "n";
      options = {
        desc = "toggle quickfix list";
      };
    }
    {
      action = "<cmd>lleft<CR>";
      key = "[l";
      mode = "n";
      options = {
        silent = true;
        desc = "cycle [l]oclist left";
      };
    }
    {
      action = "<cmd>lright<CR>";
      key = "]l";
      mode = "n";
      options = {
        silent = true;
        desc = "cycle [l]oclist right";
      };
    }
    {
      action = "<cmd>lfirst<CR>";
      key = "[L";
      mode = "n";
      options = {
        silent = true;
        desc = "first [L]oclist entry";
      };
    }
    {
      action = "<cmd>llast<CR>";
      key = "]L";
      mode = "n";
      options = {
        silent = true;
        desc = "last [L]oclist entry";
      };
    }
    {
      action = "<C-d>zz";
      key = "<C-d>";
      mode = "n";
      options = {
        desc = "move [d]own half-page and center";
      };
    }
    {
      action = "<C-u>zz";
      key = "<C-u>";
      mode = "n";
      options = {
        desc = "move [u]p half-page and center";
      };
    }
    {
      action = "<C-f>zz";
      key = "<C-f>";
      mode = "n";
      options = {
        desc = "move DOWN [f]ull-page and center";
      };
    }
    {
      action = "<C-b>zz";
      key = "<C-b>";
      mode = "n";
      options = {
        desc = "move UP full-page and center";
      };
    }
    {
      action = "\"_x";
      key = "x";
      mode = "n";
    }
    {
      action = "\"_X";
      key = "X";
      mode = "n";
    }
    {
      action = "\"_s";
      key = "s";
      mode = "n";
    }
    {
      action = "\"_c";
      key = "c";
      mode = "n";
    }
    {
      action = "\"_dP";
      key = "<leader>p";
      mode = "n";
    }
    {
      action = "v:count == 0 ? 'gj' : 'j'";
      key = "j";
      mode = "n";
      options = {
        expr = true;
      };
    }
    {
      action = "v:count == 0 ? 'gk' : 'k'";
      key = "k";
      mode = "n";
      options = {
        expr = true;
      };
    }
    {
      action = ":m '>+1<CR>gv=gv";
      key = "J";
      mode = "v";
      options = {
        silent = true;
      };
    }
    {
      action = ":m '<-2<CR>gv=gv";
      key = "K";
      mode = "v";
      options = {
        silent = true;
      };
    }
    {
      action = "\"+y";
      key = "<leader>y";
      mode = [
        "n"
        "v"
      ];
      options = {
        desc = "Yank to clipboard";
      };
    }
    {
      action = "\"+Y";
      key = "<leader>Y";
      mode = "n";
      options = {
        desc = "Yank lines to clipboard";
      };
    }
    {
      action = "<Nop>";
      key = "Q";
      mode = "n";
      options = {
        desc = "Disable Ex mode";
      };
    }
    {
      action = "<cmd>update<CR>";
      key = "<leader>s";
      mode = [
        "n"
        "v"
      ];
      options = {
        desc = "[S]ave";
        silent = true;
      };
    }
  ];
}
/*
  -- move between splits
  keymap.set('n', '<C-h>', '<C-w>h')
  keymap.set('n', '<C-j>', '<C-w>j')
  keymap.set('n', '<C-k>', '<C-w>k')
  keymap.set('n', '<C-l>', '<C-w>l')

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

  -- Shortcut for expanding to current buffer's directory in command mode
  keymap.set('c', '%%', function()
    if fn.getcmdtype() == ':' then
      return fn.expand('%:h') .. '/'
    else
      return '%%'
    end
  end, { expr = true, desc = "expand to current buffer's directory" })

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
*/
