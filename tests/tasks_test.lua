local test, H = ...
local tasks = require("kuroneko.tasks")

local function open_tasks()
	vim.cmd("Kuroneko tasks")
	H.flush()
	return vim.api.nvim_get_current_buf()
end

--- `kuroneko task done|undo` answers with the TaskItem changed.
local function answer_tasks()
	H.routes.task = function(args)
		for _, task in ipairs(H.fixture("tasks")) do
			if task.ref == args[3] then
				task.done = args[2] == "done"
				task.doneAt = task.done and "2026-10-14T15:00:00Z" or nil
				return task
			end
		end
		return nil, "pendência não encontrada: " .. args[3]
	end
end

test("tasks: :Kuroneko tasks lists open pendências by meeting", function()
	local buf = open_tasks()
	H.eq("kuroneko://tasks", vim.api.nvim_buf_get_name(buf))
	H.eq({ { "tasks" } }, H.calls)
	H.eq("# Pendências", H.lines()[1])
	H.line_of("## Planejamento do Q4 · qua 14/10")
	H.line_of("- [ ] Revisar o PR — Você [01:00]")
	H.line_of("## Daily · ter 13/10")
	H.eq(false, vim.bo[buf].modifiable)
end)

test("tasks: toggling checks the pendência off and back on", function()
	answer_tasks()
	open_tasks()
	H.cursor_on("Revisar o PR")
	H.press("c")
	H.eq({ { "task", "done", "summary:7:8:1a2b3c4d" } }, H.calls_to("task"))
	H.line_of("- [x] Revisar o PR — Você [01:00]")
	H.eq(1, #H.calls_to("tasks"), "stays listed until a reload")
	H.press("c")
	H.eq({ "task", "undo", "summary:7:8:1a2b3c4d" }, H.calls_to("task")[2])
	H.line_of("- [ ] Revisar o PR — Você [01:00]")
	H.cursor_on("ligar pro fornecedor")
	H.press("c")
	H.eq({ "task", "done", "note:42" }, H.calls_to("task")[3])
end)

test("tasks: toggling reloads the meeting buffer if it is open", function()
	answer_tasks()
	require("kuroneko").open(7)
	H.flush()
	open_tasks()
	H.cursor_on("Revisar o PR")
	H.press("c")
	H.eq(2, #H.calls_to("meeting"))
end)

test("tasks: toggle off a pendência does nothing", function()
	open_tasks()
	H.cursor_on("## Daily")
	H.press("c")
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	H.press("c")
	H.eq({}, H.calls_to("task"))
	H.eq("Kuroneko: ponha o cursor numa pendência", H.messages[#H.messages])
end)

test("tasks: <CR> opens the meeting at the moment of the pendência", function()
	open_tasks()
	H.cursor_on("Revisar o PR")
	H.press("<CR>")
	H.eq("kuroneko://7", vim.api.nvim_buf_get_name(0))
	H.eq(H.line_of("[01:00] Você: Eu reviso o PR hoje."), vim.api.nvim_win_get_cursor(0)[1])
end)

test("tasks: <CR> on a meeting heading opens the meeting", function()
	open_tasks()
	H.cursor_on("## Daily")
	H.press("<CR>")
	H.eq("kuroneko://5", vim.api.nvim_buf_get_name(0))
	H.eq({ "meeting", "5" }, H.calls[#H.calls])
end)

test("tasks: p plays the meeting from that moment", function()
	local buf = open_tasks()
	H.cursor_on("ligar pro fornecedor")
	H.press("p")
	H.eq({ { id = 7, ms = 95000, buf = buf, line = H.line_of("ligar pro fornecedor") } }, H.played)
	H.cursor_on("Atualizar o ticket")
	H.press("p")
	H.eq(1, #H.played, "no moment, nothing to play")
	H.press("x")
	H.eq(1, H.stopped)
end)

test("tasks: R fetches again, q closes", function()
	local buf = open_tasks()
	H.press("R")
	H.eq(2, #H.calls_to("tasks"))
	H.press("q")
	H.eq(false, vim.api.nvim_buf_is_valid(buf))
end)

test("tasks: an error of the command is shown", function()
	H.routes.tasks = function()
		return nil, "o banco do Kuroneko não abriu"
	end
	open_tasks()
	H.eq("Kuroneko: o banco do Kuroneko não abriu", H.messages[#H.messages])
end)

test("tasks: g? and keys from setup", function()
	local keys = tasks.keys
	require("kuroneko").setup({ tasks_keys = { toggle_task = "<Space>", play = false } })
	open_tasks()
	H.eq("", vim.fn.maparg("p", "n"))
	H.ok(vim.fn.maparg("<Space>", "n") ~= "" or vim.fn.maparg(" ", "n") ~= "", "toggle on <Space>")
	H.press("g?")
	local help = H.messages[#H.messages]
	H.ok(help:find("<Space>  marcar como feita", 1, true), help)
	H.ok(not help:find("tocar a reunião", 1, true), help)
	tasks.keys = keys
end)
