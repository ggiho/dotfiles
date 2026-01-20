return {
	name = "ruff",
	cmd = { "ruff", "server" },
	filetypes = { "python" },
	root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
	single_file_support = true,
	settings = {
		-- Modern Ruff LSP configuration
		args = {
			"--preview", -- Enable preview features
		},
		organizeImports = true,
		fixAll = true,
		-- Disable diagnostics to avoid duplication with pyright
		lint = {
			enable = false,
		},
	},
	init_options = {
		settings = {
			-- Enable auto-fix on save for specific rules
			fixOnSave = {
				enable = true,
				-- Common auto-fix rules
				rules = {
					"F401", -- Remove unused imports
					"E501", -- Line too long (if configured)
					"I001", -- Import sorting
				},
			},
		},
	},
}