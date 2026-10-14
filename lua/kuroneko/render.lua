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

--- Returns `lines`, `items` (line number → what it is) and `highlights`
--- ({ line, col_start, col_end, group }, 0-based columns).
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
		local body = vim.split(vim.trim(document.body), "\n", { plain = true })
		add("")
		-- A summary from Claude already opens with its own "## Resumo".
		if not (body[1] or ""):match("^#") then
			add("## " .. document_title(document.kind), item)
			add("")
		end
		for _, line in ipairs(body) do
			add(line, item)
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
			local line = add("> 📝 [" .. time.clock(entry.startMs) .. at .. "] " .. entry.text, item)
			table.insert(highlights, { line, 0, -1, "KuronekoNote" })
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
