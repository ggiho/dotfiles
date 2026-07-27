------------------------------------------------------------
-- Neovim 0.11+ Native LSP Final Setup (no lspconfig)
-- - lsp/<name>.lua 파일이 반환하는 테이블을 레지스트리에 등록
-- - FileType에서 ensure + enable
-- - LspAttach에서 키맵/하이라이트 등
------------------------------------------------------------

-- Set default LSP capabilities for consistent encoding (UTF-16 LSP standard)
local default_capabilities = vim.lsp.protocol.make_client_capabilities()
default_capabilities.offsetEncoding = { "utf-16" }

-- Override make_position_params to always include position encoding
local original_make_position_params = vim.lsp.util.make_position_params
vim.lsp.util.make_position_params = function(window, offset_encoding)
	offset_encoding = offset_encoding or "utf-16"
	return original_make_position_params(window, offset_encoding)
end

-- Enhanced diagnostics configuration for 0.11+
vim.diagnostic.config({
	virtual_text = {
		spacing = 4,
		source = "if_many",
		prefix = "●",
		format = function(diagnostic)
			if diagnostic.severity == vim.diagnostic.severity.ERROR then
				return string.format("E: %s", diagnostic.message)
			elseif diagnostic.severity == vim.diagnostic.severity.WARN then
				return string.format("W: %s", diagnostic.message)
			elseif diagnostic.severity == vim.diagnostic.severity.INFO then
				return string.format("I: %s", diagnostic.message)
			elseif diagnostic.severity == vim.diagnostic.severity.HINT then
				return string.format("H: %s", diagnostic.message)
			end
			return diagnostic.message
		end,
	},
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = "✘",
			[vim.diagnostic.severity.WARN] = "▲",
			[vim.diagnostic.severity.HINT] = "⚑",
			[vim.diagnostic.severity.INFO] = "»",
		},
	},
	update_in_insert = false,
	underline = true,
	severity_sort = true,
	float = {
		focusable = false,
		close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
		border = "rounded",
		source = "always",
		prefix = "",
		scope = "cursor",
	},
})

-- 0) lsp/<name>.lua들을 레지스트리에 등록 (절대 경로로 안전하게 로드)
do
	local config_dir = vim.fn.stdpath("config")
	local lsp_dir = config_dir .. "/lsp"

	-- Check if lsp directory exists
	if vim.fn.isdirectory(lsp_dir) == 1 then
		-- Get all .lua files in lsp directory
		local lsp_files = vim.fn.glob(lsp_dir .. "/*.lua", false, true)

		for _, file_path in ipairs(lsp_files) do
			local name = vim.fn.fnamemodify(file_path, ":t:r") -- Get filename without extension
			if name then
				-- Use dofile for absolute path loading
				local ok, cfg = pcall(dofile, file_path)
				if ok and type(cfg) == "table" then
					vim.lsp.config[name] = cfg
					-- vim.notify(("✓ LSP config '%s' loaded successfully"):format(name), vim.log.levels.INFO)
				else
					vim.notify(("✗ lsp/%s.lua load failed or invalid"):format(name), vim.log.levels.WARN)
					vim.notify(("Error: %s"):format(tostring(cfg)), vim.log.levels.WARN)
				end
			end
		end
	else
		vim.notify("LSP configuration directory not found: " .. lsp_dir, vim.log.levels.WARN)
	end
end

-- 1) 등록-보장 + enable 헬퍼
local function ensure_lsp(name)
	if not vim.lsp.config[name] then
		-- Fallback: try to load directly with absolute path
		local config_dir = vim.fn.stdpath("config")
		local file_path = config_dir .. "/lsp/" .. name .. ".lua"
		local ok, cfg = pcall(dofile, file_path)
		if ok and type(cfg) == "table" then
			vim.lsp.config[name] = cfg
		else
			vim.notify(("LSP config '%s' not found"):format(name), vim.log.levels.WARN)
			return
		end
	end

	-- Check if LSP server binary exists, auto-install if missing
	local config = vim.lsp.config[name]
	if config and config.cmd then
		local cmd = config.cmd[1]
		if vim.fn.executable(cmd) == 0 then
			vim.notify(("LSP server '%s' not found. Attempting auto-install..."):format(cmd), vim.log.levels.WARN)

			-- Try to auto-install with Mason
			local mason_ok, mason_registry = pcall(require, "mason-registry")
			if mason_ok and mason_registry.is_installed(name) == false then
				vim.notify(("Installing '%s' via Mason..."):format(name), vim.log.levels.INFO)
				local package = mason_registry.get_package(name)
				package:install():once("closed", function()
					if package:is_installed() then
						vim.notify(("✓ Successfully installed '%s'"):format(name), vim.log.levels.INFO)
						vim.schedule(function()
							vim.lsp.enable(name)
						end)
					else
						vim.notify(
							("✗ Failed to install '%s'. Please install manually: :MasonInstall %s"):format(name, name),
							vim.log.levels.ERROR
						)
					end
				end)
				return
			else
				vim.notify(("Manual install required: :MasonInstall %s"):format(name), vim.log.levels.ERROR)
				return
			end
		end
	end

	-- Force UTF-16 encoding for all LSP clients (LSP standard)
	vim.lsp.enable(name)

	-- Set encoding after enable
	vim.schedule(function()
		local clients = vim.lsp.get_clients({ name = name })
		for _, client in ipairs(clients) do
			if client.offset_encoding ~= "utf-16" then
				client.offset_encoding = "utf-16"
			end
		end
	end)
end

-- 2) FileType → 서버 enable (with multiple servers per filetype support)
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "python", "lua", "javascript", "typescript", "typescriptreact", "javascriptreact", "html", "c", "cpp" },
	callback = function(ev)
		local map = {
			python = { "pyright", "ruff" }, -- Modern Python workflow: type checking + linting/formatting
			lua = "lua_ls",
			javascript = "ts_ls",
			javascriptreact = "ts_ls",
			typescript = "ts_ls",
			typescriptreact = "ts_ls",
			html = "html",
			c = "clangd",
			cpp = "clangd",
		}
		local servers = map[ev.match]
		if servers then
			if type(servers) == "table" then
				for _, name in ipairs(servers) do
					ensure_lsp(name)
				end
			else
				ensure_lsp(servers)
			end
		end
	end,
})

-- 3) LspAttach 시 키맵/하이라이트
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("neovim-starter", { clear = true }),
	callback = function(event)
		local client = vim.lsp.get_client_by_id(event.data.client_id)

		-- 키맵 유틸
		local function map(keys, func, desc)
			vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end

		-- Telescope 안전 로드
		local has_tb, tb = pcall(require, "telescope.builtin")

		map("gd", vim.lsp.buf.definition, "Go to definition")
		map("gD", vim.lsp.buf.declaration, "Go to declaration")

		-- Neovim 0.11+ provides these discoverable LSP mappings by default:
		-- grn - vim.lsp.buf.rename
		-- gra - vim.lsp.buf.code_action
		-- grr - vim.lsp.buf.references
		-- gri - vim.lsp.buf.implementation
		-- grt - vim.lsp.buf.type_definition
		-- gO  - vim.lsp.buf.document_symbol

		if has_tb then
			map("<leader>ls", tb.lsp_dynamic_workspace_symbols, "Workspace symbols")
		else
			map("<leader>ls", function()
				vim.lsp.buf.workspace_symbol()
			end, "Workspace symbols")
		end

		map("gl", vim.diagnostic.open_float, "Show diagnostic")
		map("<leader>lq", vim.diagnostic.setloclist, "Diagnostics list")
		map("[d", function()
			vim.diagnostic.jump({ count = -1, float = true })
		end, "Previous diagnostic")
		map("]d", function()
			vim.diagnostic.jump({ count = 1, float = true })
		end, "Next diagnostic")

		-- Force UTF-16 encoding for this client (LSP standard)
		if client then
			client.offset_encoding = "utf-16"
			-- Also ensure capabilities reflect the encoding
			if client.server_capabilities then
				client.server_capabilities.offsetEncoding = "utf-16"
				client.server_capabilities.positionEncoding = "utf-16"
			end
		end

		-- Inlay hints toggle (if supported)
		if client and client.server_capabilities.inlayHintProvider then
			map("<leader>lh", function()
				vim.lsp.inlay_hint.enable(
					not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }),
					{ bufnr = event.buf }
				)
			end, "Toggle inlay hints")
		end

		-- 문서 하이라이트 (지원 시)
		if client and client.server_capabilities.documentHighlightProvider then
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				callback = vim.lsp.buf.document_highlight,
			})
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				callback = vim.lsp.buf.clear_references,
			})
		end

		-- Neovim 0.11+ Enhanced Features

		-- Keep Ctrl-Space as a convenient alias for Neovim's built-in LSP omnifunc.
		if client and client.server_capabilities.completionProvider then
			vim.keymap.set("i", "<C-Space>", function()
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n", false)
			end, { buffer = event.buf, desc = "Trigger LSP completion" })
		end

		-- Enable inlay hints if supported
		if client and client.server_capabilities.inlayHintProvider then
			vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
		end

		-- Enhanced semantic token highlighting
		if client and client.server_capabilities.semanticTokensProvider then
			vim.b[event.buf].semantic_tokens = true
		end
	end,
})
