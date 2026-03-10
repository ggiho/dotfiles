local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.font_size = 14
config.font = wezterm.font("JetBrainsMono Nerd Font")
config.automatically_reload_config = true
config.enable_tab_bar = false
config.window_decorations = "RESIZE"
config.adjust_window_size_when_changing_font_size = false
config.harfbuzz_features = { "calt=0" }
config.max_fps = 120
config.enable_kitty_graphics = true
config.window_close_confirmation = "NeverPrompt"
config.window_background_opacity = 0.9
config.macos_window_background_blur = 12
config.audible_bell = "Disabled"
config.initial_cols = 120
config.initial_rows = 45

-- tmux 자동 실행 설정
config.default_prog = { "zsh", "--login" }

-- 창 여백 설정
config.window_padding = {
	left = 18,
	right = 15,
	top = 20,
	bottom = 5,
}

config.keys = {
	{
		key = "LeftArrow",
		mods = "OPT",
		action = wezterm.action.SendKey({ key = "b", mods = "ALT" }),
	},
	{
		key = "RightArrow",
		mods = "OPT",
		action = wezterm.action.SendKey({ key = "f", mods = "ALT" }),
	},
	-- Ctrl+L: clear current line then clear screen
	{
		key = "l",
		mods = "CTRL",
		action = wezterm.action.SendString("\x15clear\n"),
	},
	-- Cmd+K: clear current line then clear screen
	{
		key = "k",
		mods = "CMD",
		action = wezterm.action.SendString("\x15clear\n"),
	},
}

-- 색상 팔레트: Catppuccin Mocha
config.colors = {
	foreground = "#cdd6f4",
	background = "#1e1e2e",
	cursor_bg = "#cdd6f4",
	cursor_fg = "#1e1e2e",
	cursor_border = "#cdd6f4",
	selection_bg = "#585b70",
	selection_fg = "#cdd6f4",
	ansi = {
		"#11111b",
		"#f38ba8",
		"#a6e3a1",
		"#f9e2af",
		"#89b4fa",
		"#cba6f7",
		"#8cabcf",
		-- "#89dceb",
		"#bac2de",
	},
	brights = {
		"#45475a",
		"#eba0ac",
		"#94e2d5",
		"#fab387",
		"#b4befe",
		"#f5c2e7",
		"#8cabcf",
		"#cdd6f4",
	},
	-- 추가 사용자 정의 색상
	indexed = {
		[16] = "#fab387",
		[17] = "#74c7ec",
	},
}

return config
