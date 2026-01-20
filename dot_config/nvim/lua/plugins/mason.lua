return {
	"mason-org/mason-lspconfig.nvim",
	opts = {
		ensure_installed = { "lua_ls", "ts_ls", "html", "clangd", "ruff" },
	},
	dependencies = {
		{ "mason-org/mason.nvim", opts = {} },
		-- neovim 0.11 supports lsp natively
		-- "neovim/nvim-lspconfig",
	},
}
