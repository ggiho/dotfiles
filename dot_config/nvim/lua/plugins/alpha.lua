return {
	"goolord/alpha-nvim",
	event = "VimEnter",
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		-- Custom GIHO ASCII art (simple and clean)
		dashboard.section.header.val = {
			[[                                                  ]],
			[[                                                  ]],
			[[         ██████╗ ██╗██╗  ██╗ ██████╗             ]],
			[[        ██╔════╝ ██║██║  ██║██╔═══██╗            ]],
			[[        ██║  ███╗██║███████║██║   ██║            ]],
			[[        ██║   ██║██║██╔══██║██║   ██║            ]],
			[[        ╚██████╔╝██║██║  ██║╚██████╔╝            ]],
			[[         ╚═════╝ ╚═╝╚═╝  ╚═╝ ╚═════╝             ]],
			[[                                                  ]],
			[[               Welcome to Neovim!                ]],
			[[                                                  ]],
		}

		-- Menu buttons
		dashboard.section.buttons.val = {
			dashboard.button("f", "  Find file", ":Telescope find_files <CR>"),
			dashboard.button("e", "  New file", ":ene <BAR> startinsert <CR>"),
			dashboard.button("p", "  Find project", ":Telescope projects <CR>"),
			dashboard.button("r", "  Recently used files", ":Telescope oldfiles <CR>"),
			dashboard.button("t", "  Find text", ":Telescope live_grep <CR>"),
			dashboard.button("c", "  Configuration", ":e $MYVIMRC <CR>"),
			dashboard.button("q", "  Quit Neovim", ":qa<CR>"),
		}

		-- Footer
		local function footer()
			local total_plugins = #vim.tbl_keys(require("lazy").plugins())
			local datetime = os.date(" %Y-%m-%d   %H:%M:%S")
			local version = vim.version()
			local nvim_version_info = "   v" .. version.major .. "." .. version.minor .. "." .. version.patch

			return datetime .. "   " .. total_plugins .. " plugins" .. nvim_version_info
		end

		dashboard.section.footer.val = footer()

		-- Styling
		dashboard.section.footer.opts.hl = "Type"
		dashboard.section.header.opts.hl = "Include"
		dashboard.section.buttons.opts.hl = "Keyword"

		dashboard.opts.opts.noautocmd = true
		alpha.setup(dashboard.opts)

		-- Disable statusline in alpha
		vim.api.nvim_create_autocmd("User", {
			pattern = "AlphaReady",
			desc = "disable status and tablines for alpha",
			callback = function()
				local prev_showtabline = vim.opt.showtabline
				local prev_status = vim.opt.laststatus
				vim.opt.showtabline = 0
				vim.opt.laststatus = 0
				vim.api.nvim_create_autocmd("BufUnload", {
					pattern = "<buffer>",
					callback = function()
						vim.opt.laststatus = prev_status
						vim.opt.showtabline = prev_showtabline
					end,
				})
			end,
		})
	end,
}

