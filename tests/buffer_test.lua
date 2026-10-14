local test, H = ...
local buffer = require("kuroneko.buffer")

local function open_meeting(id)
	local buf = require("kuroneko").open(id or 7)
	H.flush()
	return buf
end

test("buffer: opens the meeting with links, prints and summary", function()
	local buf = open_meeting()
	H.eq("kuroneko://7", vim.api.nvim_buf_get_name(buf))
	H.eq({ "meeting", "7" }, H.calls[1])
	H.line_of("🔗 PR #482")
	H.line_of("> 📎 print: print 1.png")
	H.line_of("- [ ] Revisar o PR — Você [01:00]")
end)

test("buffer: meeting 12 is not the buffer of meeting 123", function()
	local big = open_meeting(123)
	local small = open_meeting(12)
	H.ok(big ~= small, "two buffers")
	H.eq("kuroneko://12", vim.api.nvim_buf_get_name(small))
	H.eq({ "meeting", "12" }, H.calls[#H.calls])
end)

test("buffer: <CR> on a link opens it", function()
	open_meeting()
	H.cursor_on("🔗 Plano do Q4")
	H.press("<CR>")
	H.eq({ "https://notion.so/Plano-Q4" }, H.opened)
	H.eq({}, H.played)
end)

test("buffer: a link only counts on its own line", function()
	open_meeting()
	vim.api.nvim_win_set_cursor(0, { H.line_of("🔗 Plano do Q4") + 1, 0 })
	H.press("<CR>")
	H.eq({}, H.opened)
	H.eq({}, H.played)
	H.eq("Kuroneko: nada para tocar nesta linha", H.messages[#H.messages])
end)

test("buffer: <CR> on a print opens the image", function()
	local image = vim.fn.tempname() .. ".png"
	vim.fn.writefile({}, image)
	H.routes.meeting = function()
		local meeting = H.fixture("meeting")
		meeting.timeline[2].attachments[1].path = image
		return meeting
	end
	open_meeting()
	H.cursor_on("📎 print:")
	H.press("<CR>")
	H.eq({ image }, H.opened)
end)

test("buffer: a print missing on disk is not handed to the system", function()
	open_meeting()
	H.cursor_on("📎 print:")
	H.press("<CR>")
	H.eq({}, H.opened)
	H.ok(H.messages[#H.messages]:find("arquivo não encontrado", 1, true), H.messages[#H.messages])
end)

test("buffer: <CR> elsewhere still plays from the line", function()
	local buf = open_meeting()
	H.cursor_on("Eu reviso o PR hoje")
	H.press("<CR>")
	H.eq({ { id = 7, ms = 60000, buf = buf, line = H.line_of("Eu reviso o PR hoje") } }, H.played)
	H.cursor_on("- [ ] Revisar o PR")
	H.press("<CR>")
	H.eq(60000, H.played[2].ms, "the [mm:ss] of the summary line")
end)

test("buffer: toggling a summary pendência runs task done|undo with its ref", function()
	H.routes.task = function()
		return {}
	end
	open_meeting()
	H.cursor_on("- [ ] Revisar o PR")
	H.press("c")
	H.eq({ { "task", "done", "summary:7:8:1a2b3c4d" } }, H.calls_to("task"))
	H.eq({ "meeting", "7" }, H.calls[#H.calls], "reloads after")
	H.cursor_on("- [x] Mandar a ata")
	H.press("c")
	H.eq({ "task", "undo", "summary:7:9:5e6f7a8b" }, H.calls_to("task")[2])
end)

test("buffer: toggling a #acao note uses its note ref", function()
	H.routes.task = function()
		return {}
	end
	open_meeting()
	H.cursor_on("ligar pro fornecedor")
	H.press("c")
	H.eq({ { "task", "done", "note:42" } }, H.calls_to("task"))
end)

test("buffer: toggle outside a pendência does nothing", function()
	open_meeting()
	H.cursor_on("- Lançar em novembro")
	H.press("c")
	H.cursor_on("Eu reviso o PR hoje")
	H.press("c")
	H.eq({}, H.calls_to("task"))
end)

test("buffer: a toggle error is shown and nothing reloads", function()
	H.routes.task = function()
		return nil, "pendência não encontrada: summary:7:8:1a2b3c4d (o resumo mudou?)"
	end
	open_meeting()
	local before = #H.calls
	H.cursor_on("- [ ] Revisar o PR")
	H.press("c")
	H.eq(before + 1, #H.calls)
	H.eq("Kuroneko: pendência não encontrada: summary:7:8:1a2b3c4d (o resumo mudou?)", H.messages[#H.messages])
end)

test("buffer: toggling refreshes an open pendências buffer", function()
	H.routes.task = function()
		return {}
	end
	require("kuroneko").tasks()
	H.flush()
	open_meeting()
	H.cursor_on("- [ ] Revisar o PR")
	H.press("c")
	H.eq(2, #H.calls_to("tasks"))
end)

test("buffer: gl adds a link with an optional title", function()
	H.routes.link = function(args)
		return { id = 9, url = args[4], label = args[5] or "example.com/doc", createdAt = "2026-10-14T13:00:00Z" }
	end
	open_meeting()
	H.answers = { "https://example.com/doc", "Doc do projeto" }
	H.press("gl")
	H.eq({ { "link", "add", "7", "https://example.com/doc", "Doc do projeto" } }, H.calls_to("link"))
	H.eq("Kuroneko: link guardado: Doc do projeto", H.messages[#H.messages])
	H.eq({ "meeting", "7" }, H.calls[#H.calls])

	H.answers = { " github.com/o/r/pull/9 ", "" }
	H.press("gl")
	H.eq({ "link", "add", "7", "github.com/o/r/pull/9" }, H.calls_to("link")[2])

	H.answers = {}
	H.press("gl")
	H.eq(2, #H.calls_to("link"), "cancelled")
end)

test("buffer: D removes the link under the cursor", function()
	H.routes.link = function(args)
		return { removed = tonumber(args[3]) }
	end
	open_meeting()
	vim.api.nvim_win_set_cursor(0, { H.line_of("🔗 Plano do Q4") + 1, 0 })
	H.press("D")
	H.eq({}, H.calls_to("link"), "not from the line below")
	H.cursor_on("🔗 Plano do Q4")
	H.confirm = 2
	H.press("D")
	H.eq({}, H.calls_to("link"))
	H.confirm = 1
	H.press("D")
	H.eq({ { "link", "rm", "4" } }, H.calls_to("link"))
end)

test("buffer: D on a print removes its note", function()
	H.routes.note = function()
		return { removed = 41 }
	end
	open_meeting()
	H.cursor_on("📎 print:")
	H.press("D")
	H.eq({ { "note", "rm", "41" } }, H.calls_to("note"))
end)

test("buffer: ]n skips the print and context lines of a note", function()
	open_meeting()
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	H.press("]n")
	H.eq(H.line_of("📝 [00:30"), vim.api.nvim_win_get_cursor(0)[1])
	H.press("]n")
	H.eq(H.line_of("ligar pro fornecedor"), vim.api.nvim_win_get_cursor(0)[1])
	H.press("[n")
	H.eq(H.line_of("📝 [00:30"), vim.api.nvim_win_get_cursor(0)[1])
end)

test("buffer: g? lists the new keys and skips unmapped ones", function()
	open_meeting()
	H.press("g?")
	local help = H.messages[#H.messages]
	H.ok(help:find("gl  guardar um link", 1, true), help)
	H.ok(help:find("c  marcar a pendência como feita", 1, true), help)
	H.ok(help:find("D  apagar a nota ou o link", 1, true), help)

	local keys = buffer.keys
	buffer.keys = vim.tbl_extend("force", keys, { link = false })
	vim.cmd("silent! %bwipeout!")
	open_meeting()
	H.press("g?")
	buffer.keys = keys
	help = H.messages[#H.messages]
	H.ok(not help:find("guardar um link", 1, true), help)
	H.eq("", vim.fn.maparg("gl", "n"), "unmapped")
end)

test(":Kuroneko lists meetings with their open pendências", function()
	vim.cmd("Kuroneko")
	H.flush()
	H.ok(H.selected, "a picker was shown")
	local format = H.selected.opts.format_item
	H.ok(format(H.selected.items[1]):find("│ 2 pendências", 1, true), format(H.selected.items[1]))
	H.ok(format(H.selected.items[2]):find("│ 1 pendência", 1, true), format(H.selected.items[2]))
	H.ok(format(H.selected.items[2]):find("│ Daily │", 1, true), format(H.selected.items[2]))
end)

test(":Kuroneko open, search, summarize and stop still work", function()
	H.routes.search = function()
		return { { meetingId = 7, meetingTitle = "Planejamento do Q4", startMs = 60000, type = "speech", name = "Você", text = "Eu reviso o PR hoje." } }
	end
	H.routes.summarize = function()
		return { kind = "summary", body = "## Resumo", updatedAt = "2026-10-14T13:00:00Z" }
	end
	vim.cmd("Kuroneko open 7")
	H.flush()
	H.eq("kuroneko://7", vim.api.nvim_buf_get_name(0))
	vim.cmd("Kuroneko summarize")
	H.flush()
	H.eq({ { "summarize", "7" } }, H.calls_to("summarize"))
	vim.cmd("Kuroneko stop")
	H.eq(1, H.stopped)
	vim.cmd("Kuroneko search revisar o PR")
	H.flush()
	H.eq({ { "search", "revisar o PR" } }, H.calls_to("search"))
	H.eq(1, #H.selected.items)
end)

test(":Kuroneko completes its subcommands, tasks included", function()
	H.eq({ "tasks" }, vim.fn.getcompletion("Kuroneko t", "cmdline"))
	H.eq({ "open", "search", "stop", "summarize", "tasks" }, vim.fn.getcompletion("Kuroneko ", "cmdline"))
end)
