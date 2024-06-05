return {
        "folke/trouble.nvim",
		opts = {},
		cmd = "Trouble",
		keys = {
				{ "<leader>tt", "<cmd>Trouble quickfix toggle<cr>", desc = "[T]rouble [T]oggle" },
				{ "[t", "<cmd>Trouble previous<cr>", desc = "[T]rouble previous" },
				{ "]t", "<cmd>Trouble next<cr>", desc = "[T]rouble next" },
		},
}

