local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local lazy_root = vim.fn.stdpath("data") .. "/lazy"

vim.g.mapleader = " "
vim.opt.runtimepath:prepend(config_root)
vim.opt.runtimepath:prepend(lazy_root .. "/mini.nvim")
vim.opt.runtimepath:prepend(lazy_root .. "/nvim-ts-context-commentstring")

local specs = dofile(config_root .. "/lua/plugins/mini.lua")
assert(#specs == 1, "mini modules must be consolidated into one plugin spec")

local spec = specs[1]
assert(spec[1] == "nvim-mini/mini.nvim", "mini.nvim must use its current upstream repository")
assert(type(spec.config) == "function", "mini.nvim needs one central config function")

spec.config()

for _, global in ipairs({
	"MiniAi",
	"MiniBufremove",
	"MiniClue",
	"MiniComment",
	"MiniDiff",
	"MiniFiles",
	"MiniSplitjoin",
	"MiniSurround",
	"MiniTrailspace",
}) do
	assert(_G[global], global .. " was not configured")
end

assert(MiniFiles.config.options.permanent_delete == false, "mini.files deletions must use its trash")
assert(vim.fn.maparg("<leader>e", "n") ~= "", "<leader>e mini.files mapping is missing")
assert(vim.fn.maparg("<leader>E", "n") ~= "", "<leader>E cwd explorer mapping is missing")
assert(vim.fn.maparg("<leader>go", "n") ~= "", "mini.diff overlay mapping is missing")
assert(vim.fn.maparg("<leader>gs", "n") ~= "", "current hunk stage mapping is missing")
assert(vim.fn.maparg("<leader>gr", "n") ~= "", "current hunk reset mapping is missing")

assert(
	vim.uv.fs_stat(config_root .. "/lua/plugins/nvim-tree.lua") == nil,
	"nvim-tree spec must be removed after mini.files replaces it"
)

print("mini.nvim integration checks passed")
