return {
  "epwalsh/obsidian.nvim",
  version = "*",  -- recommended, use latest release instead of latest commit
  lazy = true,
  event = {
     "BufReadPre /home/repparw/Documents/obsidian/**.md",
     "BufNewFile /home/repparw/Documents/obsidian/**.md",
  },
  dependencies = {
    -- Required.
    "nvim-lua/plenary.nvim",

  },
  opts = {
    workspaces = {
      {
        name = "obsidian",
        path = "~/Documents/obsidian",
      },
    },
	mappings = {
	  ["gf"] = {
      action = function()
        return require("obsidian").util.gf_passthrough()
      end,
      opts = { noremap = false, expr = true, buffer = true },
    },
	  ["<leader>o"] = {
	  action = function()
		  return require("obsidian").util.ObsidianOpen()
	   -- return require("obsidian").get_client():command("ObsidianNew", { args = "Foo" })
	  end,
	  opts = { noremap = false, expr = true, buffer = true },
	},
    -- Smart action depending on context, either follow link or toggle checkbox.
	  ["<cr>"] = {
	  action = function()
		return require("obsidian").util.smart_action()
	  end,
	  opts = { buffer = true, expr = true },
    },
  },
 },

}
