return {
	"nvim-lua/plenary.nvim",
	{
		"christoomey/vim-tmux-navigator",
		keys = {
			{ "<C-h>", "<cmd>TmuxNavigateLeft<CR>", desc = "Move focus left (Neovim/tmux)" },
			{ "<C-j>", "<cmd>TmuxNavigateDown<CR>", desc = "Move focus down (Neovim/tmux)" },
			{ "<C-k>", "<cmd>TmuxNavigateUp<CR>", desc = "Move focus up (Neovim/tmux)" },
			{ "<C-l>", "<cmd>TmuxNavigateRight<CR>", desc = "Move focus right (Neovim/tmux)" },
		},
	},
}
