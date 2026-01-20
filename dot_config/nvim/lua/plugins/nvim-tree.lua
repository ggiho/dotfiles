return {
	"nvim-tree/nvim-tree.lua",
	cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeOpen" }, -- 명령어 호출 시 로딩
	keys = {
		{ "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file explorer" },
            { 
        "<leader>;", 
        function()
            if vim.bo.filetype == "NvimTree" then
                vim.cmd("wincmd p")
            else
                vim.cmd("NvimTreeFocus")
            end
        end, 
        desc = "Toggle focus between file and explorer" 
    },
	},
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local nvimtree = require("nvim-tree")

		vim.g.loaded_netrw = 1
		vim.g.loaded_netrwPlugin = 1

		nvimtree.setup({
			view = { width = 35, relativenumber = true },
			renderer = {
				indent_markers = { enable = true },
				icons = {
					glyphs = {
						folder = {
							arrow_closed = "",
							arrow_open = "",
						},
					},
				},
			},
			actions = {
				open_file = {
					window_picker = { enable = false },
				},
			},
			filters = { custom = { ".DS_Store" } },
			git = { ignore = false },
		})
	end,
}

