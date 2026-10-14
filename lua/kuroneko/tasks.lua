-- The open pendências of every meeting in one buffer (kuroneko://tasks),
-- under the meeting each came from: check them off, open the meeting at
-- that moment or listen from there.
local buffer = require("kuroneko.buffer")
local cli = require("kuroneko.cli")
local player = require("kuroneko.player")
local render = require("kuroneko.render")

local M = {}

M.keys = {
	open = "<CR>",
	toggle_task = "c",
	play = "p",
	stop = "x",
	reload = "R",
	close = "q",
	help = "g?",
}

local name = "kuroneko://tasks"
local shown = {} -- buf → { list, items }

local function notify(message, level)
	vim.notify("Kuroneko: " .. message, level or vim.log.levels.INFO)
end

local function show(buf, list)
	local lines, items, highlights = render.tasks(list)
	local cursor = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0) or nil
	shown[buf] = { list = list, items = items }
	buffer.paint(buf, lines, highlights)
	if cursor then
		pcall(vim.api.nvim_win_set_cursor, 0, { math.min(cursor[1], #lines), cursor[2] })
	end
end

local function load(buf)
	cli.run({ "tasks" }, nil, function(list, err)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		if not list then
			return notify(err, vim.log.levels.ERROR)
		end
		show(buf, list)
	end)
end

--- The item of the cursor's line: a pendência or a meeting heading.
local function item_at_cursor(buf)
	local state = shown[buf]
	local line = vim.api.nvim_win_get_cursor(0)[1]
	return state and state.items[line], line
end

local function task_at_cursor(buf)
	local item, line = item_at_cursor(buf)
	if not (item and item.type == "task") then
		return notify("ponha o cursor numa pendência")
	end
	return item.task, line
end

local function open(buf)
	local item = item_at_cursor(buf)
	if item and item.type == "meeting" then
		return buffer.open(item.meetingId)
	end
	local task = task_at_cursor(buf)
	if task then
		buffer.open(task.meetingId, task.startMs)
	end
end

--- Checks the pendência off (or back on). It stays listed, checked, until
--- the next reload: `kuroneko tasks` only lists the open ones.
local function toggle(buf)
	local task = task_at_cursor(buf)
	if not task then
		return
	end
	local done = not task.done
	cli.run({ "task", done and "done" or "undo", task.ref }, nil, function(updated, err)
		if err then
			return notify(err, vim.log.levels.ERROR)
		end
		for key, value in pairs(type(updated) == "table" and updated or {}) do
			task[key] = value
		end
		task.done = done
		if vim.api.nvim_buf_is_valid(buf) and shown[buf] then
			show(buf, shown[buf].list)
		end
		buffer.reload_meeting(task.meetingId)
	end)
end

local function play(buf)
	local task, line = task_at_cursor(buf)
	if not task then
		return
	end
	if not task.startMs then
		return notify("essa pendência não tem o momento da reunião")
	end
	player.play(task.meetingId, task.startMs, buf, function()
		return line
	end)
end

local function help()
	local k = M.keys
	notify(buffer.key_help({
		{ { k.open }, "abrir a reunião no momento da pendência" },
		{ { k.toggle_task }, "marcar como feita (ou reabrir)" },
		{ { k.play }, "tocar a reunião desse momento" },
		{ { k.stop }, "parar" },
		{ { k.reload }, "recarregar (some com as feitas)" },
		{ { k.close }, "fechar" },
	}))
end

local function map(buf)
	local actions = {
		open = open,
		toggle_task = toggle,
		play = play,
		stop = function()
			player.stop()
		end,
		reload = load,
		close = function(b)
			vim.api.nvim_buf_delete(b, { force = true })
		end,
		help = help,
	}
	for action, lhs in pairs(M.keys) do
		if lhs and actions[action] then
			vim.keymap.set("n", lhs, function()
				actions[action](buf)
			end, { buffer = buf, nowait = true, desc = "Kuroneko: " .. action })
		end
	end
end

--- Shows the open pendências, fetched again.
function M.open()
	local buf = buffer.find_buf(name)
	if buf == -1 then
		buf = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_name(buf, name)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "hide"
		vim.bo[buf].swapfile = false
		vim.bo[buf].filetype = "markdown"
		vim.bo[buf].modifiable = false
		map(buf)
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			callback = function()
				shown[buf] = nil
			end,
		})
	end
	vim.api.nvim_set_current_buf(buf)
	vim.wo.wrap = true
	vim.wo.linebreak = true
	vim.wo.breakindent = true
	vim.wo.signcolumn = "yes:1"
	load(buf)
	return buf
end

--- Fetches the list again if it is open (a pendência changed elsewhere).
function M.refresh()
	local buf = buffer.find_buf(name)
	if buf ~= -1 and shown[buf] then
		load(buf)
	end
end

return M
