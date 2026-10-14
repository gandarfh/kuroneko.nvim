-- Talks to the `kuroneko` command, the only way the plugin touches meetings:
-- everything it prints is JSON (except `transcript`).
local M = {}

M.cmd = "kuroneko"

local install_hint = "comando kuroneko não encontrado; instale com:\n"
	.. "curl -fsSL https://github.com/gandarfh/kuroneko/releases/latest/download/install.sh | sh"

local function decode(text)
	local ok, value = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
	if not ok then
		return nil, "resposta inválida do kuroneko"
	end
	return value
end

local function failure(result)
	local message = vim.trim(result.stderr or ""):gsub("^kuroneko: ", "")
	return message ~= "" and message or ("kuroneko saiu com código " .. result.code)
end

--- Runs `kuroneko <args>` in the background; `callback(value, err)` runs on
--- the main loop. `opts.raw` skips JSON decoding, `opts.stdin` feeds input.
function M.run(args, opts, callback)
	opts = opts or {}
	local ok, err = pcall(vim.system, vim.list_extend({ M.cmd }, args), { text = true, stdin = opts.stdin }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				return callback(nil, failure(result))
			end
			if opts.raw then
				return callback(result.stdout)
			end
			callback(decode(result.stdout))
		end)
	end)
	if not ok then
		vim.schedule(function()
			callback(nil, tostring(err):match("ENOENT") and install_hint or tostring(err))
		end)
	end
end

--- Same as `run`, blocking; for previews that must fill synchronously.
function M.run_sync(args, opts)
	opts = opts or {}
	local ok, job = pcall(vim.system, vim.list_extend({ M.cmd }, args), { text = true })
	if not ok then
		return nil, install_hint
	end
	local result = job:wait()
	if result.code ~= 0 then
		return nil, failure(result)
	end
	if opts.raw then
		return result.stdout
	end
	return decode(result.stdout)
end

--- Starts `kuroneko play`; `on_position(ms)` gets each reported position.
function M.play(args, on_position, on_exit)
	local pending = ""
	local ok, job = pcall(vim.system, vim.list_extend({ M.cmd, "play" }, args), {
		text = true,
		stdout = function(_, data)
			if not data then
				return
			end
			pending = pending .. data
			for line in pending:gmatch("([^\n]*)\n") do
				local value = decode(line)
				if value and value.positionMs then
					vim.schedule(function()
						on_position(value.positionMs, value.done)
					end)
				end
			end
			pending = pending:match("[^\n]*$")
		end,
	}, function(result)
		vim.schedule(function()
			on_exit(result.code ~= 0 and result.signal == 0 and failure(result) or nil)
		end)
	end)
	if not ok then
		vim.schedule(function()
			on_exit(install_hint)
		end)
		return nil
	end
	return job
end

return M
