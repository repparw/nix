{...}: {
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
      action = "<cmd>Trouble diagnostics toggle<cr>";
      key = "<leader>tt";
      mode = "n";
      options = {
        desc = "[T]rouble [T]oggle";
      };
    }
    {
      action = "<cmd>Trouble previous";
      key = "[t";
      mode = "n";
      options = {
        desc = "[T]rouble previous";
      };
    }
    {
      action = "<cmd>Trouble next";
      key = "]t";
      mode = "n";
      options = {
        desc = "[T]rouble next";
      };
    }
    {
      action = "<cmd>cprev<CR>";
      key = "[c";
      mode = "n";
      options = {
        desc = "[c]ycle quickfix prev";
        silent = true;
      };
    }
    {
      action = "<cmd>cnext<CR>";
      key = "]c";
      mode = "n";
      options = {
        desc = "[c]ycle quickfix next";
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
      action = "<cmd>lprev<CR>";
      key = "[l";
      mode = "n";
      options = {
        silent = true;
        "<leader>ca" = {
          action = "code_action";
          desc = "Code Action";
        };
        desc = "cycle [l]oclist prev";
      };
    }
    {
      action = "<cmd>lnext<CR>";
      key = "]l";
      mode = "n";
      options = {
        silent = true;
        desc = "cycle [l]oclist next";
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
/**/

