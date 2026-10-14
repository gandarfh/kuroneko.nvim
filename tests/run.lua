-- Runs every tests/*_test.lua in a headless Neovim with a fake `kuroneko`:
--   nvim --headless --clean -c "luafile tests/run.lua"
-- Exits with 1 when a test fails.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.cmd.runtime("plugin/kuroneko.lua")
require("kuroneko").setup({})

local H = dofile(root .. "/tests/helpers.lua")

local tests = {}
local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

for _, file in ipairs(vim.fn.glob(root .. "/tests/*_test.lua", false, true)) do
	loadfile(file)(test, H)
end

local failed = 0
for _, case in ipairs(tests) do
	H.reset()
	local ok, err = xpcall(case.fn, debug.traceback)
	io.write((ok and "ok    " or "FAIL  ") .. case.name .. "\n")
	if not ok then
		failed = failed + 1
		io.write(err .. "\n")
	end
end
io.write(string.format("\n%d tests, %d failed\n", #tests, failed))
vim.cmd(failed > 0 and "cquit 1" or "qall!")
