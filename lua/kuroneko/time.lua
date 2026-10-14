-- Dates come from the command as UTC ISO 8601; people read them local and
-- in Portuguese.
local M = {}

local weekdays = { "dom", "seg", "ter", "qua", "qui", "sex", "sáb" }

--- 03:21 or 1:03:21.
function M.clock(ms)
	local total = math.max(0, math.floor(ms / 1000))
	local h, m, s = math.floor(total / 3600), math.floor(total % 3600 / 60), total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

--- "03:21" / "1:03:21" to milliseconds.
function M.parse_clock(text)
	local parts = vim.split(text, ":", { plain = true })
	local total = 0
	for _, part in ipairs(parts) do
		local n = tonumber(part)
		if not n then
			return nil
		end
		total = total * 60 + n
	end
	return total * 1000
end

--- Epoch seconds of "2026-10-14T12:15:12Z".
function M.parse_iso(text)
	local y, mo, d, h, mi, s = (text or ""):match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	-- os.time reads the table as local time; shift by the local UTC offset.
	local now = os.time()
	local offset = os.difftime(os.time(os.date("*t", now)), os.time(os.date("!*t", now)))
	return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s, isdst = false }) + offset
end

--- "qua 14/10 09:15".
function M.day(iso)
	local epoch = M.parse_iso(iso)
	if not epoch then
		return ""
	end
	return weekdays[tonumber(os.date("%w", epoch)) + 1] .. " " .. os.date("%d/%m %H:%M", epoch)
end

--- "09:15".
function M.hm(iso)
	local epoch = M.parse_iso(iso)
	return epoch and os.date("%H:%M", epoch) or ""
end

function M.duration(ms)
	if not ms then
		return nil
	end
	local minutes = math.max(1, math.floor(ms / 60000))
	if minutes < 60 then
		return minutes .. " min"
	end
	return string.format("%dh%02d", math.floor(minutes / 60), minutes % 60)
end

return M
