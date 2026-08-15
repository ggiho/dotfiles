-- Obsidian UI 기능(위키링크/문법 conceal 렌더링)에 필요한 conceallevel 설정.
-- 마크다운 파일에서만 적용해 다른 파일 타입엔 영향 없게 함.
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function()
		vim.opt_local.conceallevel = 2
	end,
})

return {
	"epwalsh/obsidian.nvim",
	version = "*", -- recommended, use latest release instead of latest commit
	lazy = true,
	ft = "markdown",
	-- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
	-- event = {
	--   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
	--   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
	--   -- refer to `:h file-pattern` for more examples
	--   "BufReadPre path/to/my-vault/*.md",
	--   "BufNewFile path/to/my-vault/*.md",
	-- },
	dependencies = {
		-- Required.
		"nvim-lua/plenary.nvim",

		-- see below for full list of optional dependencies 👇
	},
	-- 어디서든 노트를 만들고/찾고/열 수 있는 워크플로우 키맵 (누르면 플러그인 로드)
	keys = {
		{ "<leader>on", "<cmd>ObsidianNew<cr>", desc = "Obsidian: 새 노트" },
		{ "<leader>oo", "<cmd>ObsidianQuickSwitch<cr>", desc = "Obsidian: 노트 빠른 전환" },
		{ "<leader>os", "<cmd>ObsidianSearch<cr>", desc = "Obsidian: 내용 전문검색" },
		{ "<leader>ob", "<cmd>ObsidianBacklinks<cr>", desc = "Obsidian: 백링크" },
		{ "<leader>od", "<cmd>ObsidianToday<cr>", desc = "Obsidian: 오늘 데일리노트" },
		{ "<leader>ot", "<cmd>ObsidianTemplate<cr>", desc = "Obsidian: 템플릿 삽입" },
		{ "<leader>ol", "<cmd>ObsidianLink<cr>", mode = "v", desc = "Obsidian: 선택영역 링크" },
	},
	opts = {
		workspaces = {
			{
				name = "sb",
				path = vim.fn.expand("~") .. "/40_Notes",
			},
		},
		notes_subdir = "00 Inbox",
		new_notes_location = "notes_subdir",

		daily_notes = {
			folder = "00 Inbox",
			date_format = "%Y-%m-%d",
		},

		disable_frontmatter = true,
		templates = {
			subdir = "templates",
			date_format = "%Y-%m-%d",
			time_format = "%H:%M:%S",
		},

		-- key mappings
		mappings = {
			-- overrides the 'gf' mapping to work on markdown/wiki links within your vault
			["gf"] = {
				action = function()
					return require("obsidian").util.gf_passthrough()
				end,
				opts = { noremap = false, expr = true, buffer = true },
			},
			-- toggle check-boxes
			["<leader>ti"] = {
				action = function()
					return require("obsidian").util.toggle_checkbox()
				end,
				opts = { buffer = true },
			},
		},
		
		completion = {
			nvim_cmp = true,
			min_chars = 2,
		},
		
		ui = {
			-- Disable some things because you set these manually for all Markdown files using treesitter
			checkboxes = {},
			bullets = {},
		},
	},
}
