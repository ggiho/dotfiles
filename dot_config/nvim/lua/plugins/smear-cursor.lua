return {
	"sphamba/smear-cursor.nvim",
	opts = {
		stiffness = 0.5,
		trailing_stiffness = 0.49,
		never_draw_over_target = false,
		-- Force cursor color to match Catppuccin theme cursor
		-- cursor_color = nil, -- explicitly set to nil to use default
		-- Alternative options:
		-- cursor_color = "none", -- matches text color at cursor position
		-- cursor_color = "#f5e0dc", -- Catppuccin mocha rosewater color
	},
}
