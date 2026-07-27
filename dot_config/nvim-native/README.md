# Neovim 0.12 native completion experiment

This isolated profile tests Neovim 0.12 completion without `nvim-cmp`,
LuaSnip, or any other plugin:

```sh
NVIM_APPNAME=nvim-native nvim path/to/file.lua
```

It reuses the general-purpose LSP definitions and Mason binaries from the main
`nvim` profile. Company-specific commands and plugins are intentionally not
loaded.

Completion controls:

- `Ctrl-Space`: request LSP completion
- `Ctrl-n` / `Ctrl-p`: navigate the popup
- `Ctrl-y` or `Enter`: accept
- `Tab` / `Shift-Tab`: navigate completion or an active LSP snippet

This profile is an evaluation target, not a replacement for the main config.
