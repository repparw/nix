return {
	"yetone/avante.nvim",
	event = "VeryLazy",
	lazy = false,
	opts = {
		provider = "copilot",
		hints = { enabled = false },
		behaviour = { auto_suggestions = false },
		mappings = {
			ask = "<leader>a",
			edit = "<leader>e",
			toggle = "<leader>At",
			refresh = "<leader>Ar",
		},
		keys = function(_, keys)
			---@type avante.Config
			local opts = require("lazy.core.plugin").values(
				require("lazy.core.config").spec.plugins["avante.nvim"],
				"opts",
				false
			)

			local mappings = {
				{
					opts.mappings.ask,
					function()
						require("avante.api").ask()
					end,
					desc = "avante: ask",
					mode = { "n", "v" },
				},
				{
					opts.mappings.refresh,
					function()
						require("avante.api").refresh()
					end,
					desc = "avante: refresh",
					mode = "v",
				},
				{
					opts.mappings.edit,
					function()
						require("avante.api").edit()
					end,
					desc = "avante: edit",
					mode = { "n", "v" },
				},
			}
			mappings = vim.tbl_filter(function(m)
				return m[1] and #m[1] > 0
			end, mappings)
			return vim.list_extend(mappings, keys)
		end,
	},
	-- if you want to download pre-built binary, then pass source=false. Make sure to follow instruction above.
	-- Also note that downloading prebuilt binary is a lot faster comparing to compiling from source.
	build = ":AvanteBuild",
	dependencies = {
		"stevearc/dressing.nvim",
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
		"nvim-tree/nvim-web-devicons",
		{
			-- support for image pasting
			"HakonHarnes/img-clip.nvim",
			event = "VeryLazy",
			opts = {
				-- recommended settings
				default = {
					embed_image_as_base64 = false,
					prompt_for_file_name = false,
					drag_and_drop = {
						insert_mode = true,
					},
					-- required for Windows users
					use_absolute_path = true,
				},
			},
		},
		{
			-- Make sure to setup it properly if you have lazy=true
			"MeanderingProgrammer/render-markdown.nvim",
			opts = {
				file_types = { "markdown", "Avante" },
			},
			ft = { "markdown", "Avante" },
		},
	},
}
