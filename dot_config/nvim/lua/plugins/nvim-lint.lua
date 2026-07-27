return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")
		lint.linters_by_ft = {
			javascript = { "eslint_d" },
			typescript = { "eslint_d" },
			javascriptreact = { "eslint_d" },
			typescriptreact = { "eslint_d" },
			svelte = { "eslint_d" },
			python = { "ruff" },
			go = { "golangci-lint" },
			lua = { "luacheck" },
			sql = { "sqlfluff" },
			c = { "cppcheck" },
			cpp = { "cppcheck" },
			rust = { "clippy" },
		}

		local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
			group = lint_augroup,
			callback = function()
				-- 파일이 너무 크면 린팅 스킵 (성능 개선)
				local max_filesize = 100 * 1024 -- 100KB
				local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(0))
				if ok and stats and stats.size > max_filesize then
					return
				end

				lint.try_lint()
			end,
		})

		vim.keymap.set("n", "<leader>ll", function()
			lint.try_lint()
		end, { desc = "Lint current file" })
	end,
}
