local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

vim.g.mapleader = " "
vim.opt.runtimepath:prepend(config_root)

local last_jump
vim.diagnostic.goto_prev = function()
	last_jump = { count = -1, float = true }
end
vim.diagnostic.goto_next = function()
	last_jump = { count = 1, float = true }
end
vim.diagnostic.jump = function(opts)
	last_jump = opts
end

dofile(config_root .. "/lua/core/lsp.lua")

local attach_callback
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = "LspAttach" })) do
	if autocmd.group_name == "neovim-starter" then
		attach_callback = autocmd.callback
		break
	end
end
assert(attach_callback, "LspAttach callback was not registered")

local get_client_by_id = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function()
	return {
		id = 1,
		name = "test-lsp",
		offset_encoding = "utf-8",
		server_capabilities = { completionProvider = {} },
		supports_method = function()
			return false
		end,
	}
end

-- Simulate the buffer defaults that Neovim installs before LspAttach handlers run.
vim.bo.omnifunc = "v:lua.vim.lsp.omnifunc"
attach_callback({ buf = 0, data = { client_id = 1 } })
vim.lsp.get_client_by_id = get_client_by_id

local function find_map(lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
		if mapping.lhs == lhs then
			return mapping
		end
	end
end

assert(find_map("gd"), "gd definition mapping is missing")
assert(find_map("gD"), "gD declaration mapping is missing")
assert(find_map("gl"), "gl diagnostic float mapping is missing")
assert(find_map(" ls"), "workspace symbol mapping is missing")
assert(find_map(" lq"), "diagnostic list mapping is missing")
assert(find_map(" la"), "code action mapping is missing")
assert(find_map(" lr"), "rename mapping is missing")
assert(not find_map(" f"), "LSP must not shadow the Telescope <leader>f prefix")

local previous_diagnostic = assert(find_map("[d"), "previous diagnostic mapping is missing")
previous_diagnostic.callback()
assert(last_jump.count == -1 and last_jump.float == true, "[d must jump backward and open the float")

local next_diagnostic = assert(find_map("]d"), "next diagnostic mapping is missing")
next_diagnostic.callback()
assert(last_jump.count == 1 and last_jump.float == true, "]d must jump forward and open the float")

assert(vim.bo.omnifunc == "v:lua.vim.lsp.omnifunc", "LSP omnifunc default was changed")

local completion_mapping
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "i")) do
	if mapping.lhs == "<C-Space>" then
		completion_mapping = mapping
		break
	end
end
assert(completion_mapping, "manual LSP completion mapping is missing")

local ts_ls = dofile(config_root .. "/lsp/ts_ls.lua")
for _, filetype in ipairs(ts_ls.filetypes) do
	assert(
		filetype ~= "javascript.jsx" and filetype ~= "typescript.tsx",
		"ts_ls contains a non-standard Neovim filetype"
	)
end

print("lsp keymap regression checks passed")
