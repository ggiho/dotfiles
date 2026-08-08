return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = ":TSUpdate",
	config = function()
		local treesitter = require("nvim-treesitter")

		treesitter.setup({})
		-- Only parsers Neovim does NOT bundle. Built-in (statically linked, with
		-- queries in $VIMRUNTIME): c, lua, markdown, markdown_inline, query, vim,
		-- vimdoc -- those are left to the built-in and intentionally omitted here.
		treesitter.install({
			-- config / data formats (jsonc reuses the json parser automatically)
			"json",
			"yaml",
			"toml",
			-- languages in use (mirrors the configured LSP servers)
			"python",
			"bash",
			"javascript",
			"typescript",
			"tsx",
			"cpp",
			"html",
			"css",
			-- database
			"sql",
			-- misc dev
			"diff",
			"gitcommit",
			"gitignore",
			"dockerfile",
		})

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
