-- Kuroneko meetings in Neovim: browse, read, play, name voices, take notes,
-- keep links, check off pendências and summarize with Claude, all through
-- the `kuroneko` command.
local M = {}

local defaults = {
	-- The `kuroneko` command (installed with the app).
	cmd = "kuroneko",
	-- Keys in a meeting buffer; set one to false to leave it unmapped.
	keys = {},
	-- Keys in the pendências buffer (:Kuroneko tasks), the same way.
	tasks_keys = {},
	-- Options for the Telescope pickers, e.g. require("telescope.themes").get_dropdown().
	telescope = {},
}

local function highlights()
	local set = function(name, link)
		vim.api.nvim_set_hl(0, name, { link = link, default = true })
	end
	local speakers = { "Function", "String", "Constant", "Type", "Identifier", "Special", "Statement", "PreProc" }
	for index, link in ipairs(speakers) do
		set("KuronekoSpeaker" .. index, link)
	end
	set("KuronekoMe", "Title")
	set("KuronekoTime", "Comment")
	set("KuronekoNote", "DiagnosticWarn")
	set("KuronekoContext", "Comment")
	set("KuronekoPlaying", "Visual")
	set("KuronekoLink", "Underlined")
	set("KuronekoDone", "Comment")
end

function M.setup(opts)
	local config = vim.tbl_deep_extend("force", defaults, opts or {})
	require("kuroneko.cli").cmd = config.cmd
	local buffer = require("kuroneko.buffer")
	buffer.keys = vim.tbl_extend("force", buffer.keys, config.keys)
	local tasks = require("kuroneko.tasks")
	tasks.keys = vim.tbl_extend("force", tasks.keys, config.tasks_keys)
	require("kuroneko.picker").telescope = config.telescope
	highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("kuroneko_highlights", { clear = true }),
		callback = highlights,
	})
end

function M.meetings()
	require("kuroneko.picker").meetings()
end

function M.search(query)
	require("kuroneko.picker").search(query)
end

function M.open(id, at_ms)
	return require("kuroneko.buffer").open(id, at_ms)
end

function M.tasks()
	return require("kuroneko.tasks").open()
end

return M
