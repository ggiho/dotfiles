-- 마크다운에서만 conceallevel 적용 (위키링크/문법 렌더링용)
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function()
		vim.opt_local.conceallevel = 2
	end,
})

-- 볼트 노트 진입 시 버퍼-로컬 키맵 (포크는 :Obsidian 서브커맨드 방식)
vim.api.nvim_create_autocmd("User", {
	pattern = "ObsidianNoteEnter",
	callback = function(ev)
		vim.keymap.set("n", "<leader>ti", "<cmd>Obsidian toggle_checkbox<cr>", {
			buffer = ev.buf,
			desc = "Obsidian: 체크박스 토글",
		})
	end,
})

return {
	-- ⚠️ epwalsh/obsidian.nvim 은 유지보수 중단 → 커뮤니티 포크 사용
	"obsidian-nvim/obsidian.nvim",
	version = "*", -- 최신 릴리스 사용 (제거하면 latest commit)
	lazy = true,
	ft = "markdown",
	dependencies = {
		"nvim-lua/plenary.nvim",
	},
	-- 어디서든 노트를 만들고/찾고/열 수 있는 워크플로우 키맵 (누르면 플러그인 로드)
	keys = {
		{ "<leader>on", "<cmd>Obsidian new<cr>", desc = "Obsidian: 새 노트" },
		{ "<leader>oo", "<cmd>Obsidian quick_switch<cr>", desc = "Obsidian: 노트 빠른 전환" },
		{ "<leader>os", "<cmd>Obsidian search<cr>", desc = "Obsidian: 내용 전문검색" },
		{ "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Obsidian: 백링크" },
		{ "<leader>od", "<cmd>Obsidian today<cr>", desc = "Obsidian: 오늘 데일리노트" },
		{ "<leader>ot", "<cmd>Obsidian template<cr>", desc = "Obsidian: 템플릿 삽입" },
		{ "<leader>ol", "<cmd>Obsidian link<cr>", mode = "v", desc = "Obsidian: 선택영역 링크" },
	},
	opts = {
		legacy_commands = false, -- 구 :ObsidianNew 대신 :Obsidian new 서브커맨드 사용
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
			date_format = "YYYY-MM-DD", -- 포크는 moment식 토큰 (strftime 아님)
		},

		frontmatter = { enabled = false }, -- (구 disable_frontmatter=true)
		templates = {
			folder = "templates",
			date_format = "YYYY-MM-DD",
			time_format = "HH:mm",
		},

		-- 완성은 포크 4.0부터 내장 LSP(obsidian-ls)가 담당 (구 completion.nvim_cmp 제거).
		-- nvim-cmp로 받으려면 cmp-nvim-lsp 필요 (nvim-cmp.lua 참고).

		-- 렌더링은 render-markdown.nvim이 담당 → obsidian 자체 UI는 끔 (이중 렌더 방지)
		ui = { enable = false },
	},
}
