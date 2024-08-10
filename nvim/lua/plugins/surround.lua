-- require {
--     "kylechui/nvim-surround",
--     version = "*", -- Use for stability; omit to use `main` branch for the latest features
--     event = "VeryLazy",
--     config = function()
--         require("nvim-surround").setup({
--             -- Configuration here, or leave empty to use defaults
--         })
--     end
-- }

return {
  "kylechui/nvim-surround",
  event = { "BufReadPre", "BufNewFile" },
  version = "*", -- Use for stability; omit to use `main` branch for the latest features
  config = true,
}
