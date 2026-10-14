-- Turns a meeting (the JSON of `kuroneko meeting <id>`) into buffer lines,
-- remembering what each line is so keys can act on it.
local time = require("kuroneko.time")

local M = {}

local speaker_groups = 8

--- Highlight group of a voice: "me" has its own, the others cycle.
function M.speaker_group(key)
	if key == "me" then
		return "KuronekoMe"
	end
	local cluster = tonumber((key or ""):match("^c(%d+)$")) or 0
	return "KuronekoSpeaker" .. (cluster % speaker_groups + 1)
end

local function document_title(kind)
	if kind == "summary" then
		return "Resumo"
	end
	return kind:sub(1, 1):upper() .. kind:sub(2)
end

local function squash(text)
	return vim.trim(((text or ""):gsub("%s+", " ")))
end

--- A summary line the way the command reads a pendência's text: without
--- the bracketed times and with spaces collapsed.
local function bare(line)
	return squash((line:gsub("%[[^%]]*%d:%d%d[^%]]*%]", " ")))
end

--- Line of the summary body (from 1) of each pendência: the one the
--- command says, if its text is there; else the first line with the text.
local function summary_tasks(meeting, body)
	local by_line = {}
	for _, item in ipairs(meeting.summaryItems or {}) do
		if item.kind == "task" and item.ref then
			local text = squash(item.text)
			local function holds(index)
				if text == "" then
					return false
				end
				return body[index] and not by_line[index] and bare(body[index]):find(text, 1, true)
			end
			local index = item.line and item.line + 1
			if not holds(index) then
				index = nil
				for i = 1, #body do
					if holds(i) then
						index = i
						break
					end
				end
			end
			if index then
				by_line[index] = item
			end
		end
	end
	return by_line
end

--- "github.com/o/r/pull/482" out of "https://github.com/o/r/pull/482/".
local function short_url(url)
	return (url:gsub("^%a[%w+.-]*://", ""):gsub("/$", ""))
end

--- Returns `lines`, `items` (line number → what it is) and `highlights`
--- ({ line, col_start, col_end, group }, 0-based columns). Items with
--- `open` hold a URL or file to open; with `task`, a pendência
--- ({ ref, done, … }) to check off.
function M.meeting(meeting)
	local lines, items, highlights = {}, {}, {}

	local function add(text, item)
		table.insert(lines, text)
		if item then
			items[#lines] = item
		end
		return #lines
	end

	add("# " .. meeting.title)
	local header = { time.day(meeting.startedAt) }
	if meeting.endedAt then
		header[1] = header[1] .. "–" .. time.hm(meeting.endedAt)
	end
	table.insert(header, time.duration(meeting.durationMs))
	local names = {}
	for _, voice in ipairs(meeting.voices or {}) do
		table.insert(names, voice.name)
	end
	if #names > 0 then
		table.insert(header, table.concat(names, ", "))
	end
	add(table.concat(vim.tbl_filter(function(part)
		return part and part ~= ""
	end, header), " · "))

	if #(meeting.links or {}) > 0 then
		add("")
		for _, link in ipairs(meeting.links) do
			local prefix = "🔗 "
			local label = link.label or link.title or short_url(link.url)
			local address = short_url(link.url)
			local text = prefix .. label .. (address ~= label and (" · " .. address) or "")
			local line = add(text, { type = "link", linkId = link.id, url = link.url, label = label, open = link.url })
			table.insert(highlights, { line, #prefix, #prefix + #label, "KuronekoLink" })
			table.insert(highlights, { line, #prefix + #label, -1, "KuronekoContext" })
		end
	end

	if meeting.status == "recording" then
		add("")
		add("> Gravando. A transcrição chega aos poucos, uns 2 minutos atrás da conversa.")
	elseif meeting.status ~= "done" then
		add("")
		add(meeting.status == "failed" and ("> A transcrição falhou: " .. (meeting.statusDetail or "erro desconhecido"))
			or "> Transcrição em andamento.")
	end

	for _, document in ipairs(meeting.documents or {}) do
		local item = { type = "document", kind = document.kind }
		local body = vim.split((document.body or ""):gsub("\r\n", "\n"), "\n", { plain = true })
		local first, last = 1, #body
		while first <= last and vim.trim(body[first]) == "" do
			first = first + 1
		end
		while last >= first and vim.trim(body[last]) == "" do
			last = last - 1
		end
		local tasks = document.kind == "summary" and summary_tasks(meeting, body) or {}
		add("")
		-- A summary from Claude already opens with its own "## Resumo".
		if not vim.trim(body[first] or ""):match("^#") then
			add("## " .. document_title(document.kind), item)
			add("")
		end
		for index = first, last do
			local text = body[index]
			if index == first then
				text = text:gsub("^%s+", "")
			end
			if index == last then
				text = text:gsub("%s+$", "")
			end
			local task = tasks[index]
			local line = add(text, task and { type = "document", kind = document.kind, task = task } or item)
			if task and task.done then
				table.insert(highlights, { line, 0, -1, "KuronekoDone" })
			end
		end
	end

	add("")
	add("## Transcrição")
	for _, entry in ipairs(meeting.timeline or {}) do
		add("")
		if entry.type == "note" then
			local at = entry.at and (" · " .. time.hm(entry.at)) or ""
			local item = {
				type = "note",
				noteId = entry.noteId,
				startMs = entry.startMs,
				playMs = entry.context and entry.context.startMs or entry.startMs,
			}
			local text = entry.text or ""
			-- A note tagged #acao is a pendência, checked off like the summary's.
			if vim.tbl_contains(entry.tags or {}, "acao") then
				item.task = { ref = "note:" .. entry.noteId, done = entry.resolvedAt ~= nil, text = text }
				text = (item.task.done and "[x] " or "[ ] ") .. text
			end
			local line = add(vim.trim("> 📝 [" .. time.clock(entry.startMs) .. at .. "] " .. text), item)
			table.insert(highlights, { line, 0, -1, item.task and item.task.done and "KuronekoDone" or "KuronekoNote" })
			-- Prints (and any other file) of the note, one per line.
			for _, attachment in ipairs(entry.attachments or {}) do
				local prefix = "> 📎 " .. (attachment.kind == "image" and "print" or "arquivo") .. ": "
				local file = vim.fs.basename(attachment.path)
				local file_line = add(prefix .. file, vim.tbl_extend("force", item, { open = attachment.path }))
				table.insert(highlights, { file_line, 0, #prefix, "KuronekoContext" })
				table.insert(highlights, { file_line, #prefix, -1, "KuronekoLink" })
			end
			if entry.context then
				local prefix = "> ↳ "
				local context = add(prefix .. entry.context.name .. " em " .. time.clock(entry.context.startMs)
					.. ": “" .. entry.context.excerpt .. "”", item)
				table.insert(highlights, { context, 0, -1, "KuronekoContext" })
				table.insert(highlights, { context, #prefix, #prefix + #entry.context.name, M.speaker_group(entry.context.speaker) })
			end
		else
			local stamp = "[" .. time.clock(entry.startMs) .. "] "
			local line = add(stamp .. entry.name .. ": " .. entry.text, {
				type = "speech",
				startMs = entry.startMs,
				endMs = entry.endMs,
				speaker = entry.speaker,
				name = entry.name,
			})
			table.insert(highlights, { line, 0, #stamp - 1, "KuronekoTime" })
			table.insert(highlights, { line, #stamp, #stamp + #entry.name, M.speaker_group(entry.speaker) })
		end
	end
	if #(meeting.timeline or {}) == 0 and meeting.status == "done" then
		add("")
		add("Ninguém falou nesta gravação.")
	end
	return lines, items, highlights
end

--- Automatic titles end in " · <date>", which is shown next to them.
function M.short_title(title)
	return title:match("^(.-) · %d") or title
end

--- The pendências of `kuroneko tasks` under the meeting each came from (the
--- command sends them newest meeting first, in the order of the recording).
--- Same returns as `meeting`; items are { type = "meeting", meetingId } or
--- { type = "task", task }.
function M.tasks(list)
	local lines, items, highlights = {}, {}, {}

	local function add(text, item)
		table.insert(lines, text)
		if item then
			items[#lines] = item
		end
		return #lines
	end

	add("# Pendências")
	if #list == 0 then
		add("")
		add("Nenhuma pendência aberta.")
		return lines, items, highlights
	end
	local meeting
	for _, task in ipairs(list) do
		if task.meetingId ~= meeting then
			meeting = task.meetingId
			add("")
			local day = time.day(task.meetingStartedAt)
			add("## " .. M.short_title(task.meetingTitle) .. (day ~= "" and (" · " .. day) or ""), {
				type = "meeting",
				meetingId = task.meetingId,
			})
		end
		local text = (task.done and "- [x] " or "- [ ] ") .. task.text
		if task.owner and task.owner ~= "" then
			text = text .. " — " .. task.owner
		end
		local stamp = #text
		if task.startMs then
			text = text .. " [" .. time.clock(task.startMs) .. "]"
		end
		local line = add(text, { type = "task", task = task })
		if task.done then
			table.insert(highlights, { line, 0, -1, "KuronekoDone" })
		elseif task.startMs then
			table.insert(highlights, { line, stamp + 1, -1, "KuronekoTime" })
		end
	end
	return lines, items, highlights
end

--- Line of the speech being heard at `ms`: the last one that started before.
function M.line_at(items, ms)
	local best, best_start
	for line, item in pairs(items) do
		if item.type == "speech" and item.startMs <= ms and (not best_start or item.startMs > best_start) then
			best, best_start = line, item.startMs
		end
	end
	return best
end

return M
