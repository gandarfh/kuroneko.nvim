-- A meeting in a buffer: transcript, notes in the timeline and summary,
-- with keys to play, name voices, take notes and summarize.
local cli = require("kuroneko.cli")
local player = require("kuroneko.player")
local render = require("kuroneko.render")
local time = require("kuroneko.time")

local M = {}

-- Keys a read-only buffer has no use for, leaving motions and search
-- (/, n, ?, e, E…) alone.
M.keys = {
	play = "<CR>",
	stop = "x",
	rename = "r",
	note = "a",
	delete_note = "D",
	summarize = "S",
	edit_summary = "gS",
	next_note = "]n",
	prev_note = "[n",
	reload = "R",
	close = "q",
	help = "g?",
}

--- How often a meeting still being recorded is reloaded.
M.refresh_ms = 30000

local ns = vim.api.nvim_create_namespace("kuroneko")
local meetings = {} -- buf → { id, meeting, items }
local following = {} -- buf → true while a reload is scheduled

local function notify(message, level)
	vim.notify("Kuroneko: " .. message, level or vim.log.levels.INFO)
end

local function bufname(id)
	return "kuroneko://" .. id
end

--- The buffer named exactly `name`, or -1: `bufnr()` takes a pattern, so
--- "kuroneko://12" would also find "kuroneko://123".
local function find_buf(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
	return -1
end

--- What the cursor is on: the item of its line, or of the nearest one above.
local function item_at_cursor(buf)
	local state = meetings[buf]
	if not state then
		return nil
	end
	local line = vim.api.nvim_win_get_cursor(0)[1]
	for l = line, 1, -1 do
		if state.items[l] then
			return state.items[l], l
		end
	end
end

local function paint(buf, lines, highlights)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, hl in ipairs(highlights) do
		local line, from, to, group = hl[1], hl[2], hl[3], hl[4]
		local text = lines[line] or ""
		vim.api.nvim_buf_set_extmark(buf, ns, line - 1, from, {
			end_col = to == -1 and #text or math.min(to, #text),
			hl_group = group,
		})
	end
end

local function jump_to(buf, ms)
	local state = meetings[buf]
	local line = state and render.line_at(state.items, ms)
	if line and vim.api.nvim_get_current_buf() == buf then
		vim.api.nvim_win_set_cursor(0, { line, 0 })
		vim.cmd("normal! zz")
	end
end

local follow

function M.load(buf, id, at_ms)
	cli.run({ "meeting", tostring(id) }, nil, function(meeting, err)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		if not meeting then
			return notify(err, vim.log.levels.ERROR)
		end
		local lines, items, highlights = render.meeting(meeting)
		local cursor = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0) or nil
		meetings[buf] = { id = id, meeting = meeting, items = items }
		paint(buf, lines, highlights)
		if at_ms then
			jump_to(buf, at_ms)
		elseif cursor then
			pcall(vim.api.nvim_win_set_cursor, 0, { math.min(cursor[1], #lines), cursor[2] })
		end
		follow(buf, meeting)
	end)
end

--- While a meeting is recorded (and finished right after), its transcript
--- grows every couple of minutes: the buffer keeps up on its own while shown.
follow = function(buf, meeting)
	if meeting.status == "done" or meeting.status == "failed" or following[buf] then
		return
	end
	following[buf] = true
	vim.defer_fn(function()
		following[buf] = nil
		local state = meetings[buf]
		if not (state and vim.api.nvim_buf_is_valid(buf)) then
			return
		end
		if vim.fn.bufwinid(buf) == -1 then
			return follow(buf, state.meeting)
		end
		M.load(buf, state.id)
	end, M.refresh_ms)
end

local function reload(buf)
	local state = meetings[buf]
	if state then
		M.load(buf, state.id)
	end
end

-- Actions ------------------------------------------------------------------

--- Where playing from the cursor starts: the speech line, the subject of a
--- note, or a [mm:ss] cited in the summary.
local function play_position(buf, item, line)
	if item.type == "document" then
		local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
		local col = vim.api.nvim_win_get_cursor(0)[2] + 1
		local best, best_distance
		for start, stamp in text:gmatch("()%[(%d[%d:]*:%d%d)%]") do
			local distance = math.abs(start - col)
			if not best_distance or distance < best_distance then
				best, best_distance = time.parse_clock(stamp), distance
			end
		end
		return best
	end
	return item.playMs or item.startMs
end

local function play(buf)
	local item, line = item_at_cursor(buf)
	local ms = item and play_position(buf, item, line)
	if not ms then
		return notify("nada para tocar nesta linha")
	end
	local state = meetings[buf]
	player.play(state.id, ms, buf, function(position)
		return render.line_at(state.items, position)
	end)
end

local function choose_name(callback)
	cli.run({ "people" }, nil, function(people)
		local names = vim.tbl_map(function(person)
			return person.name
		end, people or {})
		if #names == 0 then
			return vim.ui.input({ prompt = "Quem é essa voz? " }, callback)
		end
		table.insert(names, "Outro nome…")
		vim.ui.select(names, { prompt = "Quem é essa voz?" }, function(choice)
			if choice == "Outro nome…" then
				vim.ui.input({ prompt = "Nome: " }, callback)
			else
				callback(choice)
			end
		end)
	end)
end

local function rename(buf)
	local item = item_at_cursor(buf)
	if not (item and item.type == "speech") then
		return notify("ponha o cursor numa fala")
	end
	if item.speaker == "me" then
		return notify("essa voz é você (o seu microfone)")
	end
	local state = meetings[buf]
	choose_name(function(name)
		if not name or vim.trim(name) == "" then
			return
		end
		cli.run({ "name", tostring(state.id), item.speaker, vim.trim(name) }, nil, function(_, err)
			if err then
				return notify(err, vim.log.levels.ERROR)
			end
			notify(item.name .. " agora é " .. vim.trim(name))
			reload(buf)
		end)
	end)
end

local function add_note(buf)
	local state = meetings[buf]
	local item = item_at_cursor(buf)
	-- While listening, the note goes where the audio is.
	local ms = player.position(state.id) or (item and (item.startMs or item.playMs))
	if not ms then
		return notify("ponha o cursor numa fala para marcar o momento")
	end
	vim.ui.input({ prompt = "Nota em " .. time.clock(ms) .. ": " }, function(text)
		if not text or vim.trim(text) == "" then
			return
		end
		cli.run({ "note", "add", tostring(state.id), "--at", math.floor(ms) .. "ms", text }, nil, function(_, err)
			if err then
				return notify(err, vim.log.levels.ERROR)
			end
			reload(buf)
		end)
	end)
end

local function delete_note(buf)
	local item = item_at_cursor(buf)
	if not (item and item.type == "note") then
		return notify("ponha o cursor numa nota")
	end
	if vim.fn.confirm("Apagar esta nota?", "&Sim\n&Não", 2) ~= 1 then
		return
	end
	cli.run({ "note", "rm", tostring(item.noteId) }, nil, function(_, err)
		if err then
			return notify(err, vim.log.levels.ERROR)
		end
		reload(buf)
	end)
end

local function summarize(buf)
	local state = meetings[buf]
	notify("gerando o resumo com o Claude…")
	cli.run({ "summarize", tostring(state.id) }, nil, function(_, err)
		if err then
			return notify(err, vim.log.levels.ERROR)
		end
		notify("resumo pronto")
		reload(buf)
	end)
end

--- The summary in its own buffer; :w saves it back.
local function edit_summary(buf)
	local state = meetings[buf]
	local body = ""
	for _, document in ipairs(state.meeting.documents or {}) do
		if document.kind == "summary" then
			body = document.body
		end
	end
	local name = bufname(state.id) .. "/resumo"
	local edit = find_buf(name)
	if edit == -1 then
		edit = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(edit, name)
	end
	vim.cmd("split")
	vim.api.nvim_win_set_buf(0, edit)
	vim.bo[edit].buftype = "acwrite"
	vim.bo[edit].filetype = "markdown"
	vim.bo[edit].swapfile = false
	vim.api.nvim_buf_set_lines(edit, 0, -1, false, vim.split(body, "\n", { plain = true }))
	vim.bo[edit].modified = false
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = edit,
		callback = function()
			local text = table.concat(vim.api.nvim_buf_get_lines(edit, 0, -1, false), "\n")
			cli.run({ "doc", "set", tostring(state.id), "summary" }, { stdin = text }, function(_, err)
				if err then
					return notify(err, vim.log.levels.ERROR)
				end
				vim.bo[edit].modified = false
				notify("resumo salvo")
				reload(buf)
			end)
		end,
	})
end

local function jump_note(buf, direction)
	local state = meetings[buf]
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local target
	for l, item in pairs(state.items) do
		if item.type == "note" and state.items[l - 1] ~= item then
			if direction > 0 and l > line and (not target or l < target) then
				target = l
			elseif direction < 0 and l < line and (not target or l > target) then
				target = l
			end
		end
	end
	if target then
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end
end

local function help()
	local k = M.keys
	notify(table.concat({
		k.play .. "  tocar daqui (na nota: o assunto; no resumo: o [mm:ss])",
		k.stop .. "  parar",
		k.rename .. "  dizer quem é a voz da fala",
		k.note .. "  nova nota neste momento (ou onde o áudio está)",
		k.delete_note .. "  apagar a nota",
		k.summarize .. "  gerar o resumo com o Claude",
		k.edit_summary .. "  editar o resumo (:w salva)",
		k.next_note .. " / " .. k.prev_note .. "  próxima / anterior nota",
		k.reload .. "  recarregar",
		k.close .. "  fechar",
	}, "\n"))
end

local function map(buf)
	local actions = {
		play = play,
		stop = function()
			player.stop()
		end,
		rename = rename,
		note = add_note,
		delete_note = delete_note,
		summarize = summarize,
		edit_summary = edit_summary,
		next_note = function(b)
			jump_note(b, 1)
		end,
		prev_note = function(b)
			jump_note(b, -1)
		end,
		reload = reload,
		close = function(b)
			player.stop()
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

--- Opens meeting `id`, optionally scrolled to `at_ms`.
function M.open(id, at_ms)
	local name = bufname(id)
	local buf = find_buf(name)
	local fresh = buf == -1
	if fresh then
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
				meetings[buf] = nil
				following[buf] = nil
			end,
		})
	end
	vim.api.nvim_set_current_buf(buf)
	vim.wo.wrap = true
	vim.wo.linebreak = true
	vim.wo.breakindent = true
	vim.wo.signcolumn = "yes:1"
	if fresh or not meetings[buf] then
		M.load(buf, id, at_ms)
	elseif at_ms then
		jump_to(buf, at_ms)
		reload(buf)
	else
		reload(buf)
	end
	return buf
end

--- Meeting shown in `buf`, if it is a Kuroneko buffer.
function M.current(buf)
	return meetings[buf or vim.api.nvim_get_current_buf()]
end

M.summarize = summarize
M.reload = reload

return M
