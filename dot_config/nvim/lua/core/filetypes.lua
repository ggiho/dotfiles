-- Custom filetype detection for extensionless config files.
-- ~/.config/mysql/hosts is a colon-delimited DB host list (name:host:port:user[:client:db])
-- with no extension, so Neovim leaves it filetype-less (no highlighting). Map it to a
-- dedicated `dbhosts` filetype backed by syntax/dbhosts.vim.
vim.filetype.add({
    pattern = {
        [".*/mysql/hosts"] = "dbhosts",
    },
})
