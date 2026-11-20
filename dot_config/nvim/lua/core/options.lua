vim.cmd("let g:netrw_liststype = 3")

local opt = vim.opt

opt.relativenumber = true
opt.number = true

opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.autoindent = true

opt.wrap = false

opt.ignorecase = true
opt.smartcase = true

opt.cursorline = true

opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"

opt.scrolloff = 8

opt.backspace = "indent,eol,start"

opt.clipboard:append("unnamedplus")

opt.splitright = true
opt.splitbelow = true

-- tmux repaints the whole pane when synchronized output (?2026l) ends, which wipes the
-- kitty-protocol images image.nvim places through passthrough (WezTerm cell-attached images).
-- Disable termsync only inside tmux so images survive redraws.
if vim.env.TMUX then
    opt.termsync = false
end

-- Global wrap stays off for code; soft-wrap prose filetypes to the window width.
-- linebreak = break at word boundaries, breakindent = keep list/quote indent on wrap.
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown", "text", "gitcommit" },
    group = vim.api.nvim_create_augroup("core-prose-wrap", { clear = true }),
    callback = function()
        vim.opt_local.wrap = true
        vim.opt_local.linebreak = true
        vim.opt_local.breakindent = true
    end,
})
