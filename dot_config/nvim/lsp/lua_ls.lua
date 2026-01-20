return {
	name = "lua_ls",
	cmd = { "lua-language-server" },
	filetypes = { "lua" },
	root_markers = { 
		".luarc.json", 
		".luarc.jsonc", 
		".luacheckrc", 
		".stylua.toml", 
		"stylua.toml",
		"selene.toml",
		"selene.yml",
		".git"
	},
	telemetry = { enabled = false },
	formatters = {
		ignoreComments = false,
	},
	settings = {
		Lua = {
			runtime = {
				version = "LuaJIT",
			},
			signatureHelp = { enabled = true },
			diagnostics = {
				globals = { "vim" }, -- Recognize 'vim' global for Neovim config
			},
			workspace = {
				checkThirdParty = false,
				library = {
					vim.env.VIMRUNTIME,
					-- "${3rd}/luv/library"
					-- "${3rd}/busted/library",
				},
			},
			completion = {
				callSnippet = "Replace",
			},
			hint = {
				enable = true, -- Enable inlay hints
			},
		},
	},
}
