return {
	{
		"nvim-mini/mini.nvim",
		version = false,
		dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
		config = function()
			require("mini.ai").setup({ n_lines = 500 })
			require("mini.bufremove").setup()

			require("ts_context_commentstring").setup({ enable_autocmd = false })
			require("mini.comment").setup({
				options = {
					custom_commentstring = function()
						return require("ts_context_commentstring.internal").calculate_commentstring({
							key = "commentstring",
						}) or vim.bo.commentstring
					end,
				},
			})

			local diff = require("mini.diff")
			diff.setup({ view = { style = "sign" } })
			vim.keymap.set("n", "<leader>go", diff.toggle_overlay, { desc = "Toggle diff overlay" })
			vim.keymap.set("n", "<leader>gs", function()
				return diff.operator("apply") .. "gh"
			end, { desc = "Stage current hunk", expr = true, remap = true })
			vim.keymap.set("n", "<leader>gr", function()
				return diff.operator("reset") .. "gh"
			end, { desc = "Reset current hunk", expr = true, remap = true })

			local files = require("mini.files")
			files.setup({
				options = {
					permanent_delete = false,
					use_as_default_explorer = true,
				},
				windows = {
					max_number = 3,
					preview = true,
					width_focus = 30,
					width_nofocus = 15,
					width_preview = 40,
				},
			})

			local function toggle_files(path)
				if files.get_explorer_state() then
					files.close()
					return
				end
				files.open(path)
			end

			vim.keymap.set("n", "<leader>e", function()
				local path = vim.api.nvim_buf_get_name(0)
				if path == "" or vim.bo.buftype ~= "" then
					path = vim.uv.cwd()
				end
				toggle_files(path)
			end, { desc = "Explore current file" })
			vim.keymap.set("n", "<leader>E", function()
				toggle_files(vim.uv.cwd())
			end, { desc = "Explore working directory" })

			require("mini.splitjoin").setup()
			require("mini.surround").setup()

			local trailspace = require("mini.trailspace")
			trailspace.setup({ only_in_normal_buffers = true })
			vim.keymap.set("n", "<leader>cw", function()
				trailspace.trim()
				trailspace.trim_last_lines()
			end, { desc = "Clean trailing whitespace" })

			local clue = require("mini.clue")
			clue.setup({
				triggers = {
					{ mode = "n", keys = "<Leader>" },
					{ mode = "x", keys = "<Leader>" },
					{ mode = "i", keys = "<C-x>" },
					{ mode = "n", keys = "g" },
					{ mode = "x", keys = "g" },
					{ mode = "n", keys = "[" },
					{ mode = "n", keys = "]" },
					{ mode = "n", keys = "'" },
					{ mode = "n", keys = "`" },
					{ mode = "x", keys = "'" },
					{ mode = "x", keys = "`" },
					{ mode = "n", keys = '"' },
					{ mode = "x", keys = '"' },
					{ mode = "i", keys = "<C-r>" },
					{ mode = "c", keys = "<C-r>" },
					{ mode = "n", keys = "<C-w>" },
					{ mode = "n", keys = "z" },
					{ mode = "x", keys = "z" },
				},
				clues = {
					{ mode = "n", keys = "<Leader>b", desc = "+Buffers" },
					{ mode = "n", keys = "<Leader>c", desc = "+Code" },
					{ mode = "n", keys = "<Leader>f", desc = "+Find" },
					{ mode = "n", keys = "<Leader>g", desc = "+Git" },
					{ mode = "n", keys = "<Leader>l", desc = "+Language" },
					clue.gen_clues.square_brackets(),
					clue.gen_clues.builtin_completion(),
					clue.gen_clues.g(),
					clue.gen_clues.marks(),
					clue.gen_clues.registers(),
					clue.gen_clues.windows(),
					clue.gen_clues.z(),
				},
				window = {
					config = { border = "rounded" },
					delay = 400,
				},
			})
		end,
	},
}
