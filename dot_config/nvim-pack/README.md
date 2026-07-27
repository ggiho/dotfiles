# Neovim 0.12 vim.pack experiment

This profile exercises the built-in package manager without changing the main
`lazy.nvim` setup:

```sh
NVIM_APPNAME=nvim-pack nvim
```

It intentionally contains only three plugins already used by the main config:
`plenary.nvim`, `telescope.nvim`, and `nvim-treesitter`. This is enough to
verify dependency ordering, the lockfile, a plugin update hook, and the new
Treesitter setup without migrating unrelated or company-specific commands.

Use `:packupdate` to review updates and write the confirmation buffer to apply
them. This profile is an evaluation target, not a replacement for the main
config.
