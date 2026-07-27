local installed = {}
for _, plugin in ipairs(vim.pack.get()) do
	installed[plugin.spec.name] = plugin
end

for _, name in ipairs({ "plenary.nvim", "telescope.nvim", "nvim-treesitter" }) do
	assert(installed[name], ("vim.pack did not register %s"):format(name))
end

assert(pcall(require, "plenary"), "plenary.nvim is not loadable")
assert(pcall(require, "telescope"), "telescope.nvim is not loadable")
assert(pcall(require, "nvim-treesitter"), "nvim-treesitter is not loadable")

local parsers_ready = vim.wait(120000, function()
	local parsers = require("nvim-treesitter").get_installed()
	return vim.tbl_contains(parsers, "toml") and vim.tbl_contains(parsers, "yaml")
end, 100)
assert(parsers_ready, "Treesitter parsers were not installed within 120 seconds")

local lockfile = vim.fs.joinpath(vim.fn.stdpath("config"), "nvim-pack-lock.json")
assert(vim.fn.filereadable(lockfile) == 1, "vim.pack lockfile was not created")

print("vim.pack smoke checks passed")
