return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = ":TSUpdate",
	config = function()
		local treesitter = require("nvim-treesitter")

		treesitter.setup({})
		treesitter.install({ "toml", "yaml" })

		local group = vim.api.nvim_create_augroup("treesitter_start", { clear = true })
		vim.api.nvim_create_autocmd("FileType", {
			group = group,
			callback = function(event)
				local language = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
				if language and vim.treesitter.language.add(language) then
					vim.treesitter.start(event.buf, language)
				end
			end,
		})
	end,
}
