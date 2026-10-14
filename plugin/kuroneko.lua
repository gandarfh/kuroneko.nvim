if vim.g.loaded_kuroneko then
	return
end
vim.g.loaded_kuroneko = true

local subcommands = {
	open = function(args)
		local id = tonumber(args[1])
		if not id then
			return vim.notify("Kuroneko: uso :Kuroneko open <id>", vim.log.levels.WARN)
		end
		require("kuroneko").open(id)
	end,
	search = function(args)
		require("kuroneko").search(table.concat(args, " "))
	end,
	summarize = function()
		local buffer = require("kuroneko.buffer")
		if not buffer.current() then
			return vim.notify("Kuroneko: abra uma reunião primeiro", vim.log.levels.WARN)
		end
		buffer.summarize(vim.api.nvim_get_current_buf())
	end,
	stop = function()
		require("kuroneko.player").stop()
	end,
	tasks = function()
		require("kuroneko").tasks()
	end,
}

vim.api.nvim_create_user_command("Kuroneko", function(command)
	local args = command.fargs
	local name = table.remove(args, 1)
	if not name then
		return require("kuroneko").meetings()
	end
	local run = subcommands[name]
	if not run then
		return vim.notify("Kuroneko: subcomando desconhecido: " .. name, vim.log.levels.WARN)
	end
	run(args)
end, {
	nargs = "*",
	desc = "Reuniões do Kuroneko",
	complete = function(lead, line)
		if #vim.split(line, "%s+") > 2 then
			return {}
		end
		local names = vim.tbl_filter(function(name)
			return name:find(lead, 1, true) == 1
		end, vim.tbl_keys(subcommands))
		table.sort(names)
		return names
	end,
})
