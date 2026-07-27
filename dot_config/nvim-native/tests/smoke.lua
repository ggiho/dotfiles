assert(vim.o.autocomplete, "autocomplete must be enabled")
assert(vim.tbl_contains(vim.opt.complete:get(), "o"), "omnifunc must be an autocomplete source")

local completeopt = vim.opt.completeopt:get()
for _, value in ipairs({ "menuone", "noselect", "popup" }) do
	local present = completeopt[value] == true or vim.tbl_contains(completeopt, value)
	assert(present, ("completeopt must contain %s"):format(value))
end

local function has_insert_map(lhs)
	for _, mapping in ipairs(vim.api.nvim_get_keymap("i")) do
		if mapping.lhs == lhs then
			return true
		end
	end
	return false
end

assert(has_insert_map("<C-Space>"), "manual completion mapping is missing")
assert(has_insert_map("<Tab>"), "completion/snippet Tab mapping is missing")
assert(has_insert_map("<CR>"), "completion confirmation mapping is missing")

-- lua_ls only autostarts for a real Lua buffer, so open one before waiting.
if vim.fn.executable("lua-language-server") == 0 then
	print("native completion smoke checks skipped (lua-language-server not installed)")
	return
end

local scratch = vim.fs.joinpath(vim.fn.stdpath("run"), "nvim-native-smoke.lua")
vim.fn.writefile({ "return vim.api" }, scratch)
vim.cmd.edit(scratch)
vim.bo.filetype = "lua"

local attached = vim.wait(10000, function()
	return #vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" }) > 0
end, 50)
assert(attached, "lua_ls did not attach within 10 seconds")
assert(vim.bo.omnifunc == "v:lua.vim.lsp.omnifunc", "LSP omnifunc was not installed")

print("native completion smoke checks passed")
