-- Force the macOS input source to English for Normal mode so hjkl / Alt-hjkl
-- work regardless of the previous IME. Insert mode is left untouched — toggle
-- Korean manually when needed (reliable IME restore would need TemporaryWindow.app).
-- Requires `macism` (brew install macism).

if vim.fn.has("mac") == 0 or vim.fn.executable("macism") == 0 then
	return
end

local english = "com.apple.keylayout.ABC"

vim.api.nvim_create_autocmd({ "InsertLeave", "VimEnter", "FocusGained" }, {
	group = vim.api.nvim_create_augroup("core-ime-switch", { clear = true }),
	callback = function()
		vim.system({ "macism", english })
	end,
})
