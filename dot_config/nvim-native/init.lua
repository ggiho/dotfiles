vim.g.mapleader = " "

vim.opt.number = true
vim.opt.signcolumn = "yes"
vim.opt.autocomplete = true
vim.opt.autocompletedelay = 120
vim.opt.complete = { ".", "w", "b", "u", "t", "o" }
vim.opt.completeopt = { "menu", "menuone", "noselect", "popup" }
vim.opt.pumborder = "rounded"
vim.opt.pumheight = 12
vim.opt.pummaxwidth = 80

local data_home = vim.env.XDG_DATA_HOME or vim.fs.joinpath(vim.env.HOME, ".local", "share")
local main_data = vim.env.NVIM_MAIN_DATA_HOME or vim.fs.joinpath(data_home, "nvim")
local mason_bin = vim.fs.joinpath(main_data, "mason", "bin")
if vim.fn.isdirectory(mason_bin) == 1 then
	vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
end

local main_config = (vim.fn.stdpath("config"):gsub("nvim%-native$", "nvim"))
local servers = { "clangd", "html", "lua_ls", "pyright", "ruff", "ts_ls" }

for _, name in ipairs(servers) do
	local path = vim.fs.joinpath(main_config, "lsp", name .. ".lua")
	local ok, config = pcall(dofile, path)
	if ok and type(config) == "table" and config.cmd and vim.fn.executable(config.cmd[1]) == 1 then
		vim.lsp.config(name, config)
		vim.lsp.enable(name)
	end
end

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("native-completion", { clear = true }),
	callback = function(event)
		local client = assert(vim.lsp.get_client_by_id(event.data.client_id))
		if client:supports_method("textDocument/completion") then
			vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
		end
	end,
})

vim.keymap.set("i", "<C-Space>", vim.lsp.completion.get, { desc = "Trigger LSP completion" })

vim.keymap.set({ "i", "s" }, "<Tab>", function()
	if vim.fn.pumvisible() == 1 then
		return "<C-n>"
	end
	if vim.snippet.active({ direction = 1 }) then
		return "<Cmd>lua vim.snippet.jump(1)<CR>"
	end
	return "<Tab>"
end, { expr = true, silent = true })

vim.keymap.set({ "i", "s" }, "<S-Tab>", function()
	if vim.fn.pumvisible() == 1 then
		return "<C-p>"
	end
	if vim.snippet.active({ direction = -1 }) then
		return "<Cmd>lua vim.snippet.jump(-1)<CR>"
	end
	return "<S-Tab>"
end, { expr = true, silent = true })

vim.keymap.set("i", "<CR>", function()
	if vim.fn.pumvisible() == 0 then
		return "<CR>"
	end
	if vim.fn.complete_info({ "selected" }).selected == -1 then
		return "<C-n><C-y>"
	end
	return "<C-y>"
end, { expr = true, silent = true })
