-- A fake `kuroneko` command answering from tests/fixtures, and stubs for
-- everything that would leave Neovim (prompts, the browser, the player).
local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

--- A fixture decoded the way the plugin decodes the command's output.
function H.fixture(name)
	local text = table.concat(vim.fn.readfile(H.root .. "/tests/fixtures/" .. name .. ".json"), "\n")
	return vim.json.decode(text, { luanil = { object = true, array = true } })
end

local pending = 0

local cli = require("kuroneko.cli")

--- Records the arguments and answers from `H.routes[verb](args, opts)`,
--- on the main loop like the real command.
cli.run = function(args, opts, callback)
	table.insert(H.calls, vim.deepcopy(args))
	local route = H.routes[args[1]]
	local value, err
	if route then
		value, err = route(args, opts)
	else
		err = "unexpected command in test: " .. table.concat(args, " ")
	end
	pending = pending + 1
	vim.schedule(function()
		pending = pending - 1
		callback(value, err)
	end)
end

cli.run_sync = function(args)
	table.insert(H.calls, vim.deepcopy(args))
	return ""
end

local player = require("kuroneko.player")
player.play = function(id, ms, buf, line_at)
	table.insert(H.played, { id = id, ms = ms, buf = buf, line = line_at(ms) })
end
player.stop = function()
	H.stopped = H.stopped + 1
end
player.position = function()
	return nil
end

vim.ui.input = function(opts, on_confirm)
	table.insert(H.prompts, opts.prompt)
	on_confirm(table.remove(H.answers, 1))
end
vim.ui.select = function(items, opts, on_choice)
	H.selected = { items = items, opts = opts }
	on_choice(nil)
end
vim.ui.open = function(target)
	table.insert(H.opened, target)
	return nil, nil
end
vim.fn.confirm = function()
	return H.confirm
end
vim.notify = function(message)
	table.insert(H.messages, message)
end

--- Fresh state and no buffers between tests; every verb answers with a
--- fixture unless a test says otherwise.
function H.reset()
	vim.cmd("silent! %bwipeout!")
	H.calls, H.played, H.prompts, H.answers, H.opened, H.messages = {}, {}, {}, {}, {}, {}
	H.stopped, H.confirm, H.selected = 0, 1, nil
	H.routes = {
		meeting = function()
			return H.fixture("meeting")
		end,
		meetings = function()
			return H.fixture("meetings")
		end,
		tasks = function()
			return H.fixture("tasks")
		end,
	}
end

--- Runs what the fake command answered, and what that triggered.
function H.flush()
	vim.wait(1000, function()
		return pending == 0
	end, 5)
end

--- Types `keys` in normal mode, mappings included.
function H.press(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
	H.flush()
end

function H.lines(buf)
	return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

--- Number of the first line containing `text`.
function H.line_of(text, buf)
	for number, line in ipairs(H.lines(buf)) do
		if line:find(text, 1, true) then
			return number
		end
	end
	error("no line with " .. vim.inspect(text) .. " in:\n" .. table.concat(H.lines(buf), "\n"), 2)
end

--- Puts the cursor on the first line containing `text`.
function H.cursor_on(text)
	vim.api.nvim_win_set_cursor(0, { H.line_of(text), 0 })
end

--- Calls the fake command got whose first word is `verb`.
function H.calls_to(verb)
	return vim.tbl_filter(function(args)
		return args[1] == verb
	end, H.calls)
end

function H.eq(expected, actual, message)
	if not vim.deep_equal(expected, actual) then
		error((message and (message .. ": ") or "") .. "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
	end
end

function H.ok(value, message)
	if not value then
		error(message or "expected a true value", 2)
	end
	return value
end

return H
