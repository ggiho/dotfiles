return {
	"nvim-lua/plenary.nvim",
	{
		"christoomey/vim-tmux-navigator",
		keys = {
			{ "<M-h>", "<cmd>TmuxNavigateLeft<CR>", desc = "Move focus left (Neovim/tmux)" },
			{ "<M-j>", "<cmd>TmuxNavigateDown<CR>", desc = "Move focus down (Neovim/tmux)" },
			{ "<M-k>", "<cmd>TmuxNavigateUp<CR>", desc = "Move focus up (Neovim/tmux)" },
			{ "<M-l>", "<cmd>TmuxNavigateRight<CR>", desc = "Move focus right (Neovim/tmux)" },
		},
	},
}
