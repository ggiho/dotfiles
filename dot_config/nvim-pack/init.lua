vim.g.mapleader = " "
vim.loader.enable()

vim.api.nvim_create_autocmd("PackChanged", {
	group = vim.api.nvim_create_augroup("vim-pack-hooks", { clear = true }),
	callback = function(event)
		local spec = event.data.spec
		if spec.name ~= "nvim-treesitter" or event.data.kind ~= "update" then
			return
		end
		if not event.data.active then
			vim.cmd.packadd("nvim-treesitter")
		end
		vim.cmd.TSUpdate()
	end,
})

vim.pack.add({
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/nvim-telescope/telescope.nvim" },
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
})

require("telescope").setup({})

local treesitter = require("nvim-treesitter")
treesitter.setup({})
treesitter.install({ "toml", "yaml" })

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("vim-pack-treesitter", { clear = true }),
	callback = function(event)
		local language = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
		if language and vim.treesitter.language.add(language) then
			vim.treesitter.start(event.buf, language)
		end
	end,
})

