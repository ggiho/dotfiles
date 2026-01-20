return {
	"folke/noice.nvim",
	event = "VeryLazy",
	opts = {
		-- cmdline 자동완성 설정 추가
		cmdline = {
			enabled = true,
			view = "cmdline_popup", -- 중앙 팝업 스타일
			opts = {
				-- 팝업 크기 및 위치 설정
				position = {
					row = "50%",
					col = "50%",
				},
				size = {
					width = 60,
					height = "auto",
				},
				border = {
					style = "single",
					padding = { 0, 1 },
				},
				win_options = {
					winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder",
				},
			},
		},
		-- 명령어 자동완성 활성화
		popupmenu = {
			enabled = true,
			backend = "nui", -- "nui" 또는 "cmp" 선택
		},
		presets = {
			bottom_search = true,
			command_palette = false,
			long_message_to_split = true,
			inc_rename = false,
			lsp_doc_border = true,
		},
	},
	dependencies = {
		"MunifTanjim/nui.nvim",
		{
			"rcarriga/nvim-notify",
			lazy = true,
			event = "VeryLazy",
			config = function()
				require("notify").setup({
					background_colour = "#1e1e2e",
					fps = 120,
					render = "minimal",
					timeout = 3000,
				})
				vim.notify = require("notify")
			end,
		},
	},
}
