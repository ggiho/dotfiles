return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" }, -- if you use the mini.nvim suite
	-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.icons' }, -- if you use standalone mini plugins
	-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
	---@module 'render-markdown'
	---@type render.md.UserConfig
	opts = {
		heading = {
			-- 레벨별 전체 폭 배경 블록 제거 (눈 피로). 아이콘/글자 색은 유지.
			backgrounds = {},
		},
		bullet = {
			-- 레벨 순환(●○◆◇) 대신 ○ 하나로 통일
			icons = { "○" },
		},
	},
}
