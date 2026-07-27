return {
	"goolord/alpha-nvim",
	event = "VimEnter",
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		-- MySQL dolphin (Sakila)
		local dolphin = {
			[==[                                 __]==],
			[==[                              _.-~  )]==],
			[==[                   _..--~~~~,'   ,-/     _]==],
			[==[                .-'. . . .'   ,-','    ,' )]==],
			[==[              ,'. . . _   ,--~,-'__..-'  ,']==],
			[==[            ,'. . .  (@)' ---~~~~      ,']==],
			[==[           /. . . . '~~             ,-']==],
			[==[          /. . . . .             ,-']==],
			[==[         ; . . . .  - .        ,']==],
			[==[        : . . . .       _     /]==],
			[==[       . . . . .          `-.:]==],
			[==[      . . . ./  - .          )]==],
			[==[     .  . . |  _____..---.._/ ____]==],
			[==[~---~~~~----~~~~             ~~]==],
		}
		local dolphin_n = #dolphin
		do
			local w = 0
			for _, l in ipairs(dolphin) do
				w = math.max(w, vim.fn.strdisplaywidth(l))
			end
			for i, l in ipairs(dolphin) do
				dolphin[i] = l .. string.rep(" ", w - vim.fn.strdisplaywidth(l))
			end
		end
		local header_val = { "" }
		for _, l in ipairs(dolphin) do
			table.insert(header_val, l)
		end
		vim.list_extend(header_val, { "", "Welcome to Neovim!", "" })
		dashboard.section.header.val = header_val

		-- Grouped menu (Files / Search / Tools)
		local function btn(sc, txt, kb)
			local b = dashboard.button(sc, txt, kb)
			b.opts.width = 24
			b.opts.hl = "AlphaButton"
			b.opts.hl_shortcut = "AlphaShortcut"
			return b
		end

		local menu_files = {
			btn("f", "  Find file", ":Telescope find_files<CR>"),
			btn("r", "  Recent files", ":Telescope oldfiles<CR>"),
			btn("n", "  New file", ":ene <BAR> startinsert<CR>"),
		}
		local menu_search = {
			btn("g", "  Find text", ":Telescope live_grep<CR>"),
			btn("t", "  Find TODOs", ":TodoTelescope<CR>"),
		}
		local menu_tools = {
			btn("c", "  Config", ":Telescope find_files cwd=" .. vim.fn.stdpath("config") .. "<CR>"),
			btn("l", "  Lazy", ":Lazy<CR>"),
			btn("q", "  Quit", ":qa<CR>"),
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

		-- Catppuccin gradient header: mauve -> lavender -> blue
		local grad_stops = { "#cba6f7", "#b4befe", "#89b4fa" }
		local function set_header_hl()
			local function hx(h)
				return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
			end
			local m = #grad_stops
			for i = 1, dolphin_n do
				local p = dolphin_n > 1 and (i - 1) / (dolphin_n - 1) or 0
				local seg = p * (m - 1)
				local idx = math.min(math.floor(seg), m - 2)
				local t = seg - idx
				local r1, g1, b1 = hx(grad_stops[idx + 1])
				local r2, g2, b2 = hx(grad_stops[idx + 2])
				local c = string.format(
					"#%02x%02x%02x",
					math.floor(r1 + (r2 - r1) * t + 0.5),
					math.floor(g1 + (g2 - g1) * t + 0.5),
					math.floor(b1 + (b2 - b1) * t + 0.5)
				)
				vim.api.nvim_set_hl(0, "AlphaDb" .. i, { fg = c, bold = true })
			end
			vim.api.nvim_set_hl(0, "AlphaDbCap", { fg = grad_stops[m], bold = true })
			vim.api.nvim_set_hl(0, "AlphaHeading", { fg = "#6c7086", bold = true })
			vim.api.nvim_set_hl(0, "AlphaButton", { fg = "#cdd6f4" })
			vim.api.nvim_set_hl(0, "AlphaShortcut", { fg = "#cba6f7", bold = true })
		end
		set_header_hl()
		vim.api.nvim_create_autocmd("ColorScheme", { callback = set_header_hl })

		local header_hl = {}
		for i = 1, #dashboard.section.header.val do
			local d = i - 1 -- header[1] is a spacer; dolphin lines follow
			local grp = (d >= 1 and d <= dolphin_n) and ("AlphaDb" .. d) or "AlphaDbCap"
			header_hl[i] = { { grp, 0, -1 } }
		end
		dashboard.section.header.opts.hl = header_hl

		-- Clean centered menu, lightly grouped by spacing
		local function bgroup(buttons)
			return { type = "group", val = buttons, opts = { spacing = 0 } }
		end

		dashboard.opts.layout = {
			{ type = "padding", val = 2 },
			dashboard.section.header,
			{ type = "padding", val = 2 },
			bgroup(menu_files),
			{ type = "padding", val = 1 },
			bgroup(menu_search),
			{ type = "padding", val = 1 },
			bgroup(menu_tools),
			{ type = "padding", val = 2 },
			dashboard.section.footer,
		}

		dashboard.opts.opts.noautocmd = true
		alpha.setup(dashboard.opts)

		-- Disable statusline in alpha
		vim.api.nvim_create_autocmd("User", {
			pattern = "AlphaReady",
			desc = "disable status and tablines for alpha",
			callback = function()
				-- alpha builds its buffer with noautocmd, so the FileType guard can
				-- miss the first render; kill trailing-whitespace highlight here.
				vim.b.minitrailspace_disable = true
				pcall(function()
					require("mini.trailspace").unhighlight()
				end)

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

