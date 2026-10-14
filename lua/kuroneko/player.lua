-- One meeting playing at a time, through `kuroneko play`; the line being
-- heard is highlighted in the meeting buffer.
local cli = require("kuroneko.cli")

local M = {}

local ns = vim.api.nvim_create_namespace("kuroneko_playing")
local current -- { job, id, buf, positionMs }

local function clear()
	if current and vim.api.nvim_buf_is_valid(current.buf) then
		vim.api.nvim_buf_clear_namespace(current.buf, ns, 0, -1)
	end
end

local function mark(line)
	if not (current and vim.api.nvim_buf_is_valid(current.buf)) then
		return
	end
	vim.api.nvim_buf_clear_namespace(current.buf, ns, 0, -1)
	if line then
		vim.api.nvim_buf_set_extmark(current.buf, ns, line - 1, 0, {
			line_hl_group = "KuronekoPlaying",
			sign_text = "▶",
			sign_hl_group = "KuronekoPlaying",
		})
	end
end

--- Plays meeting `id` from `ms`; `line_at(ms)` says which buffer line to mark.
function M.play(id, ms, buf, line_at)
	M.stop()
	local state = { id = id, buf = buf, positionMs = ms }
	current = state
	state.job = cli.play({ tostring(id), "--at", math.floor(ms) .. "ms" }, function(position)
		if current ~= state then
			return
		end
		state.positionMs = position
		mark(line_at(position))
	end, function(err)
		if current == state then
			clear()
			current = nil
		end
		if err then
			vim.notify("Kuroneko: " .. err, vim.log.levels.ERROR)
		end
	end)
	if not state.job then
		current = nil
	end
end

function M.stop()
	if current then
		local job = current.job
		clear()
		current = nil
		if job then
			pcall(job.kill, job, 15)
		end
	end
end

--- Position being heard in meeting `id`, if it is playing.
function M.position(id)
	if current and current.id == id then
		return current.positionMs
	end
end

return M
