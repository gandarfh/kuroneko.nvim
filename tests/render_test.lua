local test, H = ...
local render = require("kuroneko.render")

local function index_of(lines, text)
	for number, line in ipairs(lines) do
		if line:find(text, 1, true) then
			return number
		end
	end
end

test("render: links near the top, one line each with the label", function()
	local lines, items = render.meeting(H.fixture("meeting"))
	H.eq("🔗 PR #482 · github.com/gandarfh/kuroneko/pull/482", lines[4])
	H.eq("🔗 Plano do Q4 · notion.so/Plano-Q4", lines[5])
	H.eq({
		type = "link",
		linkId = 3,
		url = "https://github.com/gandarfh/kuroneko/pull/482",
		label = "PR #482",
		open = "https://github.com/gandarfh/kuroneko/pull/482",
	}, items[4])
	H.eq(4, items[5].linkId)
	H.ok(index_of(lines, "## Resumo") > 5, "links come before the summary")
end)

test("render: a link whose label is its address shows it once", function()
	local meeting = H.fixture("meeting")
	meeting.links = { { id = 1, url = "https://notion.so/Plano", label = "notion.so/Plano" } }
	local lines = render.meeting(meeting)
	H.eq("🔗 notion.so/Plano", lines[4])
end)

test("render: a note with a print and no text shows a line per file", function()
	local lines, items = render.meeting(H.fixture("meeting"))
	local note = index_of(lines, "📝 [00:30")
	H.ok(lines[note]:match("^> 📝 %[00:30 · %d%d:%d%d%]$"), "empty note text leaves no trailing space: " .. lines[note])
	H.eq("> 📎 print: print 1.png", lines[note + 1])
	local print = items[note + 1]
	H.eq("note", print.type)
	H.eq(41, print.noteId)
	H.eq("/tmp/kuroneko-test/meetings/7/attachments/print 1.png", print.open)
	H.eq(nil, items[note].open, "the note line itself opens nothing")
	H.ok(lines[note + 2]:find("↳ Ana em 00:00", 1, true), "context follows the prints")
end)

test("render: summary pendências map to their lines, with ref", function()
	local lines, items = render.meeting(H.fixture("meeting"))
	H.eq("## Resumo", lines[7], "leading blank lines of the body are dropped")
	local open = index_of(lines, "- [ ] Revisar o PR")
	H.eq("summary:7:8:1a2b3c4d", items[open].task.ref)
	H.eq(false, items[open].task.done)
	H.eq("document", items[open].type)
	local done = index_of(lines, "- [x] Mandar a ata")
	H.eq("summary:7:9:5e6f7a8b", items[done].task.ref)
	H.eq(true, items[done].task.done)
	H.eq(nil, items[index_of(lines, "- Lançar em novembro")].task, "a decisão is not a pendência")
end)

test("render: a pendência whose line moved is found by its text", function()
	local meeting = H.fixture("meeting")
	meeting.summaryItems[2].line = 2
	meeting.summaryItems[3].line = 40
	local lines, items = render.meeting(meeting)
	H.eq("summary:7:8:1a2b3c4d", items[index_of(lines, "Revisar o PR")].task.ref)
	H.eq("summary:7:9:5e6f7a8b", items[index_of(lines, "Mandar a ata")].task.ref)
	H.eq(nil, items[index_of(lines, "Combinaram o plano")].task)
end)

test("render: a pendência with a time inside the text still matches", function()
	local meeting = H.fixture("meeting")
	meeting.documents[1].body = "## Pendências\n- [ ] Revisar  [12:31] o PR — Ana\n"
	meeting.summaryItems = {
		{ kind = "task", text = "Revisar o PR", owner = "Ana", startMs = 751000, done = false, line = 1, ref = "summary:7:1:abc" },
	}
	local lines, items = render.meeting(meeting)
	H.eq("summary:7:1:abc", items[index_of(lines, "Revisar  [12:31]")].task.ref)
end)

test("render: a #acao note is a pendência, checked when resolved", function()
	local meeting = H.fixture("meeting")
	local lines, items = render.meeting(meeting)
	local line = index_of(lines, "ligar pro fornecedor")
	H.ok(lines[line]:find("] [ ] ligar pro fornecedor #acao", 1, true), lines[line])
	H.eq({ ref = "note:42", done = false, text = "ligar pro fornecedor #acao" }, items[line].task)

	meeting.timeline[4].resolvedAt = "2026-10-14T14:00:00Z"
	lines, items = render.meeting(meeting)
	line = index_of(lines, "ligar pro fornecedor")
	H.ok(lines[line]:find("] [x] ligar pro fornecedor", 1, true), lines[line])
	H.eq(true, items[line].task.done)
end)

test("render: pendências grouped by meeting, with owner and time", function()
	local lines, items = render.tasks(H.fixture("tasks"))
	H.eq("# Pendências", lines[1])
	H.eq("", lines[2])
	H.ok(lines[3]:match("^## Planejamento do Q4 · qua 14/10 %d%d:%d%d$"), lines[3])
	H.eq({ type = "meeting", meetingId = 7 }, items[3])
	H.eq("- [ ] Revisar o PR — Você [01:00]", lines[4])
	H.eq("summary:7:8:1a2b3c4d", items[4].task.ref)
	H.eq("- [ ] ligar pro fornecedor — você [01:35]", lines[5])
	H.eq("", lines[6])
	H.ok(lines[7]:match("^## Daily · ter 13/10 %d%d:%d%d$"), "automatic titles lose their date: " .. lines[7])
	H.eq("- [ ] Atualizar o ticket ABC-123", lines[8], "no owner nor time")
	H.eq(8, #lines)
end)

test("render: no pendências", function()
	local lines, items = render.tasks({})
	H.eq({ "# Pendências", "", "Nenhuma pendência aberta." }, lines)
	H.eq({}, items)
end)
