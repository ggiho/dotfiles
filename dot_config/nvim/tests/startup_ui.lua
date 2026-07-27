local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

assert(
	vim.uv.fs_stat(config_root .. "/lua/plugins/smear-cursor.lua") == nil,
	"smear-cursor must stay removed because it corrupts the startup dashboard"
)

print("startup UI regression checks passed")
