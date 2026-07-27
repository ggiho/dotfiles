local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

vim.g.mapleader = " "
vim.opt.runtimepath:prepend(config_root)

dofile(config_root .. "/lua/core/keymaps.lua")

local function find_global_map(mode, lhs)
	for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
		if mapping.lhs == lhs then
			return mapping
		end
	end
end

assert(find_global_map("n", " nh"), "<leader>nh must keep clearing search highlights")

for _, lhs in ipairs({ " w", " q", " re", " fp", "[b", "]b", " bb", " bd", " bD" }) do
	assert(find_global_map("n", lhs), lhs .. " core mapping is missing")
end

assert(find_global_map("n", " q").rhs == "<Cmd>quit!<CR>", "<leader>q must force-quit the current window")

assert(find_global_map("x", "J"), "visual J line movement is missing")
assert(find_global_map("x", "K"), "visual K line movement is missing")
assert(find_global_map("x", "p"), "visual paste must preserve the yank register")
assert(not find_global_map("n", "c"), "normal c must keep Vim's default register behavior")
assert(not find_global_map("n", "x"), "normal x must keep Vim's default register behavior")

local telescope = dofile(config_root .. "/lua/plugins/telescope.lua")[1]
local telescope_keys = {}
for _, mapping in ipairs(telescope.keys) do
	telescope_keys[mapping[1]] = true
end

for _, lhs in ipairs({ "<leader>ff", "<leader>fr", "<leader>fg", "<leader>fk", "<leader>fd" }) do
	assert(telescope_keys[lhs], lhs .. " Telescope mapping must be preserved")
end

local telescope_module = package.loaded["telescope"]
local telescope_themes = package.loaded["telescope.themes"]
local telescope_config
package.loaded["telescope"] = {
	setup = function(config)
		telescope_config = config
	end,
	load_extension = function() end,
}
package.loaded["telescope.themes"] = {
	get_dropdown = function()
		return {}
	end,
}
telescope.config()
package.loaded["telescope"] = telescope_module
package.loaded["telescope.themes"] = telescope_themes

local layout = telescope_config.defaults.layout_config
assert(layout.preview_height == nil, "strategy-specific preview_height must not leak into dropdown layouts")
assert(layout.width == 0.95 and layout.height == 0.95, "Telescope layout size must use shared width and height")
assert(layout.vertical.preview_height == 0.7, "vertical preview height is missing")
assert(layout.vertical.size == nil, "obsolete vertical.size config must not be used")

local plugin_specs = dofile(config_root .. "/lua/plugins/init.lua")
local tmux_navigator = plugin_specs[2]
local navigator_keys = {}
for _, mapping in ipairs(tmux_navigator.keys) do
	navigator_keys[mapping[1]] = true
end

for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
	assert(navigator_keys[lhs], lhs .. " Neovim/tmux navigation mapping is missing")
end

print("core keymap regression checks passed")
