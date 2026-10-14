-- Choosing a meeting or a search hit: Telescope when installed (with the
-- transcript as preview), vim.ui.select otherwise.
local buffer = require("kuroneko.buffer")
local cli = require("kuroneko.cli")
local time = require("kuroneko.time")

local M = {}

M.telescope = {}

local function notify(message, level)
	vim.notify("Kuroneko: " .. message, level or vim.log.levels.INFO)
end

--- Automatic titles end in " · <date>", which the list already shows.
local function short_title(title)
	return title:match("^(.-) · %d") or title
end

local function describe(meeting)
	local parts = { meeting.week, time.day(meeting.startedAt), short_title(meeting.title) }
	if #meeting.people > 0 then
		table.insert(parts, table.concat(meeting.people, ", "))
	end
	if meeting.noteCount > 0 then
		table.insert(parts, meeting.noteCount == 1 and "1 nota" or (meeting.noteCount .. " notas"))
	end
	if vim.tbl_contains(meeting.documents, "summary") then
		table.insert(parts, "resumo")
	end
	if meeting.status ~= "done" then
		table.insert(parts, meeting.status == "failed" and "falhou" or "transcrevendo")
	end
	return table.concat(parts, " │ ")
end

local function pick(items, opts)
	local ok = pcall(require, "telescope")
	if not ok then
		return vim.ui.select(items, { prompt = opts.title, format_item = opts.display }, function(choice)
			if choice then
				opts.on_choice(choice)
			end
		end)
	end
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local previewers = require("telescope.previewers")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values
	local previews = {}

	pickers
		.new(M.telescope, {
			prompt_title = opts.title,
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					local display = opts.display(item)
					return { value = item, display = display, ordinal = display }
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Transcrição",
				define_preview = function(self, entry)
					local id = opts.meeting_id(entry.value)
					previews[id] = previews[id] or cli.run_sync({ "transcript", tostring(id) }, { raw = true }) or ""
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(previews[id], "\n", { plain = true }))
					vim.bo[self.state.bufnr].filetype = "markdown"
					vim.wo[self.state.winid].wrap = true
					vim.wo[self.state.winid].linebreak = true
				end,
			}),
			attach_mappings = function(prompt)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt)
					if entry then
						opts.on_choice(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.meetings()
	cli.run({ "meetings" }, nil, function(list, err)
		if not list then
			return notify(err, vim.log.levels.ERROR)
		end
		if #list == 0 then
			return notify("nenhuma reunião gravada ainda")
		end
		pick(list, {
			title = "Reuniões",
			display = describe,
			meeting_id = function(meeting)
				return meeting.id
			end,
			on_choice = function(meeting)
				buffer.open(meeting.id)
			end,
		})
	end)
end

function M.search(query)
	local function run(text)
		if not text or vim.trim(text) == "" then
			return
		end
		cli.run({ "search", text }, nil, function(hits, err)
			if not hits then
				return notify(err, vim.log.levels.ERROR)
			end
			if #hits == 0 then
				return notify("nada encontrado para “" .. text .. "”")
			end
			pick(hits, {
				title = "Busca: " .. text,
				display = function(hit)
					local who = hit.type == "note" and "📝" or hit.name
					return string.format("%s │ %s %s: %s", short_title(hit.meetingTitle), time.clock(hit.startMs), who, hit.text)
				end,
				meeting_id = function(hit)
					return hit.meetingId
				end,
				on_choice = function(hit)
					buffer.open(hit.meetingId, hit.startMs)
				end,
			})
		end)
	end
	if query and query ~= "" then
		run(query)
	else
		vim.ui.input({ prompt = "Buscar nas reuniões: " }, run)
	end
end

return M
