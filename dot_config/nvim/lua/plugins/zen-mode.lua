-- 긴 글/블로그 작성용 집중 모드. <leader>z 로 방해요소 제거 + 커서 문단만 강조.
return {
	"folke/zen-mode.nvim",
	dependencies = { "folke/twilight.nvim" },
	cmd = "ZenMode",
	keys = {
		{ "<leader>z", "<cmd>ZenMode<cr>", desc = "Zen mode (집중 글쓰기)" },
	},
	opts = {
		window = {
			width = 90,
			options = {
				number = false,
				relativenumber = false,
				signcolumn = "no",
			},
		},
		plugins = {
			twilight = { enabled = true }, -- 켜면 커서 주변 문단만 밝게
			options = { laststatus = 0 }, -- 상태줄 숨김
		},
	},
}
