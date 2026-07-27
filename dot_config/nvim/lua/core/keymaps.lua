vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

map("i", "lk", "<Esc>", { desc = "Exit insert mode" })
map("n", "<leader>nh", "<cmd>nohlsearch<CR>", { desc = "Clear search highlights" })

map("n", "J", "mzJ`z", { desc = "Join lines without moving cursor" })
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down and center" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up and center" })
map("n", "n", "nzzzv", { desc = "Next search result and center" })
map("n", "N", "Nzzzv", { desc = "Previous search result and center" })

map("x", "J", ":move '>+1<CR>gv=gv", { desc = "Move selection down" })
map("x", "K", ":move '<-2<CR>gv=gv", { desc = "Move selection up" })
map("x", "<", "<gv", { desc = "Indent left and reselect" })
map("x", ">", ">gv", { desc = "Indent right and reselect" })
map("x", "p", '"_dP', { desc = "Paste without replacing yank" })

map("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bb", "<cmd>buffer #<CR>", { desc = "Alternate buffer" })
map("n", "<leader>bd", function()
	require("mini.bufremove").delete(0, false)
end, { desc = "Delete buffer" })
map("n", "<leader>bD", function()
	require("mini.bufremove").delete(0, true)
end, { desc = "Delete buffer (force)" })

map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write file" })
map("n", "<leader>wq", "<cmd>wq<CR>", { desc = "Write and quit" })
map("n", "<leader>q", "<cmd>quit!<CR>", { desc = "Quit window (force)" })
map("n", "<leader>re", "<cmd>restart<CR>", { desc = "Restart Neovim" })

map("n", "<leader>fp", function()
	local path = vim.fn.expand("%:.")
	if path == "" then
		vim.notify("Current buffer has no file path", vim.log.levels.WARN)
		return
	end
	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path)
end, { desc = "Copy relative file path" })

map("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = "Replace word in buffer" })

-- Increment / decrement numbers
map("n", "<leader>+", "<C-a>", { desc = "Increment number" })
map("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

-- Black-hole register: delete/change without clobbering the yank register
map({ "n", "x" }, "<leader>d", '"_d', { desc = "Delete to black hole" })
map({ "n", "x" }, "c", '"_c', { desc = "Change without yanking" })
map("n", "x", '"_x', { desc = "Delete char without yanking" })

-- Disable Ex mode
map("n", "Q", "<nop>", { desc = "Disable Ex mode" })

vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight yanked text",
	group = vim.api.nvim_create_augroup("core-highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})
